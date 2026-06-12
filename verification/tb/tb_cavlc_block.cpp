// Replay test: cavlc_block.sv vs the C model's residual_block log.
//
// The log (H264_CAVLC_LOG, written by c_model cavlc.c) holds one record
// per residual block: nC class / maxc, the exact bits the C decoder
// consumed (MSB-first packed), and the decoded tc + 16 coefficients.
// Each record is fed to the RTL bitreader byte-wise; the block FSM must
// produce identical coefficients and consume exactly nbits.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <algorithm>

#include "Vcavlc_top.h"
#include "verilated.h"

namespace {

struct Rec {
    int nc;                       // -1 = chroma DC
    int maxc;
    int nbits;
    std::vector<uint8_t> bytes;   // ceil(nbits/8), MSB-first
    int tc;
    int16_t coefs[16];
};

bool read_log(const char *path, std::vector<Rec> &out) {
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    for (;;) {
        uint8_t hdr[4];
        if (fread(hdr, 1, 4, f) != 4) break;
        Rec r;
        r.nc = (int8_t)hdr[0];
        r.maxc = hdr[1];
        r.nbits = hdr[2] | (hdr[3] << 8);
        size_t nb = (size_t)((r.nbits + 7) / 8);
        r.bytes.resize(nb);
        if (fread(r.bytes.data(), 1, nb, f) != nb) { fclose(f); return false; }
        uint8_t tcb;
        if (fread(&tcb, 1, 1, f) != 1) { fclose(f); return false; }
        r.tc = tcb;
        if (fread(r.coefs, sizeof(int16_t), 16, f) != 16) {
            fclose(f);
            return false;
        }
        out.push_back(std::move(r));
    }
    fclose(f);
    return true;
}

}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const char *log = (argc > 1) ? argv[1] : "/tmp/cavlc.log";

    std::vector<Rec> recs;
    if (!read_log(log, recs) || recs.empty()) {
        printf("[SKIP] no log at %s\n", log);
        return 1;
    }

    Vcavlc_top top;
    auto tick = [&] {
        top.clk = 0;
        top.eval();
        top.clk = 1;
        top.eval();
    };

    int fails = 0;
    size_t ri = 0;
    for (const Rec &r : recs) {
        // reset per record: clean buffer state
        top.rst_n = 0;
        top.in_valid = 0;
        top.start = 0;
        tick();
        top.rst_n = 1;
        tick();

        // preload all record bytes (pad with a stop byte so lookahead
        // never starves; the FSM must not consume past nbits anyway)
        std::vector<uint8_t> feed = r.bytes;
        for (int i = 0; i < 8; i++) feed.push_back(0xAA);
        size_t fi = 0;
        while (fi < feed.size()) {
            int nb = (int)std::min<size_t>(4, feed.size() - fi);
            uint32_t w = 0;
            for (int k = 0; k < nb; k++)
                w |= (uint32_t)feed[fi + k] << (24 - k * 8);
            top.in_valid = top.in_ready ? 1 : 0;
            top.in_word = w;
            top.in_bytes = (uint8_t)nb;
            tick();
            if (top.in_valid) fi += top.in_bytes;
            top.in_valid = 0;
            if (top.avail >= 56) break;
        }

        int avail0 = top.avail;

        // command
        top.start = 1;
        top.chroma_dc = (r.nc == -1);
        top.nc_class = 0;
        if (r.nc >= 8) top.nc_class = 3;
        else if (r.nc >= 4) top.nc_class = 2;
        else if (r.nc >= 2) top.nc_class = 1;
        top.maxc = (uint8_t)r.maxc;
        tick();
        top.start = 0;

        int16_t got[16];
        memset(got, 0, sizeof(got));
        int guard = 0;
        bool finished = false;
        int tail = 0;
        // run until done/err, then 3 extra cycles: the final coef_we and
        // the last bit consume land on/after the done edge
        while (guard++ < 2000) {
            top.in_valid = 0;
            if (fi < feed.size() && top.in_ready) {
                int nb = (int)std::min<size_t>(4, feed.size() - fi);
                uint32_t w = 0;
                for (int k = 0; k < nb; k++)
                    w |= (uint32_t)feed[fi + k] << (24 - k * 8);
                top.in_valid = 1;
                top.in_word = w;
                top.in_bytes = (uint8_t)nb;
            }
            tick();
            if (top.in_valid) { fi += top.in_bytes; top.in_valid = 0; }
            if (top.coef_we) got[top.coef_addr] = (int16_t)top.coef_data;
            if (top.done || top.err) finished = true;
            if (finished && ++tail >= 3) break;
        }

        bool bad = false;
        if (top.err || !finished) {
            printf("[FAIL] rec %zu: %s (nc=%d maxc=%d nbits=%d)\n",
                   ri, top.err ? "err state" : "timeout", r.nc, r.maxc,
                   r.nbits);
            bad = true;
        }
        if (!bad && (int)top.tc_out != r.tc) {
            printf("[FAIL] rec %zu: tc rtl=%d c=%d\n", ri, (int)top.tc_out,
                   r.tc);
            bad = true;
        }
        if (!bad) {
            for (int k = 0; k < 16; k++) {
                if (got[k] != r.coefs[k]) {
                    printf("[FAIL] rec %zu: coef[%d] rtl=%d c=%d "
                           "(nc=%d maxc=%d)\n",
                           ri, k, got[k], r.coefs[k], r.nc, r.maxc);
                    bad = true;
                    break;
                }
            }
        }
        if (!bad) {
            // consumed = bits gone from the buffer + bytes pushed after
            long pushed = (long)fi * 8;
            long consumed = pushed - ((long)top.avail - 0) -
                            ((long)feed.size() - (long)fi) * 0;
            consumed = pushed - (long)top.avail;
            // avail0 bookkeeping: buffer had avail0 from same accounting
            (void)avail0;
            if (consumed != r.nbits) {
                printf("[FAIL] rec %zu: consumed %ld != %d bits\n", ri,
                       consumed, r.nbits);
                bad = true;
            }
        }
        if (bad && ++fails >= 5) break;
        ri++;
    }

    if (fails == 0) {
        printf("[PASS] cavlc_block: %zu blocks bit-exact vs C model\n",
               recs.size());
        return 0;
    }
    printf("%d failures of %zu records\n", fails, recs.size());
    return 1;
}
