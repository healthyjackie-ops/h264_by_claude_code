#include "decoder.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bitstream.h"
#include "cabac.h"
#include "cavlc.h"
#include "deblock.h"
#include "intra.h"
#include "nal.h"
#include "params.h"
#include "slice.h"
#include "transform.h"

static int trace_level(void) {
    static int v = -1;
    if (v < 0) {
        const char *e = getenv("H264_TRACE");
        v = e ? atoi(e) : 0;
        if (e && v == 0) v = 1;
    }
    return v;
}

/* 4x4 sub-block z-scan order inside an MB: index -> (x4,y4) and back. */
static const uint8_t zscan_x[16] = {0,1,0,1, 2,3,2,3, 0,1,0,1, 2,3,2,3};
static const uint8_t zscan_y[16] = {0,0,1,1, 0,0,1,1, 2,2,3,3, 2,2,3,3};
static const uint8_t raster_to_z[16] = {
    0, 1, 4, 5,
    2, 3, 6, 7,
    8, 9, 12, 13,
    10, 11, 14, 15
};

typedef struct {
    const sps_t *sps;
    const pps_t *pps;
    uint32_t mb_w, mb_h;
    size_t ls, cs;             /* luma / chroma strides (padded planes) */
    uint8_t *Y, *U, *V;
    int8_t *i4_mode;           /* [mb_h*4][mb_w*4]; 2 (DC) for non-I4x4 MBs */
    uint8_t *nzL;              /* [mb_h*4][mb_w*4] total_coeff per luma 4x4 */
    uint8_t *nzC[2];           /* [mb_h*2][mb_w*2] per chroma component */
    uint8_t *mb_qp;            /* [mb_h][mb_w] final luma QP per MB */
    /* CABAC neighbor state (also filled on the CAVLC path; cheap) */
    uint8_t *mb_cat;           /* 0 = I_4x4, 1 = I_16x16, 2 = I_PCM */
    uint8_t *mb_cmode;         /* chroma pred mode per MB */
    uint8_t *mb_cbp;           /* (cbp_chroma<<4)|cbp_luma per MB */
    uint8_t *cbf_l;            /* coded_block_flag per luma 4x4 [bw*bh] */
    uint8_t *cbf_ldc;          /* Intra16x16 luma DC cbf per MB */
    uint8_t *cbf_c[2];         /* chroma AC cbf per 4x4 [bw/2 * bh/2] */
    uint8_t *cbf_cdc[2];       /* chroma DC cbf per MB */
} ictx_t;

static int clip3(int lo, int hi, int v) {
    return v < lo ? lo : (v > hi ? hi : v);
}

/* Has luma 4x4 block (gbx,gby) been decoded before z-index cur_k of MB
 * (cur_mbx,cur_mby)? Single-slice raster MB order + z-scan inside the MB. */
static int blk_decoded(const ictx_t *c, uint32_t cur_mbx, uint32_t cur_mby,
                       int cur_k, int gbx, int gby) {
    if (gbx < 0 || gby < 0 || (uint32_t)gbx >= c->mb_w * 4) return 0;
    uint32_t mbx = (uint32_t)gbx >> 2, mby = (uint32_t)gby >> 2;
    if (mby < cur_mby) return 1;
    if (mby > cur_mby) return 0;
    if (mbx < cur_mbx) return 1;
    if (mbx > cur_mbx) return 0;
    return raster_to_z[(gby & 3) * 4 + (gbx & 3)] < cur_k;
}

/* nC predictor (9.2.1) from per-block total_coeff arrays. */
static int derive_nc(const uint8_t *nz, uint32_t row_blocks,
                     int bx, int by, int availA, int availB) {
    if (availA && availB) {
        int nA = nz[(uint32_t)by * row_blocks + (uint32_t)(bx - 1)];
        int nB = nz[(uint32_t)(by - 1) * row_blocks + (uint32_t)bx];
        return (nA + nB + 1) >> 1;
    }
    if (availA) return nz[(uint32_t)by * row_blocks + (uint32_t)(bx - 1)];
    if (availB) return nz[(uint32_t)(by - 1) * row_blocks + (uint32_t)bx];
    return 0;
}


/* ------------------------- CABAC syntax (Phase 9) ------------------------ */

/* mb_type for I slices (9.3.2.5 binarization; ctx layout per ffmpeg
 * decode_cabac_intra_mb_type: bin0 at 3+inc, then terminate for I_PCM,
 * then cbp_luma@6, cbp_chroma@7/8, pred@9/10). */
static uint32_t cabac_mb_type_I(cabac_t *cb, const ictx_t *c,
                                uint32_t mbx, uint32_t mby) {
    int inc = 0;
    if (mbx > 0 && c->mb_cat[mby * c->mb_w + mbx - 1] != 0) inc++;
    if (mby > 0 && c->mb_cat[(mby - 1) * c->mb_w + mbx] != 0) inc++;
    if (cabac_decision(cb, 3 + inc) == 0) return 0;        /* I_4x4 */
    if (cabac_terminate(cb)) return 25;                    /* I_PCM */
    uint32_t t = 1;
    t += 12u * (uint32_t)cabac_decision(cb, 6);
    if (cabac_decision(cb, 7)) {
        t += 4u * (1u + (uint32_t)cabac_decision(cb, 8));
    }
    t += 2u * (uint32_t)cabac_decision(cb, 9);
    t += (uint32_t)cabac_decision(cb, 10);
    return t;
}

static int cabac_intra4x4_mode(cabac_t *cb, int pred) {
    if (cabac_decision(cb, 68)) return pred;
    int m = cabac_decision(cb, 69);
    m += 2 * cabac_decision(cb, 69);
    m += 4 * cabac_decision(cb, 69);
    return m + (m >= pred);
}

static uint32_t cabac_chroma_mode(cabac_t *cb, const ictx_t *c,
                                  uint32_t mbx, uint32_t mby) {
    int inc = 0;
    if (mbx > 0 && c->mb_cmode[mby * c->mb_w + mbx - 1] != 0) inc++;
    if (mby > 0 && c->mb_cmode[(mby - 1) * c->mb_w + mbx] != 0) inc++;
    if (cabac_decision(cb, 64 + inc) == 0) return 0;
    if (cabac_decision(cb, 67) == 0) return 1;
    if (cabac_decision(cb, 67) == 0) return 2;
    return 3;
}

/* CBP, I_4x4 path (ctx 73..76 luma, 77..84 chroma; neighbor semantics per
 * ffmpeg decode_cabac_mb_cbp_*: unavailable intra neighbor reads as 0x7F,
 * I_PCM as 0x2F). */
static uint32_t cabac_cbp(cabac_t *cb, const ictx_t *c,
                          uint32_t mbx, uint32_t mby) {
    /* Unavailable neighbors read as luma-all-set / chroma-zero (0x0F):
     * luma condTerm = available && bit==0, chroma condTerm needs an
     * available nonzero-cbp neighbor (9.3.3.1.1.4, verified vs JM). */
    uint32_t cbp_a = (mbx > 0) ? c->mb_cbp[mby * c->mb_w + mbx - 1] : 0x0F;
    uint32_t cbp_b = (mby > 0) ? c->mb_cbp[(mby - 1) * c->mb_w + mbx] : 0x0F;
    uint32_t cbp = 0;
    int ctx;
    ctx = !(cbp_a & 0x02) + 2 * !(cbp_b & 0x04);
    cbp += (uint32_t)cabac_decision(cb, 73 + ctx);
    ctx = !(cbp & 0x01) + 2 * !(cbp_b & 0x08);
    cbp += (uint32_t)cabac_decision(cb, 73 + ctx) << 1;
    ctx = !(cbp_a & 0x08) + 2 * !(cbp & 0x01);
    cbp += (uint32_t)cabac_decision(cb, 73 + ctx) << 2;
    ctx = !(cbp & 0x04) + 2 * !(cbp & 0x02);
    cbp += (uint32_t)cabac_decision(cb, 73 + ctx) << 3;

    uint32_t ca = (cbp_a >> 4) & 3, cb_ = (cbp_b >> 4) & 3;
    ctx = (ca > 0) + 2 * (cb_ > 0);
    if (cabac_decision(cb, 77 + ctx)) {
        ctx = 4 + (ca == 2) + 2 * (cb_ == 2);
        cbp |= (1u + (uint32_t)cabac_decision(cb, 77 + ctx)) << 4;
    }
    return cbp;
}

/* mb_qp_delta: unary with ctx 60+(last!=0), 62, 63. */
static int cabac_qp_delta(cabac_t *cb, int last_nz, int32_t *delta,
                          uint32_t *err) {
    if (!cabac_decision(cb, 60 + (last_nz ? 1 : 0))) {
        *delta = 0;
        return 0;
    }
    int val = 1;
    int ctx = 62;
    while (cabac_decision(cb, ctx)) {
        ctx = 63;
        if (++val > 104) { *err = H264_ERR_BAD_STREAM; return -1; }
    }
    *delta = (val & 1) ? (val + 1) / 2 : -((val + 1) / 2);
    return 0;
}

/* One residual block (9.3.2.3 + ctx tables): cbf at 85+cat*4+inc, then
 * significance map at 105/166 + catoff + scanpos, then levels in reverse
 * scan order through the node-ctx machine with EG0 escape. Output is in
 * scan order, like cavlc_residual_block. Returns total_coeff or -1. */
static int cabac_residual(cabac_t *cb, int cat, int cond_a, int cond_b,
                          int max_coeffs, int16_t scan[16], uint32_t *err) {
    static const int sig_off[5] = { 0, 15, 29, 44, 47 };
    static const int lvl_off[5] = { 0, 10, 20, 30, 39 };
    static const uint8_t l1ctx[8] = { 1, 2, 3, 4, 0, 0, 0, 0 };
    static const uint8_t gt1ctx[8] = { 5, 5, 5, 5, 6, 7, 8, 9 };
    static const uint8_t tr_eq1[8] = { 1, 2, 3, 3, 4, 5, 6, 7 };
    static const uint8_t tr_gt1[8] = { 4, 4, 4, 4, 5, 6, 7, 7 };

    memset(scan, 0, 16 * sizeof(scan[0]));
    if (!cabac_decision(cb, 85 + cat * 4 + cond_a + 2 * cond_b)) return 0;

    int idx[16];
    int cnt = 0;
    int i;
    for (i = 0; i < max_coeffs - 1; i++) {
        if (cabac_decision(cb, 105 + sig_off[cat] + i)) {
            idx[cnt++] = i;
            if (cabac_decision(cb, 166 + sig_off[cat] + i)) break;
        }
    }
    if (i == max_coeffs - 1) idx[cnt++] = i;
    if (cnt == 0 || cb->error) { *err = H264_ERR_BAD_STREAM; return -1; }

    int total = cnt;
    int node = 0;
    while (cnt) {
        int pos = idx[--cnt];
        int abs_lvl;
        if (!cabac_decision(cb, 227 + lvl_off[cat] + l1ctx[node])) {
            abs_lvl = 1;
            node = tr_eq1[node];
        } else {
            abs_lvl = 2;
            int ctx = 227 + lvl_off[cat] + gt1ctx[node];
            node = tr_gt1[node];
            while (abs_lvl < 15 && cabac_decision(cb, ctx)) abs_lvl++;
            if (abs_lvl >= 15) {                  /* EG0 bypass escape */
                int j = 0;
                while (cabac_bypass(cb) && j < 23) j++;
                int v = 1;
                while (j--) v = 2 * v + cabac_bypass(cb);
                abs_lvl = v + 14;
            }
        }
        int sign = cabac_bypass(cb);
        scan[pos] = (int16_t)(sign ? -abs_lvl : abs_lvl);
        if (cb->error) { *err = H264_ERR_TRUNC; return -1; }
    }
    return total;
}

/* coded_block_flag neighbor terms (9.3.3.1.1.9, all-intra frame): an
 * out-of-picture neighbor counts as 1, I_PCM counts as 1, otherwise the
 * stored cbf of the matching block/MB (0 when the neighbor has no such
 * block, e.g. luma DC next to a non-I16x16 MB). */
static int cbf_cond_luma4(const ictx_t *c, int gx, int gy) {
    uint32_t bw = c->mb_w * 4;
    if (gx < 0 || gy < 0) return 1;
    uint32_t mb = ((uint32_t)gy >> 2) * c->mb_w + ((uint32_t)gx >> 2);
    if (c->mb_cat[mb] == 2) return 1;
    return c->cbf_l[(uint32_t)gy * bw + (uint32_t)gx];
}

static int cbf_cond_chroma4(const ictx_t *c, int comp, int gx, int gy) {
    uint32_t cw = c->mb_w * 2;
    if (gx < 0 || gy < 0) return 1;
    uint32_t mb = ((uint32_t)gy >> 1) * c->mb_w + ((uint32_t)gx >> 1);
    if (c->mb_cat[mb] == 2) return 1;
    return c->cbf_c[comp][(uint32_t)gy * cw + (uint32_t)gx];
}

static int cbf_cond_lumadc(const ictx_t *c, uint32_t mbx, uint32_t mby,
                           int dx, int dy) {
    int nx = (int)mbx + dx, ny = (int)mby + dy;
    if (nx < 0 || ny < 0) return 1;
    uint32_t mb = (uint32_t)ny * c->mb_w + (uint32_t)nx;
    if (c->mb_cat[mb] == 2) return 1;
    if (c->mb_cat[mb] != 1) return 0;          /* no DC block in I_4x4 */
    return c->cbf_ldc[mb];
}

static int cbf_cond_chromadc(const ictx_t *c, int comp, uint32_t mbx,
                             uint32_t mby, int dx, int dy) {
    int nx = (int)mbx + dx, ny = (int)mby + dy;
    if (nx < 0 || ny < 0) return 1;
    uint32_t mb = (uint32_t)ny * c->mb_w + (uint32_t)nx;
    if (c->mb_cat[mb] == 2) return 1;
    return c->cbf_cdc[comp][mb];
}

static int decode_islice(bs_t *bs, const sps_t *sps, const pps_t *pps,
                         const slice_hdr_t *sh, h264_decoded_t *out) {
    ictx_t c;
    memset(&c, 0, sizeof(c));
    c.sps = sps;
    c.pps = pps;
    c.mb_w = sps->mb_width;
    c.mb_h = sps->mb_height;
    c.ls = (size_t)c.mb_w * 16;
    c.cs = (size_t)c.mb_w * 8;

    size_t lsamples = c.ls * (size_t)c.mb_h * 16;
    size_t csamples = c.cs * (size_t)c.mb_h * 8;
    uint32_t bw = c.mb_w * 4, bh = c.mb_h * 4;
    c.Y = (uint8_t *)calloc(lsamples, 1);
    c.U = (uint8_t *)calloc(csamples, 1);
    c.V = (uint8_t *)calloc(csamples, 1);
    c.i4_mode = (int8_t *)calloc((size_t)bw * bh, 1);
    c.nzL = (uint8_t *)calloc((size_t)bw * bh, 1);
    c.nzC[0] = (uint8_t *)calloc((size_t)(bw / 2) * (bh / 2), 1);
    c.nzC[1] = (uint8_t *)calloc((size_t)(bw / 2) * (bh / 2), 1);
    c.mb_qp = (uint8_t *)calloc((size_t)c.mb_w * c.mb_h, 1);
    size_t nmbs = (size_t)c.mb_w * c.mb_h;
    c.mb_cat = (uint8_t *)calloc(nmbs, 1);
    c.mb_cmode = (uint8_t *)calloc(nmbs, 1);
    c.mb_cbp = (uint8_t *)calloc(nmbs, 1);
    c.cbf_l = (uint8_t *)calloc((size_t)bw * bh, 1);
    c.cbf_ldc = (uint8_t *)calloc(nmbs, 1);
    c.cbf_c[0] = (uint8_t *)calloc((size_t)(bw / 2) * (bh / 2), 1);
    c.cbf_c[1] = (uint8_t *)calloc((size_t)(bw / 2) * (bh / 2), 1);
    c.cbf_cdc[0] = (uint8_t *)calloc(nmbs, 1);
    c.cbf_cdc[1] = (uint8_t *)calloc(nmbs, 1);
    int ok = c.Y && c.U && c.V && c.i4_mode && c.nzL && c.nzC[0] &&
             c.nzC[1] && c.mb_qp && c.mb_cat && c.mb_cmode && c.mb_cbp &&
             c.cbf_l && c.cbf_ldc && c.cbf_c[0] && c.cbf_c[1] &&
             c.cbf_cdc[0] && c.cbf_cdc[1];
    if (!ok) {
        out->err = H264_ERR_INTERNAL;
        goto fail;
    }

    {
    int qp = (int)sh->slice_qp;
    int dbg = trace_level();
    int use_cabac = pps->entropy_coding_mode;
    int last_qpd_nz = 0;
    cabac_t cbx;
    memset(&cbx, 0, sizeof(cbx));
    if (use_cabac) {
        bs_byte_align(bs);             /* cabac_alignment_one_bit(s) */
        cabac_init(&cbx, bs->data, bs->size, bs->byte, qp);
    }

    for (uint32_t mby = 0; mby < c.mb_h; mby++) {
    for (uint32_t mbx = 0; mbx < c.mb_w; mbx++) {
        uint32_t mb_type;
        if (use_cabac) {
            mb_type = cabac_mb_type_I(&cbx, &c, mbx, mby);
            if (cbx.error) { out->err = H264_ERR_TRUNC; goto fail; }
        } else {
            mb_type = bs_ue(bs);
            if (bs->error) { out->err = H264_ERR_TRUNC; goto fail; }
            if (mb_type > 25) { out->err = H264_ERR_BAD_STREAM; goto fail; }
        }

        uint8_t *ydst = c.Y + (size_t)mby * 16 * c.ls + (size_t)mbx * 16;
        uint8_t *udst = c.U + (size_t)mby * 8 * c.cs + (size_t)mbx * 8;
        uint8_t *vdst = c.V + (size_t)mby * 8 * c.cs + (size_t)mbx * 8;

        if (mb_type == 25) {                       /* I_PCM */
            if (use_cabac) {
                /* x264 never emits PCM, so the CABAC re-init handoff is
                 * unverifiable; reject until a JM-encoded vector exists. */
                out->err = H264_ERR_UNSUP;
                goto fail;
            }
            bs_byte_align(bs);
            for (int y = 0; y < 16; y++)
                for (int x = 0; x < 16; x++)
                    ydst[(size_t)y * c.ls + (size_t)x] = (uint8_t)bs_u(bs, 8);
            for (int y = 0; y < 8; y++)
                for (int x = 0; x < 8; x++)
                    udst[(size_t)y * c.cs + (size_t)x] = (uint8_t)bs_u(bs, 8);
            for (int y = 0; y < 8; y++)
                for (int x = 0; x < 8; x++)
                    vdst[(size_t)y * c.cs + (size_t)x] = (uint8_t)bs_u(bs, 8);
            if (bs->error) { out->err = H264_ERR_TRUNC; goto fail; }
            /* nC bookkeeping: I_PCM counts as 16 coefficients everywhere;
             * intra-mode prediction sees DC. QP chain is unchanged. */
            for (int k = 0; k < 16; k++) {
                uint32_t gx = mbx * 4 + zscan_x[k], gy = mby * 4 + zscan_y[k];
                c.nzL[gy * bw + gx] = 16;
                c.i4_mode[gy * bw + gx] = 2;
            }
            for (int k = 0; k < 4; k++) {
                uint32_t gx = mbx * 2 + (uint32_t)(k & 1);
                uint32_t gy = mby * 2 + (uint32_t)(k >> 1);
                c.nzC[0][gy * (bw / 2) + gx] = 16;
                c.nzC[1][gy * (bw / 2) + gx] = 16;
            }
            c.mb_qp[mby * c.mb_w + mbx] = (uint8_t)qp;
            c.mb_cat[mby * c.mb_w + mbx] = 2;
            c.mb_cbp[mby * c.mb_w + mbx] = 0x2F;
            if (dbg >= 2) fprintf(stderr, "MB %u,%u I_PCM\n", mbx, mby);
            continue;
        }

        int intra4x4 = (mb_type == 0);
        int modes[16];
        int i16_mode = 0;
        uint32_t cbp_luma, cbp_chroma;

        if (intra4x4) {
            for (int k = 0; k < 16; k++) {
                int gx = (int)(mbx * 4 + zscan_x[k]);
                int gy = (int)(mby * 4 + zscan_y[k]);
                int pA = (gx > 0) ? c.i4_mode[(uint32_t)gy * bw + (uint32_t)gx - 1] : -1;
                int pB = (gy > 0) ? c.i4_mode[((uint32_t)gy - 1) * bw + (uint32_t)gx] : -1;
                int pred = (pA < 0 || pB < 0) ? 2 : (pA < pB ? pA : pB);
                int mode;
                if (use_cabac) {
                    mode = cabac_intra4x4_mode(&cbx, pred);
                } else if (bs_u1(bs)) {
                    mode = pred;
                } else {
                    int rem = (int)bs_u(bs, 3);
                    mode = (rem < pred) ? rem : rem + 1;
                }
                modes[k] = mode;
                c.i4_mode[(uint32_t)gy * bw + (uint32_t)gx] = (int8_t)mode;
            }
        } else {
            uint32_t m = mb_type - 1;
            i16_mode = (int)(m & 3);
            cbp_chroma = (m >> 2) % 3;
            cbp_luma = (m >= 12) ? 15 : 0;
            for (int k = 0; k < 16; k++) {
                uint32_t gx = mbx * 4 + zscan_x[k], gy = mby * 4 + zscan_y[k];
                c.i4_mode[gy * bw + gx] = 2;
            }
        }

        uint32_t chroma_mode;
        if (use_cabac) {
            chroma_mode = cabac_chroma_mode(&cbx, &c, mbx, mby);
        } else {
            chroma_mode = bs_ue(bs);
        }
        if (chroma_mode > 3 || bs->error || cbx.error) {
            out->err = (bs->error || cbx.error) ? H264_ERR_TRUNC
                                                : H264_ERR_BAD_STREAM;
            goto fail;
        }

        if (intra4x4) {
            uint32_t cbp;
            if (use_cabac) {
                cbp = cabac_cbp(&cbx, &c, mbx, mby);
                if (cbx.error) { out->err = H264_ERR_TRUNC; goto fail; }
            } else {
                int v = cavlc_intra_cbp(bs_ue(bs));
                if (v < 0 || bs->error) {
                    out->err = bs->error ? H264_ERR_TRUNC : H264_ERR_BAD_STREAM;
                    goto fail;
                }
                cbp = (uint32_t)v;
            }
            cbp_luma = cbp & 15;
            cbp_chroma = cbp >> 4;
            if (cbp_chroma > 2) { out->err = H264_ERR_BAD_STREAM; goto fail; }
        }

        c.mb_cat[mby * c.mb_w + mbx] = intra4x4 ? 0 : 1;
        c.mb_cmode[mby * c.mb_w + mbx] = (uint8_t)chroma_mode;
        c.mb_cbp[mby * c.mb_w + mbx] = (uint8_t)((cbp_chroma << 4) | cbp_luma);

        int has_residual = (cbp_luma != 0) || (cbp_chroma != 0) || !intra4x4;
        if (has_residual) {
            int32_t delta;
            if (use_cabac) {
                if (cabac_qp_delta(&cbx, last_qpd_nz, &delta, &out->err))
                    goto fail;
                last_qpd_nz = (delta != 0);
            } else {
                delta = bs_se(bs);
            }
            if (delta < -26 || delta > 25 || bs->error) {
                out->err = bs->error ? H264_ERR_TRUNC : H264_ERR_BAD_STREAM;
                goto fail;
            }
            qp = (qp + (int)delta + 52) % 52;
        } else {
            last_qpd_nz = 0;
        }
        c.mb_qp[mby * c.mb_w + mbx] = (uint8_t)qp;
        if (dbg >= 2) {
            fprintf(stderr, "MB %u,%u type=%u cbpL=%u cbpC=%u qp=%d\n",
                    mbx, mby, mb_type, cbp_luma, cbp_chroma, qp);
        }

        /* ---- residual parsing ---- */
        int16_t scan[16];
        int32_t luma_dc[16];
        memset(luma_dc, 0, sizeof(luma_dc));
        if (!intra4x4) {
            int16_t dcraw[16];
            memset(dcraw, 0, sizeof(dcraw));
            if (use_cabac) {
                int ca = cbf_cond_lumadc(&c, mbx, mby, -1, 0);
                int cbn = cbf_cond_lumadc(&c, mbx, mby, 0, -1);
                int tc = cabac_residual(&cbx, 0, ca, cbn, 16, scan, &out->err);
                if (tc < 0) goto fail;
                c.cbf_ldc[mby * c.mb_w + mbx] = (tc != 0);
            } else {
                int nc = derive_nc(c.nzL, bw, (int)(mbx * 4), (int)(mby * 4),
                                   mbx > 0, mby > 0);
                if (cavlc_residual_block(bs, nc, 16, scan, &out->err) < 0)
                    goto fail;
            }
            for (int i = 0; i < 16; i++) dcraw[h264_zigzag4x4[i]] = scan[i];
            h264_luma_dc_dequant(dcraw, qp, luma_dc);
        }

        int16_t resid[16][16];                     /* raster per 4x4 block */
        memset(resid, 0, sizeof(resid));
        for (int k = 0; k < 16; k++) {
            int gx = (int)(mbx * 4 + zscan_x[k]);
            int gy = (int)(mby * 4 + zscan_y[k]);
            if (cbp_luma & (1u << (k >> 2))) {
                int maxc = intra4x4 ? 16 : 15;
                int tc;
                if (use_cabac) {
                    int ca = cbf_cond_luma4(&c, gx - 1, gy);
                    int cbn = cbf_cond_luma4(&c, gx, gy - 1);
                    tc = cabac_residual(&cbx, intra4x4 ? 2 : 1, ca, cbn,
                                        maxc, scan, &out->err);
                    if (tc < 0) goto fail;
                    c.cbf_l[(uint32_t)gy * bw + (uint32_t)gx] = (tc != 0);
                } else {
                    int nc = derive_nc(c.nzL, bw, gx, gy, gx > 0, gy > 0);
                    tc = cavlc_residual_block(bs, nc, maxc, scan, &out->err);
                    if (tc < 0) goto fail;
                }
                c.nzL[(uint32_t)gy * bw + (uint32_t)gx] = (uint8_t)tc;
                if (intra4x4) {
                    for (int i = 0; i < 16; i++)
                        resid[k][h264_zigzag4x4[i]] = scan[i];
                } else {
                    for (int i = 0; i < 15; i++)
                        resid[k][h264_zigzag4x4[i + 1]] = scan[i];
                }
            } else {
                c.nzL[(uint32_t)gy * bw + (uint32_t)gx] = 0;
                c.cbf_l[(uint32_t)gy * bw + (uint32_t)gx] = 0;
            }
        }

        int16_t cdc[2][4];
        memset(cdc, 0, sizeof(cdc));
        if (cbp_chroma != 0) {
            for (int comp = 0; comp < 2; comp++) {
                if (use_cabac) {
                    int ca = cbf_cond_chromadc(&c, comp, mbx, mby, -1, 0);
                    int cbn = cbf_cond_chromadc(&c, comp, mbx, mby, 0, -1);
                    int tc = cabac_residual(&cbx, 3, ca, cbn, 4, scan,
                                            &out->err);
                    if (tc < 0) goto fail;
                    c.cbf_cdc[comp][mby * c.mb_w + mbx] = (tc != 0);
                } else {
                    if (cavlc_residual_block(bs, -1, 4, scan, &out->err) < 0)
                        goto fail;
                }
                for (int i = 0; i < 4; i++) cdc[comp][i] = scan[i];
            }
        }
        int16_t cres[2][4][16];
        memset(cres, 0, sizeof(cres));
        for (int comp = 0; comp < 2; comp++) {
            for (int k = 0; k < 4; k++) {
                int gx = (int)(mbx * 2 + (uint32_t)(k & 1));
                int gy = (int)(mby * 2 + (uint32_t)(k >> 1));
                if (cbp_chroma == 2) {
                    int tc;
                    if (use_cabac) {
                        int ca = cbf_cond_chroma4(&c, comp, gx - 1, gy);
                        int cbn = cbf_cond_chroma4(&c, comp, gx, gy - 1);
                        tc = cabac_residual(&cbx, 4, ca, cbn, 15, scan,
                                            &out->err);
                        if (tc < 0) goto fail;
                        c.cbf_c[comp][(uint32_t)gy * (bw / 2) + (uint32_t)gx] =
                            (tc != 0);
                    } else {
                        int nc = derive_nc(c.nzC[comp], bw / 2, gx, gy,
                                           gx > 0, gy > 0);
                        tc = cavlc_residual_block(bs, nc, 15, scan, &out->err);
                        if (tc < 0) goto fail;
                    }
                    c.nzC[comp][(uint32_t)gy * (bw / 2) + (uint32_t)gx] = (uint8_t)tc;
                    for (int i = 0; i < 15; i++)
                        cres[comp][k][h264_zigzag4x4[i + 1]] = scan[i];
                } else {
                    c.nzC[comp][(uint32_t)gy * (bw / 2) + (uint32_t)gx] = 0;
                    c.cbf_c[comp][(uint32_t)gy * (bw / 2) + (uint32_t)gx] = 0;
                }
            }
        }

        /* ---- reconstruction ---- */
        int32_t d[16];
        if (intra4x4) {
            for (int k = 0; k < 16; k++) {
                int gx = (int)(mbx * 4 + zscan_x[k]);
                int gy = (int)(mby * 4 + zscan_y[k]);
                uint8_t *bdst = c.Y + (size_t)gy * 4 * c.ls + (size_t)gx * 4;
                int aL = gx > 0, aT = gy > 0, aTL = aL && aT;
                int aTR = blk_decoded(&c, mbx, mby, k, gx + 1, gy - 1);
                if (h264_intra4x4_pred(bdst, c.ls, modes[k], aL, aT, aTL, aTR)) {
                    out->err = H264_ERR_BAD_STREAM;
                    goto fail;
                }
                if (cbp_luma & (1u << (k >> 2))) {
                    h264_dequant4x4(resid[k], qp, d);
                    h264_idct4x4_add(bdst, c.ls, d);
                }
            }
        } else {
            if (h264_intra16x16_pred(ydst, c.ls, i16_mode, mbx > 0, mby > 0)) {
                out->err = H264_ERR_BAD_STREAM;
                goto fail;
            }
            for (int k = 0; k < 16; k++) {
                uint32_t x4 = zscan_x[k], y4 = zscan_y[k];
                uint8_t *bdst = ydst + (size_t)y4 * 4 * c.ls + (size_t)x4 * 4;
                h264_dequant4x4(resid[k], qp, d);
                d[0] = luma_dc[y4 * 4 + x4];
                h264_idct4x4_add(bdst, c.ls, d);
            }
        }

        int qpc = h264_chroma_qp(clip3(0, 51, qp + (int)pps->chroma_qp_offset));
        for (int comp = 0; comp < 2; comp++) {
            uint8_t *cdst = comp ? vdst : udst;
            if (h264_intra_chroma_pred(cdst, c.cs, (int)chroma_mode,
                                       mbx > 0, mby > 0)) {
                out->err = H264_ERR_BAD_STREAM;
                goto fail;
            }
            if (cbp_chroma == 0) continue;
            int32_t cdcd[4];
            h264_chroma_dc_dequant(cdc[comp], qpc, cdcd);
            for (int k = 0; k < 4; k++) {
                uint8_t *bdst = cdst + (size_t)(k >> 1) * 4 * c.cs
                                     + (size_t)(k & 1) * 4;
                h264_dequant4x4(cres[comp][k], qpc, d);
                d[0] = cdcd[k];
                h264_idct4x4_add(bdst, c.cs, d);
            }
        }

        if (use_cabac) {
            int eos = cabac_terminate(&cbx);
            int is_last = (mby == c.mb_h - 1) && (mbx == c.mb_w - 1);
            if (eos != is_last || cbx.error) {
                out->err = cbx.error ? H264_ERR_TRUNC : H264_ERR_BAD_STREAM;
                goto fail;
            }
        }
    }
    }
    }

    /* ---- in-loop deblocking (8.7) ---- */
    if (sh->disable_deblock != 1) {
        h264_deblock_frame(c.Y, c.U, c.V, c.ls, c.cs, c.mb_w, c.mb_h,
                           c.mb_qp, (int)pps->chroma_qp_offset,
                           (int)sh->alpha_c0_offset, (int)sh->beta_offset);
    }

    /* ---- crop to output planes ---- */
    {
    uint32_t W = c.mb_w * 16 - 2 * (sps->crop_l + sps->crop_r);
    uint32_t H = c.mb_h * 16 - 2 * (sps->crop_t + sps->crop_b);
    out->width = (uint16_t)W;
    out->height = (uint16_t)H;
    uint32_t cw = W / 2, chh = H / 2;
    out->y_plane = (uint8_t *)malloc((size_t)W * H);
    out->cb_plane = (uint8_t *)malloc((size_t)cw * chh);
    out->cr_plane = (uint8_t *)malloc((size_t)cw * chh);
    if (!out->y_plane || !out->cb_plane || !out->cr_plane) {
        out->err = H264_ERR_INTERNAL;
        goto fail;
    }
    size_t yoff = (size_t)sps->crop_t * 2 * c.ls + (size_t)sps->crop_l * 2;
    size_t coff = (size_t)sps->crop_t * c.cs + (size_t)sps->crop_l;
    for (uint32_t r = 0; r < H; r++)
        memcpy(out->y_plane + (size_t)r * W, c.Y + yoff + (size_t)r * c.ls, W);
    for (uint32_t r = 0; r < chh; r++) {
        memcpy(out->cb_plane + (size_t)r * cw, c.U + coff + (size_t)r * c.cs, cw);
        memcpy(out->cr_plane + (size_t)r * cw, c.V + coff + (size_t)r * c.cs, cw);
    }
    }

    free(c.Y); free(c.U); free(c.V);
    free(c.i4_mode); free(c.nzL); free(c.nzC[0]); free(c.nzC[1]);
    free(c.mb_qp); free(c.mb_cat); free(c.mb_cmode); free(c.mb_cbp);
    free(c.cbf_l); free(c.cbf_ldc); free(c.cbf_c[0]); free(c.cbf_c[1]);
    free(c.cbf_cdc[0]); free(c.cbf_cdc[1]);
    out->err = 0;
    return 0;

fail:
    free(c.Y); free(c.U); free(c.V);
    free(c.i4_mode); free(c.nzL); free(c.nzC[0]); free(c.nzC[1]);
    free(c.mb_qp); free(c.mb_cat); free(c.mb_cmode); free(c.mb_cbp);
    free(c.cbf_l); free(c.cbf_ldc); free(c.cbf_c[0]); free(c.cbf_c[1]);
    free(c.cbf_cdc[0]); free(c.cbf_cdc[1]);
    return -1;
}

/* Decode the first IDR I-frame: scan NALs, latch SPS/PPS, then decode the
 * slice. On error the wrapper releases any planes; only err survives. */
static int h264_decode_impl(const uint8_t *data, size_t size,
                            h264_decoded_t *out) {
    memset(out, 0, sizeof(*out));
    sps_t sps;
    pps_t pps;
    memset(&sps, 0, sizeof(sps));
    memset(&pps, 0, sizeof(pps));

    size_t pos = 0;
    nal_t n;
    int saw_nal = 0;
    while (nal_next(data, size, &pos, &n) == 0) {
        saw_nal = 1;
        bs_t bs;
        bs_init(&bs, n.rbsp, n.size);
        if (n.type == NAL_SPS) {
            if (parse_sps(&bs, &sps, &out->err)) { nal_free(&n); return -1; }
            if (trace_level()) {
                fprintf(stderr,
                        "[SPS] profile=%u level=%u %ux%u MBs poc_type=%u "
                        "crop l=%u r=%u t=%u b=%u\n",
                        sps.profile_idc, sps.level_idc,
                        sps.mb_width, sps.mb_height, sps.poc_type,
                        sps.crop_l, sps.crop_r, sps.crop_t, sps.crop_b);
            }
        } else if (n.type == NAL_PPS) {
            if (parse_pps(&bs, &pps, &out->err)) { nal_free(&n); return -1; }
            if (trace_level()) {
                fprintf(stderr,
                        "[PPS] entropy=%d init_qp=%d cqp_off=%d dbf_ctrl=%d\n",
                        pps.entropy_coding_mode, pps.pic_init_qp,
                        pps.chroma_qp_offset, pps.deblock_control_present);
            }
        } else if (n.type == NAL_SLICE_IDR || n.type == NAL_SLICE_NON_IDR) {
            if (!sps.valid) { out->err = H264_ERR_NO_SPS; nal_free(&n); return -1; }
            if (!pps.valid) { out->err = H264_ERR_NO_PPS; nal_free(&n); return -1; }
            slice_hdr_t sh;
            if (parse_slice_header(&bs, &sps, &pps, n.type, n.ref_idc,
                                   &sh, &out->err)) {
                nal_free(&n);
                return -1;
            }
            if (sh.first_mb != 0) {                /* single-slice scope */
                out->err = H264_ERR_UNSUP;
                nal_free(&n);
                return -1;
            }
            if (trace_level()) {
                fprintf(stderr,
                        "[SLICE] type=%u qp=%d disable_deblock=%d a_off=%d b_off=%d\n",
                        sh.slice_type, sh.slice_qp, sh.disable_deblock,
                        sh.alpha_c0_offset, sh.beta_offset);
            }
            int rc = decode_islice(&bs, &sps, &pps, &sh, out);
            nal_free(&n);
            return rc;
        }
        /* SEI / AUD / filler: skipped. */
        nal_free(&n);
    }
    out->err = saw_nal ? H264_ERR_NO_SLICE : H264_ERR_NO_NAL;
    return -1;
}

int h264_decode(const uint8_t *data, size_t size, h264_decoded_t *out) {
    int rc = h264_decode_impl(data, size, out);
    if (rc != 0) {
        uint32_t err = out->err;
        h264_free(out);
        out->err = err;
    }
    return rc;
}

void h264_free(h264_decoded_t *out) {
    free(out->y_plane);
    free(out->cb_plane);
    free(out->cr_plane);
    memset(out, 0, sizeof(*out));
}
