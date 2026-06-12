// R4g differential: deblock_stream.sv vs the C model's final output.
// Same inputs as the frame-buffer bench (rec dump + per-MB qp from the
// coefficient dump headers); the row stream reassembles into a frame
// that must match the golden .yuv crop window.
//   usage: Vdeblock_stream coef rec yuv W H cqp aoff boff
#include <cstdio>
#include <cstring>
#include <vector>

#include "Vdeblock_stream.h"
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
    if (!nrec || pb.size() / sizeof(PixRec) != nrec) {
        printf("[SKIP] inputs\n");
        return 1;
    }
    const CoefRec *cr = (const CoefRec *)cb.data();
    const PixRec *pr = (const PixRec *)pb.data();
    int mb_w = (W + 15) / 16, mb_h = (H + 15) / 16;

    // reassembly frame (MB-aligned)
    int FW = mb_w * 16, FH = mb_h * 16;
    std::vector<uint8_t> fy(FW * FH, 0), fu(FW / 2 * FH / 2, 0),
        fv(FW / 2 * FH / 2, 0);

    Vdeblock_stream top;
    auto collect = [&] {
        if (!top.out_valid) return;
        int x = top.out_mbx, y = top.out_mby, r = top.out_row;
        if (top.out_plane == 0) {
            for (int i = 0; i < 16; i++)
                fy[(y * 16 + r) * FW + x * 16 + i] =
                    (uint8_t)((top.out_data[i / 4] >> ((i % 4) * 8)) & 0xFF);
        } else {
            auto &pl = (top.out_plane == 1) ? fu : fv;
            for (int i = 0; i < 8; i++)
                pl[(y * 8 + r) * (FW / 2) + x * 8 + i] =
                    (uint8_t)((top.out_data[i / 4] >> ((i % 4) * 8)) & 0xFF);
        }
    };
    auto tick = [&] {
        top.clk = 0;
        top.eval();
        top.clk = 1;
        top.eval();
        collect();
    };
    top.rst_n = 0;
    top.mb_push = 0;
    top.flush = 0;
    tick();
    top.rst_n = 1;
    tick();
    top.cfg_mb_w = (uint8_t)mb_w;
    top.cfg_mb_h = (uint8_t)mb_h;
    top.cfg_cqp_off = (uint8_t)(cqp & 0x3F);
    top.cfg_a_off = (uint8_t)(aoff & 0x3F);
    top.cfg_enable = 1;
    top.cfg_b_off = (uint8_t)(boff & 0x3F);

    long guard = 0;
    for (size_t rix = 0; rix < nrec; rix++) {
        while (!top.mb_ready && guard++ < 2000000) tick();
        top.mb_push = 1;
        top.mb_x = cr[rix].hdr[0];
        top.mb_y = cr[rix].hdr[2];
        top.mb_qp = cr[rix].hdr[5];
        for (int i = 0; i < 256; i++) top.in_y[i] = pr[rix].y[i];
        for (int i = 0; i < 64; i++) {
            top.in_u[i] = pr[rix].u[i];
            top.in_v[i] = pr[rix].v[i];
        }
        tick();
        top.mb_push = 0;
    }
    while (!top.mb_ready && guard++ < 2000000) tick();
    top.flush = 1;
    tick();
    top.flush = 0;
    while (!top.flush_done && guard++ < 2000000) tick();
    if (guard >= 2000000) {
        printf("[FAIL] timeout\n");
        return 1;
    }

    const uint8_t *gy = gb.data();
    const uint8_t *gu = gy + W * H;
    const uint8_t *gv = gu + (W / 2) * (H / 2);
    int fails = 0;
    for (int y = 0; y < H && fails < 5; y++)
        for (int x = 0; x < W && fails < 5; x++)
            if (fy[y * FW + x] != gy[y * W + x]) {
                printf("[FAIL] Y(%d,%d) rtl=%d c=%d\n", x, y, fy[y * FW + x],
                       gy[y * W + x]);
                fails++;
            }
    for (int y = 0; y < H / 2 && fails < 5; y++)
        for (int x = 0; x < W / 2 && fails < 5; x++) {
            if (fu[y * (FW / 2) + x] != gu[y * (W / 2) + x]) {
                printf("[FAIL] U(%d,%d) rtl=%d c=%d\n", x, y,
                       fu[y * (FW / 2) + x], gu[y * (W / 2) + x]);
                fails++;
            }
            if (fv[y * (FW / 2) + x] != gv[y * (W / 2) + x]) {
                printf("[FAIL] V(%d,%d) rtl=%d c=%d\n", x, y,
                       fv[y * (FW / 2) + x], gv[y * (W / 2) + x]);
                fails++;
            }
        }

    if (!fails) {
        printf("[PASS] deblock_stream: %dx%d frame bit-exact\n", W, H);
        return 0;
    }
    return 1;
}
