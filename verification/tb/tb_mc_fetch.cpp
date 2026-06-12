// P-R2 differential: mc_fetch + mc_core vs the C model's full MC path
// (coordinate derivation included). The bench is the memory system:
// it owns the reference plane and answers row reads with clamp
// semantics, one response per cycle.
#include <cstdio>
#include <cstring>
#include <random>

#include "Vmc_fetch.h"
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
    Vmc_fetch top;

    const int PW = 64, PH = 48;
    uint8_t plane[PH * PW];

    auto tick = [&] {
        // memory model: answer any pending row read before the edge
        top.rsp_valid = 0;
        if (top.req_valid) {
            int rx = (int16_t)(top.req_x << 3) >> 3;   // sign-extend 13b
            int ry = (int16_t)(top.req_y << 4) >> 4;   // sign-extend 12b
            int w = top.req_w;
            uint64_t hi = 0;
            uint8_t lo8 = 0;
            // pack pixels MSB-first into [71:0] = {hi[63:0], lo8}
            uint8_t px[9];
            for (int i = 0; i < w; i++)
                px[i] = plane[clampi(ry, 0, PH - 1) * PW +
                              clampi(rx + i, 0, PW - 1)];
            for (int i = w; i < 9; i++) px[i] = 0;
            for (int i = 0; i < 8; i++) hi = (hi << 8) | px[i];
            lo8 = px[8];
            top.rsp_data[0] = (uint32_t)((((uint64_t)lo8) |
                                          (hi << 8)) & 0xFFFFFFFF);
            top.rsp_data[1] = (uint32_t)(((hi << 8) | lo8) >> 32);
            top.rsp_data[2] = (uint32_t)(hi >> 56);
            top.rsp_valid = 1;
        }
        top.clk = 0;
        top.eval();
        top.clk = 1;
        top.eval();
    };

    top.rst_n = 0;
    top.start = 0;
    top.rsp_valid = 0;
    tick();
    top.rst_n = 1;
    tick();

    int fails = 0;
    long done = 0;
    for (int trial = 0; trial < 20000 && fails == 0; trial++) {
        for (auto &p : plane) p = (uint8_t)(rng() & 0xFF);
        int chroma = (int)(rng() & 1);
        int bx = (int)(rng() % (chroma ? (PW / 2 - 4) : (PW - 4))) & ~0;
        int by = (int)(rng() % (chroma ? (PH / 2 - 4) : (PH - 4)));
        // quarter/eighth-pel MVs reaching off-frame
        int mvx = (int)(rng() % 257) - 128;
        int mvy = (int)(rng() % 257) - 128;

        uint8_t cref[16];
        if (chroma) {
            h264_mc_chroma(plane, PW, PW, PH, bx + (mvx >> 3),
                           by + (mvy >> 3), mvx & 7, mvy & 7, cref, 4, 4, 4);
        } else {
            h264_mc_luma(plane, PW, PW, PH, bx + (mvx >> 2),
                         by + (mvy >> 2), mvx & 3, mvy & 3, cref, 4, 4, 4);
        }

        top.start = 1;
        top.is_chroma = chroma;
        top.px = (uint16_t)bx;
        top.py = (uint16_t)by;
        top.mvx = (uint16_t)(int16_t)mvx;
        top.mvy = (uint16_t)(int16_t)mvy;
        tick();
        top.start = 0;
        int guard = 0;
        while (!top.done && guard++ < 100) tick();
        if (!top.done) {
            printf("[FAIL] t%d timeout\n", trial);
            fails++;
            break;
        }
        for (int i = 0; i < 16 && fails < 3; i++) {
            if (top.pred[i] != cref[i]) {
                printf("[FAIL] t%d %s px%d mv(%d,%d) rtl=%d c=%d\n",
                       trial, chroma ? "C" : "L", i, mvx, mvy,
                       (int)top.pred[i], cref[i]);
                fails++;
            }
        }
        tick();
        done++;
    }

    if (!fails) {
        printf("[PASS] mc_fetch: %ld blocks (coords+phases+fetch) "
               "bit-exact vs C model\n", done);
        return 0;
    }
    return 1;
}
