// R2c differential: mb_recon.sv vs the C model's reconstruction dump.
//
// Decoupled from mb_dec: the coefficient layer comes straight from
// H264_RTL_DUMP (840-byte records), pushed through the coef port; the
// golden pixels come from H264_RTL_DUMP_REC (384-byte records). The MB
// loop replays in decode order so the line buffers see the same history.
#include <cstdio>
#include <cstring>
#include <vector>

#include "Vmb_recon.h"
#include "verilated.h"

namespace {

struct CoefRec {
    uint8_t hdr[8];
    uint8_t i4m[16];
    int16_t resid[16][16];
    int16_t dcraw[16];
    int16_t cdc[2][4];
    int16_t cres[2][4][16];
};
struct PixRec {
    uint8_t y[256];
    uint8_t u[64];
    uint8_t v[64];
};

std::vector<uint8_t> read_file(const char *p) {
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
    if (argc < 5) {
        printf("usage: %s <coef.dump> <rec.dump> <mb_w> <cqp_off>\n",
               argv[0]);
        return 1;
    }
    auto cb = read_file(argv[1]);
    auto rb = read_file(argv[2]);
    int mb_w = atoi(argv[3]);
    int cqp = atoi(argv[4]);
    if (cb.empty() || rb.empty() || cb.size() % sizeof(CoefRec) ||
        rb.size() % sizeof(PixRec) ||
        cb.size() / sizeof(CoefRec) != rb.size() / sizeof(PixRec)) {
        printf("[SKIP] bad dumps (%zu/%zu)\n", cb.size(), rb.size());
        return 1;
    }
    size_t nrec = cb.size() / sizeof(CoefRec);
    const CoefRec *cr = (const CoefRec *)cb.data();
    const PixRec *pr = (const PixRec *)rb.data();

    Vmb_recon top;
    auto tick = [&] {
        top.clk = 0;
        top.eval();
        top.clk = 1;
        top.eval();
    };
    top.rst_n = 0;
    top.coef_we = 0;
    top.mb_valid = 0;
    tick();
    top.rst_n = 1;
    tick();
    top.cfg_mb_w = (uint8_t)mb_w;
    top.cfg_cqp_off = (uint8_t)(cqp & 0x3F);

    auto push = [&](int blk, int addr, int16_t v) {
        if (!v && blk != 16 && blk < 17) {
            // zeros matter only где cram could hold stale data; cram is
            // cleared each MB, so skip zero writes to save cycles
        }
        if (v == 0) return;
        top.coef_we = 1;
        top.coef_blk = (uint8_t)blk;
        top.coef_addr = (uint8_t)addr;
        top.coef_data = (uint16_t)v;
        tick();
        top.coef_we = 0;
    };

    int fails = 0;
    for (size_t r = 0; r < nrec && fails == 0; r++) {
        const CoefRec &c = cr[r];
        // stream coefficients
        for (int b = 0; b < 16; b++)
            for (int i = 0; i < 16; i++) push(b, i, c.resid[b][i]);
        for (int i = 0; i < 16; i++) push(16, i, c.dcraw[i]);
        for (int cc = 0; cc < 2; cc++)
            for (int i = 0; i < 4; i++) push(17 + cc, i, c.cdc[cc][i]);
        for (int cc = 0; cc < 2; cc++)
            for (int k = 0; k < 4; k++)
                for (int i = 0; i < 16; i++)
                    push(19 + cc * 4 + k, i, c.cres[cc][k][i]);

        // header pulse
        top.mb_valid = 1;
        top.mb_x = c.hdr[0];
        top.mb_y = c.hdr[2];
        top.mb_i16 = c.hdr[3] == 1;
        top.mb_cbp = c.hdr[4];
        top.mb_qp = c.hdr[5];
        top.mb_i16_mode = c.hdr[6];
        top.mb_cmode = c.hdr[7];
        uint64_t i4m = 0;
        for (int i = 0; i < 16; i++)
            i4m |= ((uint64_t)(c.i4m[i] & 0xF)) << (i * 4);
        top.mb_i4m = i4m;
        tick();
        top.mb_valid = 0;

        int guard = 0;
        while (!top.rec_valid && !top.err && guard++ < 500) tick();
        if (top.err || guard >= 500) {
            printf("[FAIL] MB %zu: %s\n", r, top.err ? "err" : "timeout");
            fails++;
            break;
        }

        for (int i = 0; i < 256 && !fails; i++) {
            if (top.rec_y[i] != pr[r].y[i]) {
                printf("[FAIL] MB %zu y[%d] (%d,%d) rtl=%d c=%d "
                       "(i16=%d cbp=%02x)\n",
                       r, i, i % 16, i / 16, (int)top.rec_y[i], pr[r].y[i],
                       c.hdr[3], c.hdr[4]);
                fails++;
            }
        }
        for (int i = 0; i < 64 && !fails; i++) {
            if (top.rec_u[i] != pr[r].u[i]) {
                printf("[FAIL] MB %zu u[%d] rtl=%d c=%d\n", r, i,
                       (int)top.rec_u[i], pr[r].u[i]);
                fails++;
            }
            if (top.rec_v[i] != pr[r].v[i]) {
                printf("[FAIL] MB %zu v[%d] rtl=%d c=%d\n", r, i,
                       (int)top.rec_v[i], pr[r].v[i]);
                fails++;
            }
        }
        tick();                        // leave S_OUT
    }

    if (fails == 0) {
        printf("[PASS] mb_recon: %zu MBs bit-exact vs C reconstruction\n",
               nrec);
        return 0;
    }
    return 1;
}
