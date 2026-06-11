// R3a differential: deblock_edge.sv vs the C model's filter_edge (test
// export) on random sample lines across all bS / threshold combos.
#include <cstdio>
#include <cstring>
#include <random>

#include "Vdeblock_edge.h"
#include "verilated.h"

extern "C" {
#include "deblock.h"
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::mt19937 rng(20260611);
    Vdeblock_edge top;

    int fails = 0;
    for (int trial = 0; trial < 200000 && fails == 0; trial++) {
        uint8_t s[8];
        int correlated = (int)(rng() % 2);
        if (correlated) {
            // smooth-ish line so the filter conditions actually fire
            int base = (int)(rng() % 200) + 28;
            for (int i = 0; i < 8; i++)
                s[i] = (uint8_t)(base + (int)(rng() % 9) - 4);
        } else {
            for (auto &x : s) x = (uint8_t)(rng() & 0xFF);
        }
        int bs = (int)(rng() % 5);
        int ia = (int)(rng() % 52);
        int chroma = (int)(rng() & 1);
        int alpha = 0, beta = 0, tc0 = 0;
        // pull thresholds straight from the C tables via an edge run with
        // index ia — instead just compute via known C arrays: use the
        // exported filter directly with chosen alpha/beta/tc0 values.
        // We mimic h264_deblock_frame's table reads by sampling typical
        // values: alpha in [0,255], beta in [0,18], tc0 in [0,25].
        alpha = (int)(rng() % 256);
        beta = (int)(rng() % 19);
        tc0 = (int)(rng() % 26);

        top.p3 = s[0]; top.p2 = s[1]; top.p1 = s[2]; top.p0 = s[3];
        top.q0 = s[4]; top.q1 = s[5]; top.q2 = s[6]; top.q3 = s[7];
        top.alpha = (uint8_t)alpha;
        top.beta = (uint8_t)beta;
        top.bs = (uint8_t)bs;
        top.tc0 = (uint8_t)tc0;
        top.chroma = (uint8_t)chroma;
        top.eval();

        // C reference: build a line with stride layout matching
        // filter_edge(q0p, pstep, lstep, len=1, ...)
        uint8_t line[8];
        memcpy(line, s, 8);
        int bs4[4] = {bs, bs, bs, bs};
        int tc04[4] = {tc0, tc0, tc0, tc0};
        h264_filter_edge_test(line + 4, 1, 8, 1, alpha, beta, bs4, tc04,
                              4, chroma);

        uint8_t rtl[8] = {s[0], top.o_p2, top.o_p1, top.o_p0,
                          top.o_q0, top.o_q1, top.o_q2, s[7]};
        for (int i = 0; i < 8 && !fails; i++) {
            if (rtl[i] != line[i]) {
                printf("[FAIL] t%d pos%d rtl=%d c=%d (bs=%d a=%d b=%d "
                       "tc0=%d ch=%d s=[%d %d %d %d|%d %d %d %d])\n",
                       trial, i, rtl[i], line[i], bs, alpha, beta, tc0,
                       chroma, s[0], s[1], s[2], s[3], s[4], s[5], s[6],
                       s[7]);
                fails++;
            }
        }
    }

    if (fails == 0) {
        printf("[PASS] deblock_edge: 200000 random lines bit-exact "
               "vs C model\n");
        return 0;
    }
    return 1;
}
