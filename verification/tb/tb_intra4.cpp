// R2b differential: intra4x4_pred.sv vs c_model intra.o. Random
// neighbors and availability across all nine modes; the C side builds a
// small plane so the function reads the same neighbor values.
#include <cstdio>
#include <cstring>
#include <random>

#include "Vintra4x4_pred.h"
#include "verilated.h"

extern "C" {
#include "intra.h"
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::mt19937 rng(20260611);
    Vintra4x4_pred top;

    int fails = 0;
    long checked = 0;
    for (int trial = 0; trial < 40000 && fails == 0; trial++) {
        uint8_t plane[9 * 16];          // 9 rows x 16 cols, block at (4,1)
        for (auto &p : plane) p = (uint8_t)(rng() & 0xFF);
        const size_t stride = 16;
        uint8_t *dst = plane + 1 * stride + 4;

        int aL = (int)(rng() & 1), aT = (int)(rng() & 1);
        int aTL = (int)(rng() & 1), aTR = (int)(rng() & 1);
        int mode = (int)(rng() % 9);

        // RTL neighbor ports (with the C function's TR substitution)
        for (int y = 0; y < 4; y++) top.l[y] = dst[y * stride - 1];
        for (int x = 0; x < 4; x++) top.t[x] = dst[-(int)stride + x];
        for (int x = 4; x < 8; x++) {
            top.t[x] = aTR ? dst[-(int)stride + x]
                           : dst[-(int)stride + 3];
        }
        top.tl = dst[-(int)stride - 1];
        top.avail_left = aL;
        top.avail_top = aT;
        top.avail_topleft = aTL;
        top.mode = (uint8_t)mode;
        top.eval();

        uint8_t cplane[9 * 16];
        memcpy(cplane, plane, sizeof(plane));
        uint8_t *cdst = cplane + 1 * stride + 4;
        int rc = h264_intra4x4_pred(cdst, stride, mode, aL, aT, aTL, aTR);

        if ((rc == 0) != (top.ok != 0)) {
            printf("[FAIL] t%d mode %d: ok rtl=%d c=%d (aL%d aT%d aTL%d)\n",
                   trial, mode, (int)top.ok, rc == 0 ? 1 : 0, aL, aT, aTL);
            fails++;
            continue;
        }
        if (rc != 0) continue;
        checked++;
        for (int y = 0; y < 4 && !fails; y++)
            for (int x = 0; x < 4 && !fails; x++) {
                uint8_t r = top.pred[y * 4 + x];
                uint8_t cv = cdst[y * stride + x];
                if (r != cv) {
                    printf("[FAIL] t%d mode %d (%d,%d): rtl=%d c=%d\n",
                           trial, mode, x, y, r, cv);
                    fails++;
                }
            }
    }

    if (fails == 0) {
        printf("[PASS] intra4x4_pred: 40000 trials (%ld valid) bit-exact "
               "vs C model\n", checked);
        return 0;
    }
    return 1;
}
