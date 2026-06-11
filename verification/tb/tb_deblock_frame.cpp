// R3b differential: deblock_frame.sv vs the C model's final output.
//
// Inputs: the reconstruction dump (pre-deblock MB pixels), the
// coefficient dump (per-MB qp from its header), and the golden .yuv
// (post-deblock, cropped). The bench streams MBs in, runs the filter
// FSM, and compares the crop window of all three planes.
//   usage: Vdeblock_frame <coef.dump> <rec.dump> <golden.yuv>
//          <W> <H> <cqp_off> <a_off> <b_off>
#include <cstdio>
#include <cstring>
#include <vector>

#include "Vdeblock_frame.h"
#include "verilated.h"

namespace {
struct CoefRec {
    uint8_t hdr[8];
    uint8_t pad[832];
};
struct PixRec {
    uint8_t y[256];
    uint8_t u[64];
    uint8_t v[64];
};
std::vector<uint8_t> rd(const char *p) {
    std::vector<uint8_t> b;
    FILE *f = fopen(p, "rb");
    if (!f) return b;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    b.resize((size_t)n);
    if (fread(b.data(), 1, b.size(), f) != b.size()) b.clear();
    fclose(f);
    return b;
}
}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 9) {
        printf("usage: %s coef rec yuv W H cqp aoff boff\n", argv[0]);
        return 1;
    }
    auto cb = rd(argv[1]);
    auto pb = rd(argv[2]);
    auto gb = rd(argv[3]);
    int W = atoi(argv[4]), H = atoi(argv[5]);
    int cqp = atoi(argv[6]), aoff = atoi(argv[7]), boff = atoi(argv[8]);
    size_t nrec = cb.size() / sizeof(CoefRec);
    if (!nrec || pb.size() / sizeof(PixRec) != nrec ||
        gb.size() < (size_t)(W * H * 3 / 2)) {
        printf("[SKIP] bad inputs\n");
        return 1;
    }
    const CoefRec *cr = (const CoefRec *)cb.data();
    const PixRec *pr = (const PixRec *)pb.data();

    static const int MAXW = 320;

    Vdeblock_frame top;
    auto tick = [&] {
        top.clk = 0;
        top.eval();
        top.clk = 1;
        top.eval();
    };
    top.rst_n = 0;
    top.mb_push = 0;
    top.frame_go = 0;
    tick();
    top.rst_n = 1;
    tick();
    int mb_w = (W + 15) / 16, mb_h = (H + 15) / 16;
    top.cfg_mb_w = (uint8_t)mb_w;
    top.cfg_mb_h = (uint8_t)mb_h;
    top.cfg_cqp_off = (uint8_t)(cqp & 0x3F);
    top.cfg_a_off = (uint8_t)(aoff & 0x3F);
    top.cfg_b_off = (uint8_t)(boff & 0x3F);

    for (size_t r = 0; r < nrec; r++) {
        top.mb_push = 1;
        top.mb_x = cr[r].hdr[0];
        top.mb_y = cr[r].hdr[2];
        top.mb_qp = cr[r].hdr[5];
        for (int i = 0; i < 256; i++) top.in_y[i] = pr[r].y[i];
        for (int i = 0; i < 64; i++) {
            top.in_u[i] = pr[r].u[i];
            top.in_v[i] = pr[r].v[i];
        }
        tick();
        top.mb_push = 0;
    }
    top.frame_go = 1;
    tick();
    top.frame_go = 0;
    long guard = 0;
    while (!top.frame_done && guard++ < 2000000) tick();
    if (!top.frame_done) {
        printf("[FAIL] filter timeout\n");
        return 1;
    }

    auto rd_px = [&](int plane, int addr) -> uint8_t {
        top.rd_plane = (uint8_t)plane;
        top.rd_addr = (uint32_t)addr;
        top.eval();
        return top.rd_data;
    };

    const uint8_t *gy = gb.data();
    const uint8_t *gu = gy + W * H;
    const uint8_t *gv = gu + (W / 2) * (H / 2);
    int fails = 0;
    for (int y = 0; y < H && fails < 5; y++)
        for (int x = 0; x < W && fails < 5; x++) {
            uint8_t r = rd_px(0, y * MAXW + x);
            if (r != gy[y * W + x]) {
                printf("[FAIL] Y (%d,%d) rtl=%d c=%d\n", x, y, r,
                       gy[y * W + x]);
                fails++;
            }
        }
    for (int y = 0; y < H / 2 && fails < 5; y++)
        for (int x = 0; x < W / 2 && fails < 5; x++) {
            uint8_t u = rd_px(1, y * (MAXW / 2) + x);
            uint8_t v = rd_px(2, y * (MAXW / 2) + x);
            if (u != gu[y * (W / 2) + x]) {
                printf("[FAIL] U (%d,%d) rtl=%d c=%d\n", x, y, u,
                       gu[y * (W / 2) + x]);
                fails++;
            }
            if (v != gv[y * (W / 2) + x]) {
                printf("[FAIL] V (%d,%d) rtl=%d c=%d\n", x, y, v,
                       gv[y * (W / 2) + x]);
                fails++;
            }
        }

    if (fails == 0) {
        printf("[PASS] deblock_frame: %dx%d frame bit-exact vs C output\n",
               W, H);
        return 0;
    }
    return 1;
}
