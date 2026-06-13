// W16-a differential: mb_dec in B mode vs H264_RTL_DUMP_B records.
// Streams the FIRST gated B slice and compares per-MB skip, mb_type,
// B sub types and the list-major parse-order mvd lists. (Final MVs
// wait for the dual-list mv_pred.)
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
struct BRec {
    uint8_t mbx, mby, skip, mb_type;
    uint8_t sub[4];
    uint8_t qp, dsp, pad[2];
    int16_t mvd[2][16][2];
    int16_t mv[2][16][2];
    uint8_t pmode[16];
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
    std::vector<uint8_t> col = (argc > 3) ? rd(argv[3])
                                          : std::vector<uint8_t>();
    if (stream.empty() || db.size() % sizeof(BRec)) {
        printf("[SKIP] inputs (%zu dump bytes)\n", db.size());
        return 1;
    }
    const BRec *recs = (const BRec *)db.data();
    size_t nrec = db.size() / sizeof(BRec);

    // colocated motion field (W16-a): per 4x4 ref0/mv0/ref1/mv1
    int col_w = 0, col_h = 0;
    const uint8_t *cold = nullptr;
    if (col.size() >= 4) {
        col_w = col[0] | (col[1] << 8);
        col_h = col[2] | (col[3] << 8);
        cold = col.data() + 4;
    }
    auto colent = [&](int gx, int gy, int *r0, int *m0x, int *m0y,
                      int *r1, int *m1x, int *m1y) {
        const uint8_t *e = cold + (size_t)(gy * col_w * 4 + gx) * 10;
        *r0 = (int8_t)e[0];
        *m0x = (int16_t)(e[1] | (e[2] << 8));
        *m0y = (int16_t)(e[3] | (e[4] << 8));
        *r1 = (int8_t)e[5];
        *m1x = (int16_t)(e[6] | (e[7] << 8));
        *m1y = (int16_t)(e[8] | (e[9] << 8));
    };

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
            if (sh.is_b && !pps.entropy_coding_mode &&
                sh.num_ref_l0 == 1 && sh.num_ref_l1 == 1 &&
                !pps.weighted_pred && !pps.weighted_bipred &&
                !pps.transform_8x8) {
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
    if (!found) { printf("[SKIP] no B slice\n"); return 1; }

    size_t nmb = (size_t)sps.mb_width * sps.mb_height;
    if (nrec < nmb) { printf("[SKIP] dump too small\n"); return 1; }

    Vmb_top top;
    auto drive_col = [&] {
        if (!cold) return;
        int mx = top.col_mbx, my = top.col_mby;
        static const int cbx[4] = {0, 3, 0, 3};
        static const int cby[4] = {0, 0, 3, 3};
        for (int q = 0; q < 4; q++) {
            int r0, m0x, m0y, r1, m1x, m1y;
            int gx = mx * 4 + cbx[q], gy = my * 4 + cby[q];
            if (gx < col_w * 4 && gy < col_h * 4)
                colent(gx, gy, &r0, &m0x, &m0y, &r1, &m1x, &m1y);
            else { r0 = r1 = -1; m0x = m0y = m1x = m1y = 0; }
            top.col_ref0[q] = (int8_t)r0;
            top.col_mv0x[q] = (int16_t)m0x; top.col_mv0y[q] = (int16_t)m0y;
            top.col_ref1[q] = (int8_t)r1;
            top.col_mv1x[q] = (int16_t)m1x; top.col_mv1y[q] = (int16_t)m1y;
        }
    };
    auto tick = [&] {
        drive_col();
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
    top.cfg_is_p = 0;
    top.cfg_is_b = 1;

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
    int16_t mvd[2][16][2];
    int nmvd[2] = {0, 0};
    long guard = 0;
    int prev_valid = 0;
    while (!top.slice_done && !top.err && gi < nmb &&
           guard++ < 8000000) {
        pump();
        tick();
        if (top.in_valid) { fi += top.in_bytes; top.in_valid = 0; }
        if (top.mvd_valid) {
            int l = top.mvd_list;
            if (nmvd[l] < 16) {
                mvd[l][nmvd[l]][0] = (int16_t)top.mvd_x;
                mvd[l][nmvd[l]][1] = (int16_t)top.mvd_y;
                nmvd[l]++;
            }
        }
        if (top.mb_valid && !prev_valid) {
            const BRec &g = recs[gi];
            if (getenv("SEQ_DBG"))
                printf("MB%zu rtl=(%d,%d)s%di%dt%d c=(%d,%d)s%dt%d "
                       "nmvd=%d/%d\n",
                       gi, (int)top.mb_x, (int)top.mb_y, (int)top.mb_skip,
                       (int)top.mb_inter, (int)top.mb_ptype,
                       g.mbx, g.mby, g.skip, g.mb_type, nmvd[0], nmvd[1]);
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
                if (gtype < 23) {           // inter B
                    if (!top.mb_inter || (int)top.mb_ptype != gtype) {
                        printf("[FAIL] MB %zu type rtl=%d(int%d) c=%d\n",
                               gi, (int)top.mb_ptype, (int)top.mb_inter,
                               gtype);
                        fails++;
                    }
                    for (int b = 0; b < 4 && (gtype == 22); b++) {
                        int rs = (top.mb_sub >> (b * 4)) & 0xF;
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
            for (int l = 0; l < 2; l++)
                for (int m = 0; m < nmvd[l] && m < 16; m++) {
                    if (mvd[l][m][0] != g.mvd[l][m][0] ||
                        mvd[l][m][1] != g.mvd[l][m][1]) {
                        printf("[FAIL] MB %zu L%d mvd%d rtl=(%d,%d) "
                               "c=(%d,%d)\n", gi, l, m, mvd[l][m][0],
                               mvd[l][m][1], g.mvd[l][m][0],
                               g.mvd[l][m][1]);
                        fails++;
                    }
                }
            if (cold) {
                for (int k = 0; k < 16; k++) {
                    int rx0 = (int16_t)top.mv_out_x[k];
                    int ry0 = (int16_t)top.mv_out_y[k];
                    int rx1 = (int16_t)top.mv1_out_x[k];
                    int ry1 = (int16_t)top.mv1_out_y[k];
                    if (rx0 != g.mv[0][k][0] || ry0 != g.mv[0][k][1] ||
                        rx1 != g.mv[1][k][0] || ry1 != g.mv[1][k][1]) {
                        printf("[FAIL] MB %zu mv[%d] rtl L0(%d,%d) "
                               "L1(%d,%d) c L0(%d,%d) L1(%d,%d)\n",
                               gi, k, rx0, ry0, rx1, ry1,
                               g.mv[0][k][0], g.mv[0][k][1],
                               g.mv[1][k][0], g.mv[1][k][1]);
                        fails++;
                        if (fails >= 6) break;
                    }
                }
            }
            gi++;
            nmvd[0] = 0;
            nmvd[1] = 0;
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
        printf("[PASS] B parse: %zu MBs syntax+MV bit-exact vs dump\n", gi);
        return 0;
    }
    return 1;
}
