// Differential test: bitreader.sv + expgolomb.sv vs the C model's bs_*.
//
// Feeds the same random byte stream to both sides, then issues a random
// mix of u(n) / ue / se reads. The C side uses bitstream.o directly; the
// RTL side drives the bitreader consume port and, for ue/se, checks the
// combinational expgolomb outputs against the C values before retiring
// `len` bits. Exit 0 on full agreement.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <vector>

#include "Vbr_eg_top.h"
#include "verilated.h"

extern "C" {
#include "bitstream.h"
}

namespace {

struct Dut {
    Vbr_eg_top top;
    uint64_t cycles = 0;

    void tick() {
        top.clk = 0;
        top.eval();
        top.clk = 1;
        top.eval();
        cycles++;
    }

    void reset() {
        top.rst_n = 0;
        top.in_valid = 0;
        top.req_valid = 0;
        tick();
        tick();
        top.rst_n = 1;
        tick();
    }
};

}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::mt19937 rng(20260611);

    int fails = 0;
    for (int trial = 0; trial < 200 && fails == 0; trial++) {
        // random stream, ue-friendly: bias toward set bits so exp-golomb
        // codes stay within the supported 11-leading-zero range
        std::vector<uint8_t> bytes(512);
        for (auto &b : bytes) {
            b = (uint8_t)(rng() | (rng() & rng() ? 0x11 : 0));
        }

        bs_t bs;
        bs_init(&bs, bytes.data(), bytes.size());

        Dut d;
        d.reset();

        size_t feed = 0;
        auto pump = [&] {
            d.top.in_valid = 0;
            if (feed < bytes.size() && d.top.in_ready) {
                int nb = (int)std::min<size_t>(4, bytes.size() - feed);
                uint32_t w = 0;
                for (int k = 0; k < nb; k++)
                    w |= (uint32_t)bytes[feed + k] << (24 - k * 8);
                d.top.in_valid = 1;
                d.top.in_word = w;
                d.top.in_bytes = (uint8_t)nb;
            }
        };

        // prefill
        for (int i = 0; i < 16; i++) {
            pump();
            d.tick();
            if (d.top.in_valid) feed += d.top.in_bytes;
        }

        for (int op = 0; op < 600; op++) {
            int kind = (int)(rng() % 3);

            // make sure ample bits are buffered and C side has room
            while (d.top.avail < 32 && feed < bytes.size()) {
                pump();
                d.tick();
                if (d.top.in_valid) feed += d.top.in_bytes;
            }
            if (bs.byte + 8 > bytes.size()) break;

            uint32_t c_val;
            int rtl_len;
            uint32_t rtl_val;
            const char *what;
            if (kind == 0) {
                int n = 1 + (int)(rng() % 16);
                what = "u(n)";
                c_val = bs_u(&bs, n);
                rtl_val = (d.top.show >> (24 - n)) & ((1u << n) - 1);
                rtl_len = n;
            } else if (kind == 1) {
                what = "ue";
                uint32_t peek = (d.top.show);
                // skip if code longer than supported window
                bool marker = false;
                for (int i = 0; i <= 11; i++) {
                    if (peek & (1u << (23 - i))) { marker = true; break; }
                }
                if (!marker) continue;
                c_val = bs_ue(&bs);
                if (!d.top.eg_ok) {
                    printf("[FAIL] trial %d op %d: eg_ok low on valid code\n",
                           trial, op);
                    fails++;
                    break;
                }
                rtl_val = d.top.eg_ue;
                rtl_len = d.top.eg_len;
            } else {
                what = "se";
                uint32_t peek = (d.top.show);
                bool marker = false;
                for (int i = 0; i <= 11; i++) {
                    if (peek & (1u << (23 - i))) { marker = true; break; }
                }
                if (!marker) continue;
                int32_t sc = bs_se(&bs);
                c_val = (uint32_t)sc;
                rtl_val = (uint32_t)(int32_t)(int16_t)
                          ((int16_t)(d.top.eg_se << 4) >> 4);  // sign-extend 12b
                rtl_len = d.top.eg_len;
            }

            if (rtl_val != c_val) {
                printf("[FAIL] trial %d op %d %s: rtl=%d c=%d (show=%06x)\n",
                       trial, op, what, (int)rtl_val, (int)c_val,
                       (unsigned)d.top.show);
                fails++;
                break;
            }

            // retire bits on the RTL side
            d.top.req_valid = 1;
            d.top.req_bits = (uint8_t)rtl_len;
            pump();
            d.tick();
            if (d.top.in_valid) feed += d.top.in_bytes;
            d.top.req_valid = 0;
        }
    }

    if (fails == 0) {
        printf("[PASS] bitreader+expgolomb: 200 trials x ~600 ops "
               "bit-exact vs C model\n");
        return 0;
    }
    return 1;
}
