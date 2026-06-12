// P-R3b/c differential: mb_dec + mv_pred in P mode vs H264_RTL_DUMP_P.
// Streams the FIRST P slice of a .264 into the parser and compares the
// per-MB skip flag, mb_type, sub types, the parse-order mvd list and
// the final z-scan 4x4 MV field from the mv_pred unit.
//   usage: Vmb_top_p <stream.264> <p.dump>
#include <cstdio>
#include <cstring>
#include <vector>
#include <algorithm>

#include "Vmb_top.h"
#include "verilated.h"

extern "C" {
#include "bitstream.h"
#include "nal.h"
#include "params.h"
#include "slice.h"
}

namespace {
struct PRec {
    uint8_t mbx, mby, skip, mb_type;
    uint8_t sub[4];
    uint8_t qp;
    uint8_t pad[3];
    int16_t mvd[16][2];
    int16_t mv[16][2];
};
std::vector<uint8_t> rd(const char *p) {
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
    if (argc < 3) {
        printf("usage: %s <stream.264> <p.dump>\n", argv[0]);
        return 1;
    }
    auto stream = rd(argv[1]);
    auto db = rd(argv[2]);
    if (stream.empty() || db.size() % sizeof(PRec)) {
        printf("[SKIP] inputs (%zu dump bytes)\n", db.size());
        return 1;
    }
    const PRec *recs = (const PRec *)db.data();
    size_t nrec = db.size() / sizeof(PRec);

    sps_t sps;
    pps_t pps;
    slice_hdr_t sh;
    memset(&sps, 0, sizeof(sps));
    memset(&pps, 0, sizeof(pps));
    nal_t n;
    size_t pos = 0;
    uint32_t errc = 0;
    std::vector<uint8_t> rbsp;
    size_t sd_byte = 0;
    int sd_bit = 0;
    bool found = false;
    while (nal_next(stream.data(), stream.size(), &pos, &n) == 0) {
        bs_t bs;
        bs_init(&bs, n.rbsp, n.size);
        if (n.type == 7) parse_sps(&bs, &sps, &errc);
        else if (n.type == 8) parse_pps(&bs, &pps, &sps, &errc);
        else if (n.type == 1 || n.type == 5) {
            if (parse_slice_header(&bs, &sps, &pps, n.type, n.ref_idc,
                                   &sh, &errc)) {
                nal_free(&n);
                continue;
            }
            if (sh.is_p && !pps.entropy_coding_mode &&
                sh.num_ref_l0 == 1 && !pps.transform_8x8) {
                rbsp.assign(n.rbsp, n.rbsp + n.size);
                for (int pi = 0; pi < 8; pi++) rbsp.push_back(0);
                sd_byte = bs.byte;
                sd_bit = bs.bit;
                found = true;
                nal_free(&n);
                break;
            }
        }
        nal_free(&n);
    }
    if (!found) { printf("[SKIP] no P slice\n"); return 1; }

    size_t nmb = (size_t)sps.mb_width * sps.mb_height;
    if (nrec < nmb) { printf("[SKIP] dump too small\n"); return 1; }

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
    top.cfg_mb_w = (uint8_t)sps.mb_width;
    top.cfg_mb_h = (uint8_t)sps.mb_height;
    top.cfg_qp = (uint8_t)sh.slice_qp;
    top.cfg_is_p = 1;

    size_t fi = sd_byte;
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
    if (sd_bit) {
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

    size_t gi = 0;
    int fails = 0;
    int16_t mvd[16][2];
    int nmvd = 0;
    long guard = 0;
    int prev_valid = 0;
    while (!top.slice_done && !top.err && gi < nmb &&
           guard++ < 8000000) {
        pump();
        tick();
        if (top.in_valid) { fi += top.in_bytes; top.in_valid = 0; }
        if (top.mvd_valid && nmvd < 16) {
            mvd[nmvd][0] = (int16_t)top.mvd_x;
            mvd[nmvd][1] = (int16_t)top.mvd_y;
            nmvd++;
        }
        if (top.mb_valid && !prev_valid) {
            const PRec &g = recs[gi];
            if (getenv("SEQ_DBG"))
                printf("MB%zu rtl=(%d,%d)s%di%dt%d c=(%d,%d)s%dt%d "
                       "nmvd=%d\n",
                       gi, (int)top.mb_x, (int)top.mb_y, (int)top.mb_skip,
                       (int)top.mb_inter, (int)top.mb_ptype,
                       g.mbx, g.mby, g.skip, g.mb_type, nmvd);
            if (top.mb_x != g.mbx || top.mb_y != g.mby) {
                printf("[FAIL] MB %zu pos rtl=(%d,%d) c=(%d,%d)\n", gi,
                       (int)top.mb_x, (int)top.mb_y, g.mbx, g.mby);
                fails++;
            }
            if ((int)top.mb_skip != g.skip) {
                printf("[FAIL] MB %zu skip rtl=%d c=%d\n", gi,
                       (int)top.mb_skip, g.skip);
                fails++;
            }
            if (!g.skip) {
                int gtype = g.mb_type;
                if (gtype < 5) {            // inter
                    if (!top.mb_inter || (int)top.mb_ptype != gtype) {
                        printf("[FAIL] MB %zu type rtl=%d(int%d) c=%d\n",
                               gi, (int)top.mb_ptype, (int)top.mb_inter,
                               gtype);
                        fails++;
                    }
                    for (int b = 0; b < 4 && (gtype >= 3); b++) {
                        int rs = (top.mb_sub >> (b * 2)) & 3;
                        if (rs != g.sub[b]) {
                            printf("[FAIL] MB %zu sub%d rtl=%d c=%d\n",
                                   gi, b, rs, g.sub[b]);
                            fails++;
                        }
                    }
                } else if (top.mb_inter) {
                    printf("[FAIL] MB %zu: rtl inter, c intra(%d)\n", gi,
                           gtype);
                    fails++;
                }
            }
            for (int m = 0; m < nmvd && m < 16; m++) {
                if (mvd[m][0] != g.mvd[m][0] || mvd[m][1] != g.mvd[m][1]) {
                    printf("[FAIL] MB %zu mvd%d rtl=(%d,%d) c=(%d,%d)\n",
                           gi, m, mvd[m][0], mvd[m][1], g.mvd[m][0],
                           g.mvd[m][1]);
                    fails++;
                }
            }
            for (int k = 0; k < 16; k++) {
                int16_t rx = (int16_t)top.mv_out_x[k];
                int16_t ry = (int16_t)top.mv_out_y[k];
                if (rx != g.mv[k][0] || ry != g.mv[k][1]) {
                    printf("[FAIL] MB %zu mv[%d] rtl=(%d,%d) c=(%d,%d)\n",
                           gi, k, rx, ry, g.mv[k][0], g.mv[k][1]);
                    fails++;
                    if (fails >= 5) break;
                }
            }
            gi++;
            nmvd = 0;
            if (fails >= 5) break;
        }
        prev_valid = top.mb_valid;
    }

    if (top.err) { printf("[FAIL] err at MB %zu\n", gi); return 1; }
    if (gi != nmb) {
        printf("[FAIL] MB count %zu/%zu (done=%d guard=%ld)\n", gi, nmb,
               (int)top.slice_done, guard);
        return 1;
    }
    if (!fails) {
        printf("[PASS] P parse: %zu MBs syntax+MV bit-exact vs dump\n", gi);
        return 0;
    }
    return 1;
}
