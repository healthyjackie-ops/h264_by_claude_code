// W15-a differential: cabac_core vs the C arithmetic decoder.
// Both engines consume the same random RBSP bytes and execute the same
// random op sequence (decision over random contexts / bypass /
// terminate); every bin must match. A terminate hit re-inits both
// sides with a fresh qp/model/stream.
#include <cstdio>
#include <cstring>
#include <random>
#include <vector>

#include "Vcabac_core.h"
#include "verilated.h"

extern "C" {
#include "cabac.h"
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::mt19937 rng(20260612);
    Vcabac_core top;

    std::vector<uint8_t> data(1 << 16);
    size_t bitpos = 0;

    auto feed = [&] {
        // bitreader-style window: 24 bits at bitpos, zero past the end
        uint32_t w = 0;
        for (int i = 0; i < 24; i++) {
            size_t b = bitpos + i;
            uint32_t bit = (b >> 3) < data.size()
                ? (data[b >> 3] >> (7 - (b & 7))) & 1 : 0;
            w = (w << 1) | bit;
        }
        top.show = w;
        size_t rem = data.size() * 8 - bitpos;
        top.avail = rem > 64 ? 64 : (uint8_t)rem;
    };
    auto tick = [&] {
        feed();
        top.clk = 0;
        top.eval();
        // same-beat consumption: sample the request BEFORE the edge
        int rv = top.req_valid, rb = top.req_bits;
        top.clk = 1;
        top.eval();
        if (rv) bitpos += rb;
    };

    top.rst_n = 0;
    top.init_start = 0;
    top.op_valid = 0;
    tick();
    top.rst_n = 1;
    tick();

    cabac_t ref;
    long bins = 0;
    int fails = 0;

    for (int trial = 0; trial < 400 && !fails; trial++) {
        for (auto &b : data) b = (uint8_t)(rng() & 0xFF);
        bitpos = 0;
        int qp = (int)(rng() % 52);
        int model = (int)(rng() % 4);            // 3 = I table

        cabac_init(&ref, data.data(), data.size(), 0, qp,
                   model == 3 ? -1 : model);

        top.init_start = 1;
        top.init_qp = (uint8_t)qp;
        top.init_model = (uint8_t)model;
        tick();
        top.init_start = 0;
        int guard = 0;
        while (top.init_busy && guard++ < 1000) tick();
        if (top.init_busy) {
            printf("[FAIL] t%d init timeout\n", trial);
            fails++;
            break;
        }

        for (int o = 0; o < 4000 && !fails; o++) {
            uint32_t r = rng();
            int op = (r % 16 == 0) ? 2 : (r % 3 == 0) ? 1 : 0;
            int ctx = (int)((r >> 8) % H264_CABAC_NCTX);

            int cbin;
            if (op == 0) cbin = cabac_decision(&ref, ctx);
            else if (op == 1) cbin = cabac_bypass(&ref);
            else cbin = cabac_terminate(&ref);

            top.op_valid = 1;
            top.op = (uint8_t)op;
            top.op_ctx = (uint16_t)ctx;
            int g2 = 0;
            // op executes on its accept beat; sample bin pre-edge
            int rbin = -1;
            while (g2++ < 100) {
                feed();
                top.eval();
                if (top.op_ready) {
                    rbin = top.bin;
                    tick();
                    break;
                }
                tick();
            }
            top.op_valid = 0;
            if (rbin < 0) {
                printf("[FAIL] t%d op%d stuck (op=%d)\n", trial, o, op);
                fails++;
                break;
            }
            if (rbin != cbin) {
                printf("[FAIL] t%d op%d %s ctx=%d rtl=%d c=%d\n", trial,
                       o, op == 0 ? "dec" : op == 1 ? "byp" : "term",
                       ctx, rbin, cbin);
                fails++;
                break;
            }
            if (getenv("CABAC_TRACE") && trial == 0 && o < 8)
                printf("op%d %s ctx=%d bin=%d | rtl r=%d v=%d | "
                       "c r=%u v=%u\n", o,
                       op == 0 ? "dec" : op == 1 ? "byp" : "term", ctx,
                       cbin, (int)top.dbg_range, (int)top.dbg_value,
                       ref.range, ref.value);
            bins++;
            if (op == 2 && cbin) break;          // terminate hit: re-init
            if (ref.error) break;                // stream exhausted
        }
    }

    if (!fails) {
        printf("[PASS] cabac_core: %ld bins bit-exact vs C engine "
               "(dec/byp/term, 400 streams)\n", bins);
        return 0;
    }
    return 1;
}
