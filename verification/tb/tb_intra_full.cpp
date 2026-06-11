// R2b differential: intra16_pred + chroma_pred vs c_model intra.o.
#include <cstdio>
#include <cstring>
#include <random>

#include "Vintra_wrap.h"
#include "verilated.h"

extern "C" {
#include "intra.h"
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::mt19937 rng(20260611);
    Vintra_wrap top;

    int fails = 0;
    long c16 = 0, cch = 0;
    for (int trial = 0; trial < 20000 && fails == 0; trial++) {
        // 16x16 block at (16,1) inside a 17x48 plane
        uint8_t plane[17 * 48];
        for (auto &p : plane) p = (uint8_t)(rng() & 0xFF);
        const size_t stride = 48;
        uint8_t *dst = plane + stride + 16;

        int aL = (int)(rng() & 1), aT = (int)(rng() & 1);
        int mode = (int)(rng() % 4);

        for (int y = 0; y < 16; y++) top.l16[y] = dst[y * stride - 1];
        for (int x = 0; x < 16; x++) top.t16[x] = dst[-(int)stride + x];
        top.tl16 = dst[-(int)stride - 1];
        for (int y = 0; y < 8; y++) top.lc[y] = dst[y * stride - 1];
        for (int x = 0; x < 8; x++) top.tc[x] = dst[-(int)stride + x];
        top.tlc = dst[-(int)stride - 1];
        top.avail_left = aL;
        top.avail_top = aT;
        top.mode = (uint8_t)mode;
        top.eval();

        // I16 reference
        uint8_t cp[17 * 48];
        memcpy(cp, plane, sizeof(plane));
        int rc = h264_intra16x16_pred(cp + stride + 16, stride, mode, aL, aT);
        if ((rc == 0) != (top.ok16 != 0)) {
            printf("[FAIL] t%d i16 mode %d ok rtl=%d c=%d\n", trial, mode,
                   (int)top.ok16, rc == 0);
            fails++;
        } else if (rc == 0) {
            c16++;
            for (int i = 0; i < 256 && !fails; i++) {
                uint8_t r = top.p16[i];
                uint8_t cv = cp[stride + 16 + (i / 16) * stride + (i % 16)];
                if (r != cv) {
                    printf("[FAIL] t%d i16 mode %d px%d rtl=%d c=%d\n",
                           trial, mode, i, r, cv);
                    fails++;
                }
            }
        }

        // chroma reference
        memcpy(cp, plane, sizeof(plane));
        rc = h264_intra_chroma_pred(cp + stride + 16, stride, mode, aL, aT);
        if ((rc == 0) != (top.okc != 0)) {
            printf("[FAIL] t%d ch mode %d ok rtl=%d c=%d\n", trial, mode,
                   (int)top.okc, rc == 0);
            fails++;
        } else if (rc == 0) {
            cch++;
            for (int i = 0; i < 64 && !fails; i++) {
                uint8_t r = top.pc[i];
                uint8_t cv = cp[stride + 16 + (i / 8) * stride + (i % 8)];
                if (r != cv) {
                    printf("[FAIL] t%d ch mode %d px%d rtl=%d c=%d\n",
                           trial, mode, i, r, cv);
                    fails++;
                }
            }
        }
    }

    if (fails == 0) {
        printf("[PASS] intra16+chroma: 20000 trials (%ld+%ld valid) "
               "bit-exact vs C model\n", c16, cch);
        return 0;
    }
    return 1;
}
