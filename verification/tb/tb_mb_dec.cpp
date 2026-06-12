// R1c differential test: mb_top (bitreader + mb_dec + cavlc_block) vs
// the C model's H264_RTL_DUMP records over a real baseline-I stream.
//
// The C model side of the comparison is pre-generated:
//   H264_RTL_DUMP=<f>.dump build/h264_decode <f>.264 /dev/null
// This bench re-parses the stream's headers with the linked C objects
// (nal/params/slice/bitstream) to find slice_data and the config, feeds
// the RBSP into the RTL, and rebuilds each 840-byte record from the
// header pulses + coefficient stream for memcmp against the dump.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "Vmb_top.h"
#include "verilated.h"

extern "C" {
#include "bitstream.h"
#include "nal.h"
#include "params.h"
#include "slice.h"
}

namespace {

struct Rec {
    uint8_t hdr[8];
    uint8_t i4m[16];
    int16_t resid[16][16];
    int16_t dcraw[16];
    int16_t cdc[2][4];
    int16_t cres[2][4][16];
};

std::vector<uint8_t> read_file(const char *p) {
    std::vector<uint8_t> v;
    FILE *f = fopen(p, "rb");
    if (!f) return v;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    v.resize((size_t)n);
    if (fread(v.data(), 1, v.size(), f) != v.size()) v.clear();
    fclose(f);
    return v;
}

}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) {
        printf("usage: %s <stream.264> <golden.dump>\n", argv[0]);
        return 1;
    }
    auto stream = read_file(argv[1]);
    auto dumpb = read_file(argv[2]);
    if (stream.empty() || dumpb.empty() ||
        dumpb.size() % sizeof(Rec) != 0) {
        printf("[SKIP] bad inputs (dump %zu bytes, rec %zu)\n",
               dumpb.size(), sizeof(Rec));
        return 1;
    }
    size_t nrec = dumpb.size() / sizeof(Rec);
    const Rec *gold = (const Rec *)dumpb.data();

    // ---- parse headers with the C model to locate slice_data ----
    sps_t sps;
    pps_t pps;
    slice_hdr_t sh;
    memset(&sps, 0, sizeof(sps));
    memset(&pps, 0, sizeof(pps));
    nal_t n;
    size_t pos = 0;
    uint32_t err = 0;
    std::vector<uint8_t> rbsp;
    size_t sd_byte = 0;
    int sd_bit = 0;
    bool found = false;
    while (nal_next(stream.data(), stream.size(), &pos, &n) == 0) {
        bs_t bs;
        bs_init(&bs, n.rbsp, n.size);
        if (n.type == 7) {
            if (parse_sps(&bs, &sps, &err)) { printf("[SKIP] sps\n"); return 1; }
        } else if (n.type == 8) {
            if (parse_pps(&bs, &pps, &sps, &err)) { printf("[SKIP] pps\n"); return 1; }
        } else if (n.type == 5 || n.type == 1) {
            if (parse_slice_header(&bs, &sps, &pps, n.type, n.ref_idc,
                                   &sh, &err)) {
                printf("[SKIP] slice hdr err=0x%x\n", err);
                return 1;
            }
            if (pps.entropy_coding_mode || sh.is_p || sh.is_b) {
                printf("[SKIP] out of R1 subset\n");
                return 1;
            }
            rbsp.assign(n.rbsp, n.rbsp + n.size);
            // tail padding: single-cycle CAVLC needs a full 24-bit window
            // even while decoding the last macroblock
            for (int pi = 0; pi < 8; pi++) rbsp.push_back(0);
            sd_byte = bs.byte;
            sd_bit = bs.bit;
            found = true;
            nal_free(&n);
            break;
        }
        nal_free(&n);
    }
    if (!found) { printf("[SKIP] no I slice\n"); return 1; }

    // ---- drive the RTL ----
    Vmb_top top;
    auto tick = [&] {
        top.clk = 0;
        top.eval();
        top.clk = 1;
        top.eval();
    };
    top.rst_n = 0;
    top.in_valid = 0;
    top.start = 0;
    top.align_valid = 0;
    tick();
    top.rst_n = 1;
    tick();

    top.cfg_mb_w = (uint8_t)(sps.mb_width);
    top.cfg_mb_h = (uint8_t)(sps.mb_height);
    top.cfg_qp = (uint8_t)sh.slice_qp;

    size_t fi = sd_byte;               // feed from slice_data byte
    auto pump = [&] {
        top.in_valid = 0;
        if (fi < rbsp.size() && top.in_ready) {
            int nb = (int)std::min<size_t>(4, rbsp.size() - fi);
            uint32_t w = 0;
            for (int k = 0; k < nb; k++)
                w |= (uint32_t)rbsp[fi + k] << (24 - k * 8);
            top.in_valid = 1;
            top.in_word = w;
            top.in_bytes = (uint8_t)nb;
        }
    };
    for (int i = 0; i < 16; i++) {
        pump();
        tick();
        if (top.in_valid) fi += top.in_bytes;
        top.in_valid = 0;
    }
    if (sd_bit) {                      // consume residue bits
        top.align_valid = 1;
        top.align_bits = (uint8_t)sd_bit;
        pump();
        tick();
        if (top.in_valid) fi += top.in_bytes;
        top.align_valid = 0;
        top.in_valid = 0;
        tick();
    }

    top.start = 1;
    tick();
    top.start = 0;

    std::vector<Rec> got(nrec);
    memset(got.data(), 0, nrec * sizeof(Rec));
    size_t gi = 0;
    long guard = 0;
    Rec cur;
    memset(&cur, 0, sizeof(cur));

    while (!top.slice_done && !top.err && guard++ < 8000000) {
        pump();
        tick();
        if (top.in_valid) { fi += top.in_bytes; top.in_valid = 0; }
        if (top.coef_we) {
            int blk = top.coef_blk;
            int a = top.coef_addr;
            int16_t v = (int16_t)top.coef_data;
            if (blk < 16) cur.resid[blk][a] = v;
            else if (blk == 16) cur.dcraw[a] = v;
            else if (blk <= 18) cur.cdc[blk - 17][a & 3] = v;
            else {
                int c = (blk - 19) >> 2;
                int k = (blk - 19) & 3;
                cur.cres[c][k][a] = v;
            }
        }
        if (top.mb_valid) {
            cur.hdr[0] = top.mb_x;
            cur.hdr[1] = 0;
            cur.hdr[2] = top.mb_y;
            cur.hdr[3] = top.mb_i16 ? 1 : 0;
            cur.hdr[4] = top.mb_cbp;
            cur.hdr[5] = top.mb_qp;
            cur.hdr[6] = top.mb_i16_mode;
            cur.hdr[7] = top.mb_cmode;
            for (int i = 0; i < 16; i++)
                cur.i4m[i] = (top.mb_i4m >> (i * 4)) & 0xF;
            if (gi < nrec) got[gi] = cur;
            gi++;
            memset(&cur, 0, sizeof(cur));
            // mb_valid is a state, not a pulse: run one extra tick so
            // S_EMIT exits before we sample again
            pump();
            tick();
            if (top.in_valid) { fi += top.in_bytes; top.in_valid = 0; }
        }
    }

    if (top.err) { printf("[FAIL] mb_dec err state at MB %zu\n", gi); return 1; }
    if (gi != nrec) {
        printf("[FAIL] MB count rtl=%zu dump=%zu (done=%d)\n", gi, nrec,
               (int)top.slice_done);
        return 1;
    }
    int fails = 0;
    for (size_t i = 0; i < nrec && fails < 5; i++) {
        if (memcmp(&got[i], &gold[i], sizeof(Rec)) != 0) {
            printf("[FAIL] MB %zu mismatch:", i);
            if (memcmp(got[i].hdr, gold[i].hdr, 8))
                printf(" hdr rtl=[%d,%d,%d,cbp%02x,qp%d,%d,%d] "
                       "c=[%d,%d,%d,cbp%02x,qp%d,%d,%d]",
                       got[i].hdr[0], got[i].hdr[2], got[i].hdr[3],
                       got[i].hdr[4], got[i].hdr[5], got[i].hdr[6],
                       got[i].hdr[7],
                       gold[i].hdr[0], gold[i].hdr[2], gold[i].hdr[3],
                       gold[i].hdr[4], gold[i].hdr[5], gold[i].hdr[6],
                       gold[i].hdr[7]);
            if (memcmp(got[i].i4m, gold[i].i4m, 16)) printf(" i4m");
            if (memcmp(got[i].resid, gold[i].resid, sizeof(cur.resid)))
                printf(" resid");
            if (memcmp(got[i].dcraw, gold[i].dcraw, 32)) printf(" dcraw");
            if (memcmp(got[i].cdc, gold[i].cdc, 16)) printf(" cdc");
            if (memcmp(got[i].cres, gold[i].cres, sizeof(cur.cres)))
                printf(" cres");
            printf("\n");
            fails++;
        }
    }
    if (fails == 0) {
        printf("[PASS] mb_dec: %zu MBs bit-exact vs H264_RTL_DUMP\n", nrec);
        return 0;
    }
    return 1;
}
