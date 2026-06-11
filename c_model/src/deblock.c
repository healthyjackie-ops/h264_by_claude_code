#include "deblock.h"

#include "transform.h"

/* Tables 8-16 / 8-17, indexed by clipped indexA/indexB 0..51. */
static const uint8_t ALPHA[52] = {
      0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
      4,  4,  5,  6,  7,  8,  9, 10, 12, 13, 15, 17, 20, 22, 25, 28,
     32, 36, 40, 45, 50, 56, 63, 71, 80, 90,101,113,127,144,162,182,
    203,226,255,255
};

static const uint8_t BETA[52] = {
     0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
     2,  2,  2,  3,  3,  3,  3,  4,  4,  4,  6,  6,  7,  7,  8,  8,
     9,  9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16,
    17, 17, 18, 18
};

static const uint8_t TC0[52][3] = {
    {0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},
    {0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},
    {0,0,0},{0,0,1},{0,0,1},{0,0,1},{0,0,1},{0,1,1},{0,1,1},{1,1,1},
    {1,1,1},{1,1,1},{1,1,1},{1,1,2},{1,1,2},{1,1,2},{1,1,2},{1,2,3},
    {1,2,3},{2,2,3},{2,2,4},{2,3,4},{2,3,4},{3,3,5},{3,4,6},{3,4,6},
    {4,5,7},{4,5,8},{4,6,9},{5,7,10},{6,8,11},{6,8,13},{7,10,14},
    {8,11,16},{9,12,18},{10,13,20},{11,15,23},{13,17,25}
};

static int clip3(int lo, int hi, int v) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static uint8_t clip_u8(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return (uint8_t)v;
}

static int iabs(int v) { return v < 0 ? -v : v; }

/* Filter one edge of `len` sample lines with per-4-sample boundary
 * strengths: line i uses bs4[i / seg] (seg = 4 luma, 2 chroma). q0p
 * points at the first q0 sample; pstep crosses the edge, lstep walks. */
static void filter_edge(uint8_t *q0p, ptrdiff_t pstep, ptrdiff_t lstep,
                        int len, int alpha, int beta,
                        const int bs4[4], const int tc04[4], int seg,
                        int chroma) {
    if (alpha == 0) return;
    for (int i = 0; i < len; i++) {
        int bs = bs4[i / seg];
        int tc0 = tc04[i / seg];
        if (bs == 0) continue;
        uint8_t *q = q0p + lstep * i;
        int q0 = q[0], q1 = q[pstep], q2 = q[2 * pstep];
        int p0 = q[-pstep], p1 = q[-2 * pstep], p2 = q[-3 * pstep];
        if (!(iabs(p0 - q0) < alpha && iabs(p1 - p0) < beta &&
              iabs(q1 - q0) < beta)) {
            continue;
        }
        if (bs == 4) {
            if (chroma) {
                q[-pstep] = (uint8_t)((2 * p1 + p0 + q1 + 2) >> 2);
                q[0]      = (uint8_t)((2 * q1 + q0 + p1 + 2) >> 2);
                continue;
            }
            int p3 = q[-4 * pstep], q3 = q[3 * pstep];
            int small = iabs(p0 - q0) < (alpha >> 2) + 2;
            if (small && iabs(p2 - p0) < beta) {
                q[-pstep]     = (uint8_t)((p2 + 2 * p1 + 2 * p0 + 2 * q0 + q1 + 4) >> 3);
                q[-2 * pstep] = (uint8_t)((p2 + p1 + p0 + q0 + 2) >> 2);
                q[-3 * pstep] = (uint8_t)((2 * p3 + 3 * p2 + p1 + p0 + q0 + 4) >> 3);
            } else {
                q[-pstep]     = (uint8_t)((2 * p1 + p0 + q1 + 2) >> 2);
            }
            if (small && iabs(q2 - q0) < beta) {
                q[0]         = (uint8_t)((q2 + 2 * q1 + 2 * q0 + 2 * p0 + p1 + 4) >> 3);
                q[pstep]     = (uint8_t)((q2 + q1 + q0 + p0 + 2) >> 2);
                q[2 * pstep] = (uint8_t)((2 * q3 + 3 * q2 + q1 + q0 + p0 + 4) >> 3);
            } else {
                q[0]         = (uint8_t)((2 * q1 + q0 + p1 + 2) >> 2);
            }
        } else {
            int ap = iabs(p2 - p0), aq = iabs(q2 - q0);
            int tc;
            if (chroma) {
                tc = tc0 + 1;
            } else {
                tc = tc0 + (ap < beta ? 1 : 0) + (aq < beta ? 1 : 0);
            }
            int delta = clip3(-tc, tc,
                              ((((q0 - p0) * 4) + (p1 - q1) + 4) >> 3));
            q[-pstep] = clip_u8(p0 + delta);
            q[0]      = clip_u8(q0 - delta);
            if (!chroma) {
                if (ap < beta) {
                    q[-2 * pstep] = (uint8_t)(p1 +
                        clip3(-tc0, tc0, (p2 + ((p0 + q0 + 1) >> 1) - 2 * p1) >> 1));
                }
                if (aq < beta) {
                    q[pstep] = (uint8_t)(q1 +
                        clip3(-tc0, tc0, (q2 + ((p0 + q0 + 1) >> 1) - 2 * q1) >> 1));
                }
            }
        }
    }
}

#define DB_POC_NONE INT32_MIN

static int mv_far(int16_t ax, int16_t ay, int16_t bx, int16_t by) {
    int dx = ax - bx, dy = ay - by;
    if (dx < 0) dx = -dx;
    if (dy < 0) dy = -dy;
    return dx >= 4 || dy >= 4;
}

/* Boundary strength for the edge between 4x4 blocks p and q (8.7.2.1).
 * Each block carries up to two predictions identified by reference POC;
 * different reference sets give 1, equal sets compare motion (with both
 * pairings tried when a block predicts twice from the same picture). */
static int edge_bs(uint32_t mb_w, const uint8_t *mb_cat, const uint8_t *nzL,
                   const int16_t *mv_x, const int16_t *mv_y,
                   const int16_t *mv1_x, const int16_t *mv1_y,
                   const int32_t *poc0, const int32_t *poc1,
                   int px, int py, int qx, int qy, int mb_edge) {
    uint32_t bw = mb_w * 4;
    uint32_t pi = (uint32_t)py * bw + (uint32_t)px;
    uint32_t qi = (uint32_t)qy * bw + (uint32_t)qx;
    int p_intra = mb_cat[((uint32_t)py >> 2) * mb_w + ((uint32_t)px >> 2)] < 3;
    int q_intra = mb_cat[((uint32_t)qy >> 2) * mb_w + ((uint32_t)qx >> 2)] < 3;
    if (p_intra || q_intra) return mb_edge ? 4 : 3;
    if (nzL[pi] || nzL[qi]) return 2;

    int32_t ppoc[2];
    int16_t pmx[2], pmy[2];
    int np = 0;
    if (poc0[pi] != DB_POC_NONE) {
        ppoc[np] = poc0[pi]; pmx[np] = mv_x[pi]; pmy[np] = mv_y[pi]; np++;
    }
    if (poc1[pi] != DB_POC_NONE) {
        ppoc[np] = poc1[pi]; pmx[np] = mv1_x[pi]; pmy[np] = mv1_y[pi]; np++;
    }
    int32_t qpoc[2];
    int16_t qmx[2], qmy[2];
    int nq = 0;
    if (poc0[qi] != DB_POC_NONE) {
        qpoc[nq] = poc0[qi]; qmx[nq] = mv_x[qi]; qmy[nq] = mv_y[qi]; nq++;
    }
    if (poc1[qi] != DB_POC_NONE) {
        qpoc[nq] = poc1[qi]; qmx[nq] = mv1_x[qi]; qmy[nq] = mv1_y[qi]; nq++;
    }
    if (np != nq) return 1;
    if (np == 1) {
        if (ppoc[0] != qpoc[0]) return 1;
        return mv_far(pmx[0], pmy[0], qmx[0], qmy[0]) ? 1 : 0;
    }
    /* two predictions each: sets must match */
    int direct_set = (ppoc[0] == qpoc[0] && ppoc[1] == qpoc[1]);
    int cross_set = (ppoc[0] == qpoc[1] && ppoc[1] == qpoc[0]);
    if (!direct_set && !cross_set) return 1;
    if (ppoc[0] != ppoc[1]) {
        /* distinct pictures: exactly one valid pairing */
        if (direct_set) {
            return (mv_far(pmx[0], pmy[0], qmx[0], qmy[0]) ||
                    mv_far(pmx[1], pmy[1], qmx[1], qmy[1])) ? 1 : 0;
        }
        return (mv_far(pmx[0], pmy[0], qmx[1], qmy[1]) ||
                mv_far(pmx[1], pmy[1], qmx[0], qmy[0])) ? 1 : 0;
    }
    /* same picture twice: either pairing may pass */
    int pair_a = !(mv_far(pmx[0], pmy[0], qmx[0], qmy[0]) ||
                   mv_far(pmx[1], pmy[1], qmx[1], qmy[1]));
    int pair_b = !(mv_far(pmx[0], pmy[0], qmx[1], qmy[1]) ||
                   mv_far(pmx[1], pmy[1], qmx[0], qmy[0]));
    return (pair_a || pair_b) ? 0 : 1;
}

/* Test export (RTL differential bench): one edge, explicit params. */
void h264_filter_edge_test(uint8_t *q0p, ptrdiff_t pstep, ptrdiff_t lstep,
                           int len, int alpha, int beta,
                           const int bs4[4], const int tc04[4], int seg,
                           int chroma) {
    filter_edge(q0p, pstep, lstep, len, alpha, beta, bs4, tc04, seg,
                chroma);
}

void h264_deblock_frame(uint8_t *Y, uint8_t *U, uint8_t *V,
                        size_t ls, size_t cs,
                        uint32_t mb_w, uint32_t mb_h,
                        const uint8_t *mb_qp,
                        const uint8_t *mb_t8,
                        const uint16_t *mb_slice,
                        const int8_t *mb_dbf_idc,
                        const int8_t *mb_dbf_a, const int8_t *mb_dbf_b,
                        const uint8_t *mb_cat,
                        const uint8_t *nzL,
                        const int16_t *mv_x, const int16_t *mv_y,
                        const int16_t *mv1_x, const int16_t *mv1_y,
                        const int32_t *ref_poc0, const int32_t *ref_poc1,
                        int chroma_qp_offset, int second_chroma_qp_offset) {
    for (uint32_t mby = 0; mby < mb_h; mby++) {
    for (uint32_t mbx = 0; mbx < mb_w; mbx++) {
        uint32_t mi = mby * mb_w + mbx;
        if (mb_dbf_idc[mi] == 1) continue;         /* filtering disabled */
        int qp = mb_qp[mi];
        int t8 = mb_t8[mi];
        int alpha_off = mb_dbf_a[mi];
        int beta_off = mb_dbf_b[mi];
        int skip_left = (mbx == 0) ||
            (mb_dbf_idc[mi] == 2 && mb_slice[mi - 1] != mb_slice[mi]);
        int skip_top = (mby == 0) ||
            (mb_dbf_idc[mi] == 2 && mb_slice[mi - mb_w] != mb_slice[mi]);

        /* ---- luma vertical edges (left to right), then horizontal ---- */
        for (int dir = 0; dir < 2; dir++) {
            for (int e = 0; e < 4; e++) {
                if (e == 0 && (dir == 0 ? skip_left : skip_top)) continue;
                if (t8 && (e == 1 || e == 3)) continue;   /* 8x8 transform:
                                                no internal 4x4 edges */
                int qpav = qp;
                if (e == 0) {
                    int qpn = dir == 0 ? mb_qp[mby * mb_w + mbx - 1]
                                       : mb_qp[(mby - 1) * mb_w + mbx];
                    qpav = (qp + qpn + 1) >> 1;
                }
                int ia = clip3(0, 51, qpav + alpha_off);
                int ib = clip3(0, 51, qpav + beta_off);
                int bs4[4], tc04[4];
                for (int s = 0; s < 4; s++) {
                    int px, py, qx, qy;
                    if (dir == 0) {
                        qx = (int)(mbx * 4) + e;
                        qy = (int)(mby * 4) + s;
                        px = qx - 1;
                        py = qy;
                    } else {
                        qx = (int)(mbx * 4) + s;
                        qy = (int)(mby * 4) + e;
                        px = qx;
                        py = qy - 1;
                    }
                    bs4[s] = edge_bs(mb_w, mb_cat, nzL, mv_x, mv_y,
                                     mv1_x, mv1_y, ref_poc0, ref_poc1,
                                     px, py, qx, qy, e == 0);
                    tc04[s] = (bs4[s] > 0 && bs4[s] < 4)
                                  ? TC0[ia][bs4[s] - 1] : 0;
                }
                uint8_t *base = (dir == 0)
                    ? Y + (size_t)mby * 16 * ls + (size_t)mbx * 16 + (size_t)e * 4
                    : Y + ((size_t)mby * 16 + (size_t)e * 4) * ls + (size_t)mbx * 16;
                filter_edge(base,
                            dir == 0 ? 1 : (ptrdiff_t)ls,
                            dir == 0 ? (ptrdiff_t)ls : 1,
                            16, ALPHA[ia], BETA[ib], bs4, tc04, 4, 0);
            }
            /* chroma: edges at chroma x/y 0 and 4 (luma 0 and 8); each
             * component averages its own QPc (Cr uses the second offset). */
            for (int e = 0; e < 2; e++) {
                if (e == 0 && (dir == 0 ? skip_left : skip_top)) continue;
                /* chroma edge at luma x/y offset 2*e*4: bS from the
                 * corresponding luma block pairs (2 luma segments per
                 * chroma edge half). */
                int cbs4[4], luma_e = e * 2;
                for (int s = 0; s < 4; s++) {
                    int px, py, qx, qy;
                    if (dir == 0) {
                        qx = (int)(mbx * 4) + luma_e;
                        qy = (int)(mby * 4) + s;
                        px = qx - 1;
                        py = qy;
                    } else {
                        qx = (int)(mbx * 4) + s;
                        qy = (int)(mby * 4) + luma_e;
                        px = qx;
                        py = qy - 1;
                    }
                    cbs4[s] = edge_bs(mb_w, mb_cat, nzL, mv_x, mv_y,
                                      mv1_x, mv1_y, ref_poc0, ref_poc1,
                                      px, py, qx, qy, e == 0);
                }
                for (int comp = 0; comp < 2; comp++) {
                    int off = comp ? second_chroma_qp_offset : chroma_qp_offset;
                    int qpcav = h264_chroma_qp(clip3(0, 51, qp + off));
                    if (e == 0) {
                        int qpn = dir == 0 ? mb_qp[mby * mb_w + mbx - 1]
                                           : mb_qp[(mby - 1) * mb_w + mbx];
                        int qpcn = h264_chroma_qp(clip3(0, 51, qpn + off));
                        qpcav = (qpcav + qpcn + 1) >> 1;
                    }
                    int ia = clip3(0, 51, qpcav + alpha_off);
                    int ib = clip3(0, 51, qpcav + beta_off);
                    int tc04[4];
                    for (int s = 0; s < 4; s++) {
                        tc04[s] = (cbs4[s] > 0 && cbs4[s] < 4)
                                      ? TC0[ia][cbs4[s] - 1] : 0;
                    }
                    uint8_t *plane = comp ? V : U;
                    uint8_t *base = (dir == 0)
                        ? plane + (size_t)mby * 8 * cs + (size_t)mbx * 8 + (size_t)e * 4
                        : plane + ((size_t)mby * 8 + (size_t)e * 4) * cs + (size_t)mbx * 8;
                    filter_edge(base,
                                dir == 0 ? 1 : (ptrdiff_t)cs,
                                dir == 0 ? (ptrdiff_t)cs : 1,
                                8, ALPHA[ia], BETA[ib], cbs4, tc04, 2, 1);
                }
            }
        }
    }
    }
}
