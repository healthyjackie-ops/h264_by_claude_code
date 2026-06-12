// P-R1 differential: mc_core vs c_model mc.o. Random reference planes,
// random positions (including off-edge for clamp coverage), all phases.
#include <cstdio>
#include <cstring>
#include <random>

#include "Vmc_wrap.h"
#include "verilated.h"

extern "C" {
#include "mc.h"
}

namespace {
int clampi(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::mt19937 rng(20260612);
    Vmc_wrap top;

    const int PW = 48, PH = 32;
    uint8_t plane[PH * PW];

    int fails = 0;
    long done = 0;
    for (int trial = 0; trial < 60000 && fails == 0; trial++) {
        for (auto &p : plane) p = (uint8_t)(rng() & 0xFF);
        // positions biased to hit edges
        int x = (int)(rng() % (PW + 16)) - 8;
        int y = (int)(rng() % (PH + 16)) - 8;
        int lfx = (int)(rng() & 3), lfy = (int)(rng() & 3);
        int cfx = (int)(rng() & 7), cfy = (int)(rng() & 7);

        // C reference: 4x4 luma + 4x4 chroma
        uint8_t cl[16], cc[16];
        h264_mc_luma(plane, PW, PW, PH, x, y, lfx, lfy, cl, 4, 4, 4);
        h264_mc_chroma(plane, PW, PW, PH, x, y, cfx, cfy, cc, 4, 4, 4);

        // RTL windows with the same clamping
        for (int j = 0; j < 9; j++)
            for (int i = 0; i < 9; i++)
                top.lwin[j][i] = plane[clampi(y - 2 + j, 0, PH - 1) * PW +
                                       clampi(x - 2 + i, 0, PW - 1)];
        for (int j = 0; j < 5; j++)
            for (int i = 0; i < 5; i++)
                top.cwin[j][i] = plane[clampi(y + j, 0, PH - 1) * PW +
                                       clampi(x + i, 0, PW - 1)];
        top.lfx = (uint8_t)lfx;
        top.lfy = (uint8_t)lfy;
        top.cfx = (uint8_t)cfx;
        top.cfy = (uint8_t)cfy;
        top.eval();

        for (int i = 0; i < 16 && fails < 3; i++) {
            if (top.lpred[i] != cl[i]) {
                printf("[FAIL] t%d luma px%d f(%d,%d) rtl=%d c=%d\n",
                       trial, i, lfx, lfy, (int)top.lpred[i], cl[i]);
                fails++;
            }
            if (top.cpred[i] != cc[i]) {
                printf("[FAIL] t%d chroma px%d f(%d,%d) rtl=%d c=%d\n",
                       trial, i, cfx, cfy, (int)top.cpred[i], cc[i]);
                fails++;
            }
        }
        done++;
    }

    if (!fails) {
        printf("[PASS] mc_core: %ld trials (luma+chroma, all phases, "
               "edge clamps) bit-exact vs C model\n", done);
        return 0;
    }
    return 1;
}
