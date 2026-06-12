#include "decoder.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bitstream.h"
#include "cabac.h"
#include "cavlc.h"
#include "deblock.h"
#include "intra.h"
#include "mc.h"
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

/* RTL golden-intermediate dump (docs/rtl_spec.md R1): per-MB records
 * of the coefficient layer for cavlc_dec testbench comparison. Only
 * the RTL subset (baseline I, CAVLC, no t8) is recorded. */
static FILE *rtl_dump_file(void) {
    static FILE *f;
    static int tried;
    if (!tried) {
        tried = 1;
        const char *path = getenv("H264_RTL_DUMP");
        if (path) f = fopen(path, "wb");
    }
    return f;
}

static void rtl_dump_mb(uint32_t mbx, uint32_t mby, int cat, uint32_t cbp,
                        int qp, int i16_mode, uint32_t cmode,
                        const uint8_t *i4m, const int16_t resid[16][16],
                        const int16_t dcraw[16], const int16_t cdc[2][4],
                        const int16_t cres[2][4][16]) {
    FILE *f = rtl_dump_file();
    if (!f) return;
    uint8_t hdr[8] = {
        (uint8_t)mbx, (uint8_t)(mbx >> 8) /* mb_w<=120 fits, keep u16 */,
        (uint8_t)mby, (uint8_t)cat, (uint8_t)cbp, (uint8_t)qp,
        (uint8_t)i16_mode, (uint8_t)cmode
    };
    fwrite(hdr, 1, 8, f);
    fwrite(i4m, 1, 16, f);
    fwrite(resid, sizeof(int16_t), 16 * 16, f);
    fwrite(dcraw, sizeof(int16_t), 16, f);
    fwrite(cdc, sizeof(int16_t), 8, f);
    fwrite(cres, sizeof(int16_t), 2 * 4 * 16, f);
}

/* Reconstruction-layer dump (R2c): per-MB pixels before deblocking,
 * 384 bytes (256 luma + 64 + 64 chroma), same gating as rtl_dump_mb. */
static FILE *rtl_dump_rec_file(void) {
    static FILE *f;
    static int tried;
    if (!tried) {
        tried = 1;
        const char *path = getenv("H264_RTL_DUMP_REC");
        if (path) f = fopen(path, "wb");
    }
    return f;
}

static void rtl_dump_rec(const uint8_t *y, size_t ls, const uint8_t *u,
                         const uint8_t *v, size_t cs) {
    FILE *f = rtl_dump_rec_file();
    if (!f) return;
    for (int r = 0; r < 16; r++) fwrite(y + (size_t)r * ls, 1, 16, f);
    for (int r = 0; r < 8; r++) fwrite(u + (size_t)r * cs, 1, 8, f);
    for (int r = 0; r < 8; r++) fwrite(v + (size_t)r * cs, 1, 8, f);
}

/* P-syntax dump (P-R3a): one record per P-slice macroblock for the
 * RTL parser testbench. Gated to the P-R3 subset: CAVLC, single
 * reference, no B. Layout (little-endian, 140 bytes):
 *   u8 mbx, mby, skip, mb_type(0..4 inter, 5+ intra), sub[4], qp
 *   s16 mvd[16][2]  (parse order, zero-filled)
 *   s16 mv[16][2]   (final per-4x4, z-scan order)  */
static FILE *rtl_dump_p_file(void) {
    static FILE *f;
    static int tried;
    if (!tried) {
        tried = 1;
        const char *path = getenv("H264_RTL_DUMP_P");
        if (path) f = fopen(path, "wb");
    }
    return f;
}

/* P reconstruction pixels (P-R3d): 384B/MB like DUMP_REC, written at
 * mb_done so skipped MBs (pure MC) are covered too. Same gate as the
 * P-syntax dump minus weighted prediction (pixel-level effect). */
static FILE *rtl_dump_prec_file(void) {
    static FILE *f;
    static int tried;
    if (!tried) {
        tried = 1;
        const char *path = getenv("H264_RTL_DUMP_PREC");
        if (path) f = fopen(path, "wb");
    }
    return f;
}

static void rtl_dump_prec(const uint8_t *y, size_t ls, const uint8_t *u,
                          const uint8_t *v, size_t cs) {
    FILE *f = rtl_dump_prec_file();
    if (!f) return;
    for (int r = 0; r < 16; r++) fwrite(y + (size_t)r * ls, 1, 16, f);
    for (int r = 0; r < 8; r++) fwrite(u + (size_t)r * cs, 1, 8, f);
    for (int r = 0; r < 8; r++) fwrite(v + (size_t)r * cs, 1, 8, f);
}

/* B-syntax dump (W16-a): one record per gated B-slice macroblock.
 * Layout (LE, 284 bytes):
 *   u8 mbx, mby, skip, mb_type(0..22 inter, 23+ intra), sub[4], qp,
 *   u8 direct_spatial, pad[2]
 *   s16 mvd[2][16][2]  (parse order per list, zero-filled)
 *   s16 mv[2][16][2]   (final per-4x4 z-scan, both lists)
 *   u8 pmode[16]       (z-scan: bit0 L0 used, bit1 L1 used; 0=intra) */
typedef struct {
    uint8_t mbx, mby, skip, mb_type;
    uint8_t sub[4];
    uint8_t qp, dsp, pad[2];
    int16_t mvd[2][16][2];
    int16_t mv[2][16][2];
    uint8_t pmode[16];
} rtl_b_rec_t;

static FILE *rtl_dump_b_file(void) {
    static FILE *f;
    static int tried;
    if (!tried) {
        tried = 1;
        const char *path = getenv("H264_RTL_DUMP_B");
        if (path) f = fopen(path, "wb");
    }
    return f;
}

static void rtl_dump_b(const rtl_b_rec_t *r) {
    FILE *f = rtl_dump_b_file();
    if (f) fwrite(r, sizeof(*r), 1, f);
}

/* One-shot reference-plane dump for the P-R3d bench: the FIRST gated
 * P slice's list0[0] uncropped planes (the bench implements the MC
 * clamp over these). Layout: u16 mb_w, u16 mb_h (LE), then Y, U, V. */
static void rtl_dump_ref_once(uint32_t mb_w, uint32_t mb_h,
                              const uint8_t *y, const uint8_t *u,
                              const uint8_t *v) {
    static int done;
    if (done) return;
    done = 1;
    const char *path = getenv("H264_RTL_DUMP_REF");
    if (!path) return;
    FILE *f = fopen(path, "wb");
    if (!f) return;
    uint16_t hdr[2] = { (uint16_t)mb_w, (uint16_t)mb_h };
    fwrite(hdr, 2, 2, f);
    fwrite(y, 1, (size_t)mb_w * 16 * mb_h * 16, f);
    fwrite(u, 1, (size_t)mb_w * 8 * mb_h * 8, f);
    fwrite(v, 1, (size_t)mb_w * 8 * mb_h * 8, f);
    fclose(f);
}

typedef struct {
    uint8_t mbx, mby, skip, mb_type;
    uint8_t sub[4];
    uint8_t qp;
    uint8_t pad[3];
    int16_t mvd[16][2];
    int16_t mv[16][2];
} rtl_p_rec_t;

static void rtl_dump_p(const rtl_p_rec_t *r) {
    FILE *f = rtl_dump_p_file();
    if (!f) return;
    fwrite(r, sizeof(*r), 1, f);
}

/* A reference frame: padded planes + motion field (for B direct). */
typedef struct {
    uint8_t *Y, *U, *V;
    int16_t *mvx, *mvy;        /* per 4x4, quarter-pel (list0) */
    int8_t *ref;               /* per 4x4 list0 ref idx, -1 intra */
    int16_t *mv1x, *mv1y;      /* list1 (colocated L1 fallback, 8.4.1.2.2) */
    int8_t *ref1;
    int32_t poc;
    uint32_t frame_num;
    int32_t ref2poc[8];        /* POC per list0 ref idx at decode time */
    int n_ref2poc;
} dpb_ent_t;

static void dpb_ent_free(dpb_ent_t *e) {
    free(e->Y); free(e->U); free(e->V);
    free(e->mvx); free(e->mvy); free(e->ref);
    free(e->mv1x); free(e->mv1y); free(e->ref1);
    memset(e, 0, sizeof(*e));
}

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
    uint8_t *mb_t8;            /* transform_size_8x8_flag per MB */
    uint16_t *mb_slice;        /* owning slice index per MB (0xFFFF = none) */
    int16_t *mv_x, *mv_y;      /* per 4x4 block, quarter-pel (list0) */
    int8_t *mb_ref;            /* per 4x4: list0 ref, -1 = intra/none */
    int16_t *mv1_x, *mv1_y;    /* list1 motion (B) */
    int8_t *mb_ref1;
    uint8_t *blk_direct;       /* per 4x4: decoded via direct (B ctxInc) */
    int32_t *ref_poc0, *ref_poc1; /* per 4x4 POC of each prediction, or
                                   * POC_NONE — deblock bS compares these */
    uint8_t *mb_skip;          /* per MB: decoded as skipped (CABAC ctx) */
    uint8_t *mb_bdirect;       /* per MB: B_Skip/B_Direct_16x16 (ctxInc) */
    int n_refs;                /* list0 length (most recent first) */
    const slice_hdr_t *wp_sh;  /* active slice (weighted prediction) */
    int imp_wp;                /* implicit weighted bipred active */
    uint8_t wimp[8][8];        /* w0 per (ref0,ref1); w1 = 64 - w0 */
    uint8_t *mvd_ax, *mvd_ay;  /* per 4x4: |mvd| clipped to 70 (mvd ctxInc) */
    uint8_t *mvd1_ax, *mvd1_ay;
    const dpb_ent_t *list0[8];           /* ordered reference lists */
    const dpb_ent_t *list1[8];
    int n_l1;

    int8_t *mb_dbf_idc;        /* per-MB slice deblock params */
    int8_t *mb_dbf_a, *mb_dbf_b;
} ictx_t;

static int clip3(int lo, int hi, int v) {
    return v < lo ? lo : (v > hi ? hi : v);
}

#define POC_NONE INT32_MIN

/* An MB neighbor is available iff it is inside the picture AND belongs to
 * the same slice (6.4.9; raster order makes decoded-before implicit). */
static int mb_avail(const ictx_t *c, int sid, int nx, int ny) {
    if (nx < 0 || ny < 0 || nx >= (int)c->mb_w) return 0;
    return c->mb_slice[(uint32_t)ny * c->mb_w + (uint32_t)nx] == (uint16_t)sid;
}

/* 4x4-block-granular availability: the block's MB must be available. */
static int blk4_avail(const ictx_t *c, int sid, int gx, int gy) {
    if (gx < 0 || gy < 0 || (uint32_t)gx >= c->mb_w * 4) return 0;
    return mb_avail(c, sid, gx >> 2, gy >> 2);
}

/* Has luma 4x4 block (gbx,gby) been decoded before z-index cur_k of MB
 * (cur_mbx,cur_mby)? Single-slice raster MB order + z-scan inside the MB. */
static int blk_decoded(const ictx_t *c, int sid, uint32_t cur_mbx,
                       uint32_t cur_mby, int cur_k, int gbx, int gby) {
    if (gbx < 0 || gby < 0 || (uint32_t)gbx >= c->mb_w * 4) return 0;
    uint32_t mbx = (uint32_t)gbx >> 2, mby = (uint32_t)gby >> 2;
    if (!(mbx == cur_mbx && mby == cur_mby) &&
        !mb_avail(c, sid, (int)mbx, (int)mby)) return 0;
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
static uint32_t cabac_mb_type_I(cabac_t *cb, const ictx_t *c, int sid,
                                uint32_t mbx, uint32_t mby) {
    int inc = 0;
    if (mb_avail(c, sid, (int)mbx - 1, (int)mby) &&
        c->mb_cat[mby * c->mb_w + mbx - 1] != 0) inc++;
    if (mb_avail(c, sid, (int)mbx, (int)mby - 1) &&
        c->mb_cat[(mby - 1) * c->mb_w + mbx] != 0) inc++;
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

static uint32_t cabac_chroma_mode(cabac_t *cb, const ictx_t *c, int sid,
                                  uint32_t mbx, uint32_t mby) {
    int inc = 0;
    if (mb_avail(c, sid, (int)mbx - 1, (int)mby) &&
        c->mb_cmode[mby * c->mb_w + mbx - 1] != 0) inc++;
    if (mb_avail(c, sid, (int)mbx, (int)mby - 1) &&
        c->mb_cmode[(mby - 1) * c->mb_w + mbx] != 0) inc++;
    if (cabac_decision(cb, 64 + inc) == 0) return 0;
    if (cabac_decision(cb, 67) == 0) return 1;
    if (cabac_decision(cb, 67) == 0) return 2;
    return 3;
}

/* CBP, I_4x4 path (ctx 73..76 luma, 77..84 chroma; neighbor semantics per
 * ffmpeg decode_cabac_mb_cbp_*: unavailable intra neighbor reads as 0x7F,
 * I_PCM as 0x2F). */
static uint32_t cabac_cbp(cabac_t *cb, const ictx_t *c, int sid,
                          uint32_t mbx, uint32_t mby) {
    /* Unavailable neighbors read as luma-all-set / chroma-zero (0x0F):
     * luma condTerm = available && bit==0, chroma condTerm needs an
     * available nonzero-cbp neighbor (9.3.3.1.1.4, verified vs JM). */
    uint32_t cbp_a = mb_avail(c, sid, (int)mbx - 1, (int)mby)
                         ? c->mb_cbp[mby * c->mb_w + mbx - 1] : 0x0F;
    uint32_t cbp_b = mb_avail(c, sid, (int)mbx, (int)mby - 1)
                         ? c->mb_cbp[(mby - 1) * c->mb_w + mbx] : 0x0F;
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

/* mb_skip_flag (P): ctx 11 + available-and-not-skipped neighbors. */
static int cabac_mb_skip(cabac_t *cb, const ictx_t *c, int sid, int is_b,
                         uint32_t mbx, uint32_t mby) {
    int inc = 0;
    if (mb_avail(c, sid, (int)mbx - 1, (int)mby) &&
        !c->mb_skip[mby * c->mb_w + mbx - 1]) inc++;
    if (mb_avail(c, sid, (int)mbx, (int)mby - 1) &&
        !c->mb_skip[(mby - 1) * c->mb_w + mbx]) inc++;
    return cabac_decision(cb, (is_b ? 24 : 11) + inc);
}

/* Intra mb_type suffix at base ctx 17 (P slices): bin0@17, terminate for
 * PCM, cbpL@18, cbpC@19/19, pred@20/20 — per ffmpeg
 * decode_cabac_intra_mb_type(ctx_base=17, intra_slice=0). */
static uint32_t cabac_mb_type_I_suffix(cabac_t *cb, int base) {
    if (cabac_decision(cb, base) == 0) return 0;   /* I_4x4 */
    if (cabac_terminate(cb)) return 25;            /* I_PCM */
    uint32_t mt = 1;
    mt += 12u * (uint32_t)cabac_decision(cb, base + 1);
    if (cabac_decision(cb, base + 2)) {
        mt += 4u * (1u + (uint32_t)cabac_decision(cb, base + 2));
    }
    mt += 2u * (uint32_t)cabac_decision(cb, base + 3);
    mt += (uint32_t)cabac_decision(cb, base + 3);
    return mt;
}

/* P mb_type tree (ctx 14..17). Returns the ue-equivalent value: 0..4
 * inter (4 = P_8x8ref0 never produced), >=5 means 5 + intra mb_type. */
static uint32_t cabac_p_mb_type(cabac_t *cb) {
    if (cabac_decision(cb, 14)) {
        return 5 + cabac_mb_type_I_suffix(cb, 17);
    }
    if (cabac_decision(cb, 15) == 0) {
        return cabac_decision(cb, 16) ? 3u : 0u;   /* P_8x8 : 16x16 */
    }
    return cabac_decision(cb, 17) ? 1u : 2u;       /* 16x8 : 8x16 */
}

/* B mb_type tree (ctx 27..32); >=23 means 23 + intra mb_type. */
static uint32_t cabac_b_mb_type(cabac_t *cb, const ictx_t *c, int sid,
                                uint32_t mbx, uint32_t mby) {
    int inc = 0;
    if (mb_avail(c, sid, (int)mbx - 1, (int)mby) &&
        !c->mb_bdirect[mby * c->mb_w + mbx - 1]) inc++;
    if (mb_avail(c, sid, (int)mbx, (int)mby - 1) &&
        !c->mb_bdirect[(mby - 1) * c->mb_w + mbx]) inc++;
    if (!cabac_decision(cb, 27 + inc)) return 0;   /* B_Direct_16x16 */
    if (!cabac_decision(cb, 30)) {
        return 1 + (uint32_t)cabac_decision(cb, 32);
    }
    uint32_t bits;
    bits = (uint32_t)cabac_decision(cb, 31) << 3;
    bits |= (uint32_t)cabac_decision(cb, 32) << 2;
    bits |= (uint32_t)cabac_decision(cb, 32) << 1;
    bits |= (uint32_t)cabac_decision(cb, 32);
    if (bits < 8) return bits + 3;
    if (bits == 13) return 23 + cabac_mb_type_I_suffix(cb, 32);
    if (bits == 14) return 11;
    if (bits == 15) return 22;
    bits = (bits << 1) | (uint32_t)cabac_decision(cb, 32);
    return bits - 4;
}

/* B sub_mb_type (ctx 36..39), Table 7-18 indices. */
static uint32_t cabac_b_sub_type(cabac_t *cb) {
    if (!cabac_decision(cb, 36)) return 0;         /* B_Direct_8x8 */
    if (!cabac_decision(cb, 37)) {
        return 1 + (uint32_t)cabac_decision(cb, 39);
    }
    uint32_t type = 3;
    if (cabac_decision(cb, 38)) {
        if (cabac_decision(cb, 39)) {
            return 11 + (uint32_t)cabac_decision(cb, 39);
        }
        type += 4;
    }
    type += 2u * (uint32_t)cabac_decision(cb, 39);
    type += (uint32_t)cabac_decision(cb, 39);
    return type;
}

/* sub_mb_type (P): ctx 21..23. */
static uint32_t cabac_p_sub_type(cabac_t *cb) {
    if (cabac_decision(cb, 21)) return 0;          /* 8x8 */
    if (!cabac_decision(cb, 22)) return 1;         /* 8x4 */
    return cabac_decision(cb, 23) ? 2u : 3u;       /* 4x8 : 4x4 */
}

/* mvd component (9.3.3.1.1.7, UEG3): base 40 (x) / 47 (y), bin0 ctxInc
 * from the neighbor |mvd| sum; clipped |mvd| out for future neighbors. */
static int cabac_mvd(cabac_t *cb, int base, int amvd, int16_t *out,
                     uint32_t *err) {
    int inc = (amvd > 2 ? 1 : 0) + (amvd > 32 ? 1 : 0);
    if (!cabac_decision(cb, base + inc)) {
        *out = 0;
        return 0;
    }
    int mvd = 1;
    int ctx = base + 3;
    while (mvd < 9 && cabac_decision(cb, ctx)) {
        if (mvd < 4) ctx++;
        mvd++;
    }
    if (mvd >= 9) {
        int k = 3;
        while (cabac_bypass(cb)) {
            mvd += 1 << k;
            k++;
            if (k > 24) { *err = H264_ERR_BAD_STREAM; return -1; }
        }
        while (k--) mvd += cabac_bypass(cb) << k;
    }
    if (cb->error) { *err = H264_ERR_TRUNC; return -1; }
    *out = (int16_t)(cabac_bypass(cb) ? -mvd : mvd);
    return mvd < 70 ? mvd : 70;
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

/* High-profile 8x8 residual (ctxBlockCat 5): no coded_block_flag, the
 * significance/last maps use position->ctx tables (JM pos2ctx_map8x8 /
 * pos2ctx_last8x8), levels run the same node machine at 426+. Output in
 * 8x8 zigzag scan order. Returns total_coeff or -1. */
static int cabac_residual8x8(cabac_t *cb, int16_t scan[64], uint32_t *err) {
    static const uint8_t sig8[64] = {
        0, 1, 2, 3, 4, 5, 5, 4, 4, 3, 3, 4, 4, 4, 5, 5,
        4, 4, 4, 4, 3, 3, 6, 7, 7, 7, 8, 9,10, 9, 8, 7,
        7, 6,11,12,13,11, 6, 7, 8, 9,14,10, 9, 8, 6,11,
       12,13,11, 6, 9,14,10, 9,11,12,13,11,14,10,12,14
    };
    static const uint8_t last8[64] = {
        0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4,
        5, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7, 8, 8, 8, 8
    };
    static const uint8_t l1ctx[8] = { 1, 2, 3, 4, 0, 0, 0, 0 };
    static const uint8_t gt1ctx[8] = { 5, 5, 5, 5, 6, 7, 8, 9 };
    static const uint8_t tr_eq1[8] = { 1, 2, 3, 3, 4, 5, 6, 7 };
    static const uint8_t tr_gt1[8] = { 4, 4, 4, 4, 5, 6, 7, 7 };

    memset(scan, 0, 64 * sizeof(scan[0]));
    int idx[64];
    int cnt = 0;
    int i;
    for (i = 0; i < 63; i++) {
        if (cabac_decision(cb, 402 + sig8[i])) {
            idx[cnt++] = i;
            if (cabac_decision(cb, 417 + last8[i])) break;
        }
    }
    if (i == 63) idx[cnt++] = 63;
    if (cnt == 0 || cb->error) { *err = H264_ERR_BAD_STREAM; return -1; }

    int total = cnt;
    int node = 0;
    while (cnt) {
        int pos = idx[--cnt];
        int abs_lvl;
        if (!cabac_decision(cb, 426 + l1ctx[node])) {
            abs_lvl = 1;
            node = tr_eq1[node];
        } else {
            abs_lvl = 2;
            int ctx = 426 + gt1ctx[node];
            node = tr_gt1[node];
            while (abs_lvl < 15 && cabac_decision(cb, ctx)) abs_lvl++;
            if (abs_lvl >= 15) {
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
static int cbf_cond_luma4(const ictx_t *c, int cur_intra, int sid, int gx, int gy) {
    uint32_t bw = c->mb_w * 4;
    if (!blk4_avail(c, sid, gx, gy)) return cur_intra;
    uint32_t mb = ((uint32_t)gy >> 2) * c->mb_w + ((uint32_t)gx >> 2);
    if (c->mb_cat[mb] == 2) return 1;
    return c->cbf_l[(uint32_t)gy * bw + (uint32_t)gx];
}

static int cbf_cond_chroma4(const ictx_t *c, int cur_intra, int sid, int comp,
                            int gx, int gy) {
    uint32_t cw = c->mb_w * 2;
    if (gx < 0 || gy < 0 || (uint32_t)gx >= cw) return cur_intra;
    if (!mb_avail(c, sid, gx >> 1, gy >> 1)) return cur_intra;
    uint32_t mb = ((uint32_t)gy >> 1) * c->mb_w + ((uint32_t)gx >> 1);
    if (c->mb_cat[mb] == 2) return 1;
    return c->cbf_c[comp][(uint32_t)gy * cw + (uint32_t)gx];
}

static int cbf_cond_lumadc(const ictx_t *c, int cur_intra, int sid, uint32_t mbx,
                           uint32_t mby, int dx, int dy) {
    int nx = (int)mbx + dx, ny = (int)mby + dy;
    if (!mb_avail(c, sid, nx, ny)) return cur_intra;
    uint32_t mb = (uint32_t)ny * c->mb_w + (uint32_t)nx;
    if (c->mb_cat[mb] == 2) return 1;
    if (c->mb_cat[mb] != 1) return 0;          /* no DC block in I_4x4 */
    return c->cbf_ldc[mb];
}

static int cbf_cond_chromadc(const ictx_t *c, int cur_intra, int sid, int comp,
                             uint32_t mbx, uint32_t mby, int dx, int dy) {
    int nx = (int)mbx + dx, ny = (int)mby + dy;
    if (!mb_avail(c, sid, nx, ny)) return cur_intra;
    uint32_t mb = (uint32_t)ny * c->mb_w + (uint32_t)nx;
    if (c->mb_cat[mb] == 2) return 1;
    return c->cbf_cdc[comp][mb];
}

/* Table 9-4, Inter column (via ffmpeg ff_h264_golomb_to_inter_cbp). */
static const uint8_t golomb_to_inter_cbp[48] = {
    0,  16, 1,  2,  4,  8,  32, 3,  5,  10, 12, 15, 47, 7,  11, 13,
    14, 6,  9,  31, 35, 37, 42, 44, 33, 34, 36, 40, 39, 43, 45, 46,
    17, 18, 20, 24, 19, 21, 26, 28, 23, 27, 29, 30, 22, 25, 38, 41
};

/* Fetch a neighbor block's motion for prediction (8.4.1.3.2): returns 1
 * with mv/ref when the block is available AND already decoded; intra
 * blocks yield mv=(0,0) ref=-1. ref==-2 marks not-yet-decoded blocks of
 * the current MB. */
static int mv_nbr(const ictx_t *c, int list, int sid, int gx, int gy,
                  int16_t *mx, int16_t *my, int *ref) {
    *mx = 0; *my = 0; *ref = -1;
    if (!blk4_avail(c, sid, gx, gy)) return 0;
    uint32_t bw = c->mb_w * 4;
    uint32_t gi = (uint32_t)gy * bw + (uint32_t)gx;
    if (c->mb_ref[gi] == -2) return 0;             /* undecoded (this MB) */
    if (list == 0) {
        *mx = c->mv_x[gi];
        *my = c->mv_y[gi];
        *ref = c->mb_ref[gi];
    } else {
        *mx = c->mv1_x[gi];
        *my = c->mv1_y[gi];
        *ref = c->mb_ref1[gi];
    }
    return 1;
}

static int med3(int a, int b, int cc) {
    if (a > b) { int tmp = a; a = b; b = tmp; }
    if (b > cc) b = cc;
    return a > b ? a : b;
}

/* Luma MV prediction (8.4.1.3): partition at (gx,gy) of w4*h4 4x4 units.
 * ptype: 0 normal, 1/2 = 16x8 top/bottom, 3/4 = 8x16 left/right. */
static void mv_pred(const ictx_t *c, int list, int sid, int gx, int gy,
                    int w4, int ptype, int cur_ref,
                    int16_t *pmx, int16_t *pmy) {
    int16_t ax, ay, bx, by, cx, cy;
    int ar, br, cr;
    int has_a = mv_nbr(c, list, sid, gx - 1, gy, &ax, &ay, &ar);
    int has_b = mv_nbr(c, list, sid, gx, gy - 1, &bx, &by, &br);
    int has_c = mv_nbr(c, list, sid, gx + w4, gy - 1, &cx, &cy, &cr);
    if (!has_c) {
        has_c = mv_nbr(c, list, sid, gx - 1, gy - 1, &cx, &cy, &cr);
    }

    /* Directional special cases (8.4.1.3, matching reference). */
    if (ptype == 1 && br == cur_ref) { *pmx = bx; *pmy = by; return; }
    if (ptype == 2 && ar == cur_ref) { *pmx = ax; *pmy = ay; return; }
    if (ptype == 3 && ar == cur_ref) { *pmx = ax; *pmy = ay; return; }
    if (ptype == 4 && cr == cur_ref) { *pmx = cx; *pmy = cy; return; }

    if (!has_b && !has_c && has_a) {               /* only A decoded */
        *pmx = ax; *pmy = ay; return;
    }
    int match = (ar == cur_ref) + (br == cur_ref) + (cr == cur_ref);
    if (match == 1) {
        if (ar == cur_ref) { *pmx = ax; *pmy = ay; }
        else if (br == cur_ref) { *pmx = bx; *pmy = by; }
        else { *pmx = cx; *pmy = cy; }
        return;
    }
    *pmx = (int16_t)med3(ax, bx, cx);
    *pmy = (int16_t)med3(ay, by, cy);
}

/* Motion-compensate one partition: (gx,gy) in 4x4 units, w4*h4 size,
 * write mv/ref bookkeeping and predict into the current frame. */
/* 8.4.2.3.2 single-direction explicit weighting, in place. */
static void wp_apply(uint8_t *dst, size_t stride, int bw, int bh,
                     int w, int o, int logwd) {
    for (int j = 0; j < bh; j++) {
        for (int i = 0; i < bw; i++) {
            uint8_t *px = dst + (size_t)j * stride + (size_t)i;
            int v;
            if (logwd >= 1) {
                v = (((int)*px * w + (1 << (logwd - 1))) >> logwd) + o;
            } else {
                v = (int)*px * w + o;
            }
            *px = (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
        }
    }
}

/* MC one direction of one partition into dst planes (frame or temp). */
static void mc_one(const ictx_t *c, const dpb_ent_t *rf, int gx, int gy,
                   int w4, int h4, int16_t mvx, int16_t mvy,
                   uint8_t *dy, size_t dys, uint8_t *du, uint8_t *dv,
                   size_t dcs) {
    int lx = gx * 4, ly = gy * 4;
    int pw = (int)c->ls, phh = (int)(c->mb_h * 16);
    h264_mc_luma(rf->Y, c->ls, pw, phh,
                 lx + (mvx >> 2), ly + (mvy >> 2), mvx & 3, mvy & 3,
                 dy, dys, w4 * 4, h4 * 4);
    int cx = gx * 2, cy = gy * 2;
    int cw = (int)c->cs, chh = (int)(c->mb_h * 8);
    h264_mc_chroma(rf->U, c->cs, cw, chh,
                   cx + (mvx >> 3), cy + (mvy >> 3), mvx & 7, mvy & 7,
                   du, dcs, w4 * 2, h4 * 2);
    h264_mc_chroma(rf->V, c->cs, cw, chh,
                   cx + (mvx >> 3), cy + (mvy >> 3), mvx & 7, mvy & 7,
                   dv, dcs, w4 * 2, h4 * 2);
}

static void avg_block(uint8_t *dst, size_t ds, const uint8_t *src,
                      size_t ss, int w, int h) {
    for (int j = 0; j < h; j++)
        for (int i = 0; i < w; i++) {
            uint8_t *d = dst + (size_t)j * ds + (size_t)i;
            *d = (uint8_t)((*d + src[(size_t)j * ss + (size_t)i] + 1) >> 1);
        }
}

/* Implicit weighted bi-prediction: dst = clip((dst*w0 + src*w1 + 32)>>6) */
static void wavg_block(uint8_t *dst, size_t ds, const uint8_t *src,
                       size_t ss, int w, int h, int w0, int w1) {
    for (int j = 0; j < h; j++)
        for (int i = 0; i < w; i++) {
            uint8_t *d = dst + (size_t)j * ds + (size_t)i;
            int v = (*d * w0 + src[(size_t)j * ss + (size_t)i] * w1 + 32)
                    >> 6;
            *d = (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
        }
}

/* Predict one partition. mode: 1 = L0, 2 = L1, 3 = Bi (default average).
 * Writes both lists' motion bookkeeping and the per-block POCs. */
static void inter_pred_lx(ictx_t *c, int mode, int r0, int r1,
                          int gx, int gy, int w4, int h4,
                          int16_t m0x, int16_t m0y,
                          int16_t m1x, int16_t m1y) {
    uint32_t bw = c->mb_w * 4;
    for (int j = 0; j < h4; j++)
        for (int i = 0; i < w4; i++) {
            uint32_t gi = (uint32_t)(gy + j) * bw + (uint32_t)(gx + i);
            c->mv_x[gi] = (mode & 1) ? m0x : 0;
            c->mv_y[gi] = (mode & 1) ? m0y : 0;
            c->mb_ref[gi] = (mode & 1) ? (int8_t)r0 : -1;
            c->mv1_x[gi] = (mode & 2) ? m1x : 0;
            c->mv1_y[gi] = (mode & 2) ? m1y : 0;
            c->mb_ref1[gi] = (mode & 2) ? (int8_t)r1 : -1;
            c->ref_poc0[gi] = (mode & 1) ? c->list0[r0]->poc : POC_NONE;
            c->ref_poc1[gi] = (mode & 2) ? c->list1[r1]->poc : POC_NONE;
        }
    uint8_t *fy = c->Y + (size_t)gy * 4 * c->ls + (size_t)gx * 4;
    uint8_t *fu = c->U + (size_t)gy * 2 * c->cs + (size_t)gx * 2;
    uint8_t *fv = c->V + (size_t)gy * 2 * c->cs + (size_t)gx * 2;
    if (mode == 1 || mode == 3) {
        mc_one(c, c->list0[r0], gx, gy, w4, h4, m0x, m0y,
               fy, c->ls, fu, fv, c->cs);
    } else {
        mc_one(c, c->list1[r1], gx, gy, w4, h4, m1x, m1y,
               fy, c->ls, fu, fv, c->cs);
    }
    if (mode == 3) {
        uint8_t ty[256], tu[64], tv[64];
        mc_one(c, c->list1[r1], gx, gy, w4, h4, m1x, m1y,
               ty, 16, tu, tv, 8);
        if (c->imp_wp) {
            int w0 = c->wimp[r0][r1], w1 = 64 - w0;
            wavg_block(fy, c->ls, ty, 16, w4 * 4, h4 * 4, w0, w1);
            wavg_block(fu, c->cs, tu, 8, w4 * 2, h4 * 2, w0, w1);
            wavg_block(fv, c->cs, tv, 8, w4 * 2, h4 * 2, w0, w1);
        } else {
            avg_block(fy, c->ls, ty, 16, w4 * 4, h4 * 4);
            avg_block(fu, c->cs, tu, 8, w4 * 2, h4 * 2);
            avg_block(fv, c->cs, tv, 8, w4 * 2, h4 * 2);
        }
    }
}

/* P-path wrapper: list0 only, with explicit weighting. */
static void inter_pred_part(ictx_t *c, int ref, int gx, int gy,
                            int w4, int h4, int16_t mvx, int16_t mvy) {
    inter_pred_lx(c, 1, ref, 0, gx, gy, w4, h4, mvx, mvy, 0, 0);
    const slice_hdr_t *sh = c->wp_sh;
    if (sh && sh->wp) {
        int lx = gx * 4, ly = gy * 4, cx = gx * 2, cy = gy * 2;
        wp_apply(c->Y + (size_t)ly * c->ls + (size_t)lx, c->ls,
                 w4 * 4, h4 * 4, sh->lw[ref], sh->lo[ref],
                 sh->luma_log2_denom);
        wp_apply(c->U + (size_t)cy * c->cs + (size_t)cx, c->cs,
                 w4 * 2, h4 * 2, sh->cw[ref][0], sh->co[ref][0],
                 sh->chroma_log2_denom);
        wp_apply(c->V + (size_t)cy * c->cs + (size_t)cx, c->cs,
                 w4 * 2, h4 * 2, sh->cw[ref][1], sh->co[ref][1],
                 sh->chroma_log2_denom);
    }
}

static void store_mvd(ictx_t *c, int list, int gx, int gy, int w4, int h4,
                      int adx, int ady);

/* B spatial direct (8.4.1.2.2, direct_8x8_inference=1): one ref/mv pair
 * per list from 16x16 neighbors, per-8x8 colZero from the colocated
 * corner block of list1[0]. Marks blocks direct with zero mvd. */
static void b_spatial_direct(ictx_t *c, int sid, uint32_t mbx, uint32_t mby,
                             int gx, int gy, int w4, int h4) {
    (void)mbx; (void)mby;
    int gx0 = (gx >> 2) << 2, gy0 = (gy >> 2) << 2;   /* MB origin */
    int r0 = -1, r1 = -1;
    for (int list = 0; list < 2; list++) {
        int rmin = -1;
        int16_t nx, ny;
        int nr;
        mv_nbr(c, list, sid, gx0 - 1, gy0, &nx, &ny, &nr);
        if (nr >= 0) rmin = nr;
        mv_nbr(c, list, sid, gx0, gy0 - 1, &nx, &ny, &nr);
        if (nr >= 0 && (rmin < 0 || nr < rmin)) rmin = nr;
        if (!mv_nbr(c, list, sid, gx0 + 4, gy0 - 1, &nx, &ny, &nr)) {
            mv_nbr(c, list, sid, gx0 - 1, gy0 - 1, &nx, &ny, &nr);
        }
        if (nr >= 0 && (rmin < 0 || nr < rmin)) rmin = nr;
        if (list == 0) r0 = rmin; else r1 = rmin;
    }
    int direct_zero = (r0 < 0 && r1 < 0);
    int16_t m0x = 0, m0y = 0, m1x = 0, m1y = 0;
    int mode;
    if (direct_zero) {
        r0 = 0; r1 = 0;
        mode = 3;
    } else {
        if (r0 >= 0) mv_pred(c, 0, sid, gx0, gy0, 4, 0, r0, &m0x, &m0y);
        if (r1 >= 0) mv_pred(c, 1, sid, gx0, gy0, 4, 0, r1, &m1x, &m1y);
        mode = (r0 >= 0 ? 1 : 0) | (r1 >= 0 ? 2 : 0);
    }
    const dpb_ent_t *col = c->list1[0];
    uint32_t bw = c->mb_w * 4;
    /* Cover the requested area in 8x8 quanta (16x16 direct: 4 of them;
     * B_Direct_8x8: exactly one). */
    for (int by = gy; by < gy + h4; by += 2)
    for (int bx2 = gx; bx2 < gx + w4; bx2 += 2) {
        int ccx = gx0 + (((bx2 - gx0) >> 1) ? 3 : 0);
        int ccy = gy0 + (((by - gy0) >> 1) ? 3 : 0);
        uint32_t ci = (uint32_t)ccy * bw + (uint32_t)ccx;
        int16_t cmx, cmy;
        int cref;
        if (col->ref[ci] >= 0) {
            cref = col->ref[ci]; cmx = col->mvx[ci]; cmy = col->mvy[ci];
        } else {                       /* L0 invalid: use colocated L1 */
            cref = col->ref1 ? col->ref1[ci] : -1;
            cmx = col->mv1x ? col->mv1x[ci] : 0;
            cmy = col->mv1y ? col->mv1y[ci] : 0;
        }
        int colzero = cref == 0 &&
                      cmx >= -1 && cmx <= 1 && cmy >= -1 && cmy <= 1;
        int16_t b0x = m0x, b0y = m0y, b1x = m1x, b1y = m1y;
        if (!direct_zero && colzero) {
            if (r0 == 0) { b0x = 0; b0y = 0; }
            if (r1 == 0) { b1x = 0; b1y = 0; }
        }
        inter_pred_lx(c, mode, r0 < 0 ? 0 : r0, r1 < 0 ? 0 : r1,
                      bx2, by, 2, 2, b0x, b0y, b1x, b1y);
        for (int j = 0; j < 2; j++)
            for (int i = 0; i < 2; i++)
                c->blk_direct[(uint32_t)(by + j) * bw +
                              (uint32_t)(bx2 + i)] = 1;
        store_mvd(c, 0, bx2, by, 2, 2, 0, 0);
        store_mvd(c, 1, bx2, by, 2, 2, 0, 0);
    }
}

/* B temporal direct (8.4.1.2.3, direct_8x8_inference=1): colocated
 * motion scaled by POC distance; refIdxL0 maps the colocated reference
 * picture into the current list0, refIdxL1 = 0. */
static void b_temporal_direct(ictx_t *c, int32_t cur_poc,
                              int gx, int gy, int w4, int h4) {
    const dpb_ent_t *col = c->list1[0];
    uint32_t bw = c->mb_w * 4;
    int gx0 = (gx >> 2) << 2, gy0 = (gy >> 2) << 2;
    for (int by = gy; by < gy + h4; by += 2)
    for (int bx2 = gx; bx2 < gx + w4; bx2 += 2) {
        int ccx = gx0 + (((bx2 - gx0) >> 1) ? 3 : 0);
        int ccy = gy0 + (((by - gy0) >> 1) ? 3 : 0);
        uint32_t ci = (uint32_t)ccy * bw + (uint32_t)ccx;
        int16_t cmx, cmy;
        int cref;
        if (col->ref[ci] >= 0) {
            cref = col->ref[ci]; cmx = col->mvx[ci]; cmy = col->mvy[ci];
        } else {
            cref = col->ref1 ? col->ref1[ci] : -1;
            cmx = col->mv1x ? col->mv1x[ci] : 0;
            cmy = col->mv1y ? col->mv1y[ci] : 0;
        }
        int r0 = 0;
        int16_t m0x = 0, m0y = 0, m1x = 0, m1y = 0;
        if (cref >= 0) {
            int32_t col_ref_poc = (cref < col->n_ref2poc)
                                      ? col->ref2poc[cref] : POC_NONE;
            for (int i = 0; i < c->n_refs; i++) {
                if (c->list0[i]->poc == col_ref_poc) { r0 = i; break; }
            }
            int32_t poc0 = c->list0[r0]->poc;
            int32_t poc1 = col->poc;
            if (poc0 == poc1) {
                m0x = cmx; m0y = cmy;          /* same distance: copy */
            } else {
                int td = poc1 - poc0;
                if (td > 127) td = 127;
                if (td < -128) td = -128;
                int tb = (int)(cur_poc - poc0);
                if (tb > 127) tb = 127;
                if (tb < -128) tb = -128;
                int ad = td < 0 ? -td : td;
                int tx = (16384 + (ad >> 1)) / td;
                int dsf = (tb * tx + 32) >> 6;
                if (dsf > 1023) dsf = 1023;
                if (dsf < -1024) dsf = -1024;
                m0x = (int16_t)((dsf * cmx + 128) >> 8);
                m0y = (int16_t)((dsf * cmy + 128) >> 8);
                m1x = (int16_t)(m0x - cmx);
                m1y = (int16_t)(m0y - cmy);
            }
        }
        inter_pred_lx(c, 3, r0, 0, bx2, by, 2, 2, m0x, m0y, m1x, m1y);
        for (int j = 0; j < 2; j++)
            for (int i = 0; i < 2; i++)
                c->blk_direct[(uint32_t)(by + j) * bw +
                              (uint32_t)(bx2 + i)] = 1;
        store_mvd(c, 0, bx2, by, 2, 2, 0, 0);
        store_mvd(c, 1, bx2, by, 2, 2, 0, 0);
    }
}

/* P_Skip (8.4.1.1): 16x16 prediction with the zero-forcing conditions. */
static void p_skip_mv(const ictx_t *c, int sid, uint32_t mbx, uint32_t mby,
                      int16_t *mx, int16_t *my) {
    int gx = (int)(mbx * 4), gy = (int)(mby * 4);
    int16_t ax, ay, bx, by;
    int ar, br;
    int has_a = mv_nbr(c, 0, sid, gx - 1, gy, &ax, &ay, &ar);
    int has_b = mv_nbr(c, 0, sid, gx, gy - 1, &bx, &by, &br);
    if (!has_a || !has_b ||
        (ar == 0 && ax == 0 && ay == 0) ||
        (br == 0 && bx == 0 && by == 0)) {
        *mx = 0;
        *my = 0;
        return;
    }
    mv_pred(c, 0, sid, gx, gy, 4, 0, 0, mx, my);
}

/* ref_idx_l0 (9.3.3.1.1.6 / te(v)). CABAC: bin0 at ctx 54 + condA +
 * 2*condB (cond = neighbor ref > 0), unary continuation at 58 then 59. */
static int read_ref_idx(bs_t *bs, cabac_t *cb, int use_cabac,
                        const ictx_t *c, int list, int sid, int gx, int gy,
                        int num_ref, uint32_t *err) {
    if (num_ref <= 1) return 0;
    if (!use_cabac) {
        uint32_t v = (num_ref == 2) ? (uint32_t)!bs_u1(bs) : bs_ue(bs);
        if (bs->error) { *err = H264_ERR_TRUNC; return -1; }
        if (v >= (uint32_t)num_ref) { *err = H264_ERR_BAD_STREAM; return -1; }
        return (int)v;
    }
    uint32_t bw = c->mb_w * 4;
    const int8_t *refs = (list == 0) ? c->mb_ref : c->mb_ref1;
    int inc = 0;
    if (blk4_avail(c, sid, gx - 1, gy) &&
        refs[(uint32_t)gy * bw + (uint32_t)(gx - 1)] > 0 &&
        !c->blk_direct[(uint32_t)gy * bw + (uint32_t)(gx - 1)]) inc += 1;
    if (blk4_avail(c, sid, gx, gy - 1) &&
        refs[(uint32_t)(gy - 1) * bw + (uint32_t)gx] > 0 &&
        !c->blk_direct[(uint32_t)(gy - 1) * bw + (uint32_t)gx]) inc += 2;
    /* Pure unary (not truncated): bins continue until a 0, whatever
     * num_ref says — ctx walks inc -> 58 -> 59 (ffmpeg (ctx>>2)+4). */
    int v = 0;
    int cw = inc;
    while (cabac_decision(cb, 54 + cw)) {
        v++;
        cw = (cw >> 2) + 4;
        if (v >= 32) { *err = H264_ERR_BAD_STREAM; return -1; }
    }
    if (cb->error) { *err = H264_ERR_TRUNC; return -1; }
    if (v >= num_ref) { *err = H264_ERR_BAD_STREAM; return -1; }
    return v;
}

/* Read one mvd pair, either entropy. gx/gy locate the partition origin
 * for the CABAC neighbor ctxInc (|mvd| sums from A/B blocks); the
 * decoded clipped magnitudes are stored over the partition area by the
 * caller via store_mvd(). */
static int read_mvd_pair(bs_t *bs, cabac_t *cb, int use_cabac,
                         const ictx_t *c, int list, int sid, int gx, int gy,
                         int16_t *dx, int16_t *dy, int *adx, int *ady,
                         uint32_t *err) {
    if (!use_cabac) {
        *dx = (int16_t)bs_se(bs);
        *dy = (int16_t)bs_se(bs);
        if (bs->error) { *err = H264_ERR_TRUNC; return -1; }
        *adx = 0;
        *ady = 0;
        return 0;
    }
    uint32_t bw = c->mb_w * 4;
    const uint8_t *max_ = (list == 0) ? c->mvd_ax : c->mvd1_ax;
    const uint8_t *may_ = (list == 0) ? c->mvd_ay : c->mvd1_ay;
    int ax = 0, ay = 0, bx2 = 0, by2 = 0;
    if (blk4_avail(c, sid, gx - 1, gy) &&
        c->mb_ref[(uint32_t)gy * bw + (uint32_t)(gx - 1)] != -2) {
        ax = max_[(uint32_t)gy * bw + (uint32_t)(gx - 1)];
        ay = may_[(uint32_t)gy * bw + (uint32_t)(gx - 1)];
    }
    if (blk4_avail(c, sid, gx, gy - 1) &&
        c->mb_ref[(uint32_t)(gy - 1) * bw + (uint32_t)gx] != -2) {
        bx2 = max_[(uint32_t)(gy - 1) * bw + (uint32_t)gx];
        by2 = may_[(uint32_t)(gy - 1) * bw + (uint32_t)gx];
    }
    int r1 = cabac_mvd(cb, 40, ax + bx2, dx, err);
    if (r1 < 0) return -1;
    int r2 = cabac_mvd(cb, 47, ay + by2, dy, err);
    if (r2 < 0) return -1;
    *adx = r1;
    *ady = r2;
    return 0;
}

static void store_mvd(ictx_t *c, int list, int gx, int gy, int w4, int h4,
                      int adx, int ady) {
    uint32_t bw = c->mb_w * 4;
    uint8_t *max_ = (list == 0) ? c->mvd_ax : c->mvd1_ax;
    uint8_t *may_ = (list == 0) ? c->mvd_ay : c->mvd1_ay;
    for (int j = 0; j < h4; j++)
        for (int i = 0; i < w4; i++) {
            uint32_t gi = (uint32_t)(gy + j) * bw + (uint32_t)(gx + i);
            max_[gi] = (uint8_t)adx;
            may_[gi] = (uint8_t)ady;
        }
}

/* One frame's worth of slices: RBSP ownership + resume position. */
typedef struct {
    uint8_t *rbsp;
    size_t size;
    size_t byte;               /* slice_data start (CAVLC: bit too) */
    int bit;
    int is_idr;
    int is_ref;                /* nal_ref_idc != 0 */
    slice_hdr_t sh;
} slice_ent_t;

static int decode_picture(slice_ent_t *ents, int nslices,
                          const sps_t *sps, const pps_t *pps,
                          const dpb_ent_t *dpb, int ndpb, int32_t poc,
                          dpb_ent_t *keep, h264_decoded_t *out) {
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
    c.mb_t8 = (uint8_t *)calloc(nmbs, 1);
    c.mb_slice = (uint16_t *)malloc(nmbs * sizeof(uint16_t));
    c.mb_dbf_idc = (int8_t *)calloc(nmbs, 1);
    c.mb_dbf_a = (int8_t *)calloc(nmbs, 1);
    c.mb_dbf_b = (int8_t *)calloc(nmbs, 1);
    c.mv_x = (int16_t *)calloc((size_t)bw * bh, sizeof(int16_t));
    c.mv_y = (int16_t *)calloc((size_t)bw * bh, sizeof(int16_t));
    c.mb_ref = (int8_t *)malloc((size_t)bw * bh);
    c.mb_skip = (uint8_t *)calloc(nmbs, 1);
    c.mb_bdirect = (uint8_t *)calloc(nmbs, 1);
    c.mvd_ax = (uint8_t *)calloc((size_t)bw * bh, 1);
    c.mvd_ay = (uint8_t *)calloc((size_t)bw * bh, 1);
    c.mv1_x = (int16_t *)calloc((size_t)bw * bh, sizeof(int16_t));
    c.mv1_y = (int16_t *)calloc((size_t)bw * bh, sizeof(int16_t));
    c.mb_ref1 = (int8_t *)malloc((size_t)bw * bh);
    c.blk_direct = (uint8_t *)calloc((size_t)bw * bh, 1);
    c.ref_poc0 = (int32_t *)malloc((size_t)bw * bh * sizeof(int32_t));
    c.ref_poc1 = (int32_t *)malloc((size_t)bw * bh * sizeof(int32_t));
    c.mvd1_ax = (uint8_t *)calloc((size_t)bw * bh, 1);
    c.mvd1_ay = (uint8_t *)calloc((size_t)bw * bh, 1);
    /* Reference list initialization. P list0: most recent first — the
     * DPB order. B list0: POC < cur descending, then POC > cur
     * ascending; list1 mirrored (8.2.4.2). */
    c.n_refs = ndpb;
    c.n_l1 = 0;
    {
        int isb = (nslices > 0 && ents[0].sh.is_b);
        if (!isb) {
            for (int i = 0; i < ndpb && i < 8; i++) c.list0[i] = &dpb[i];
        } else {
            /* True POC sorts: decode order is NOT POC-monotonic once
             * B-pyramid reference B frames enter the DPB. */
            const dpb_ent_t *past[8], *fut[8];
            int npast = 0, nfut = 0;
            for (int i = 0; i < ndpb; i++) {
                if (dpb[i].poc < poc && npast < 8) past[npast++] = &dpb[i];
                else if (dpb[i].poc > poc && nfut < 8) fut[nfut++] = &dpb[i];
            }
            for (int i = 1; i < npast; i++) {      /* poc descending */
                const dpb_ent_t *e = past[i];
                int j = i;
                while (j > 0 && past[j - 1]->poc < e->poc) {
                    past[j] = past[j - 1];
                    j--;
                }
                past[j] = e;
            }
            for (int i = 1; i < nfut; i++) {       /* poc ascending */
                const dpb_ent_t *e = fut[i];
                int j = i;
                while (j > 0 && fut[j - 1]->poc > e->poc) {
                    fut[j] = fut[j - 1];
                    j--;
                }
                fut[j] = e;
            }
            int n0 = 0, n1 = 0;
            for (int i = 0; i < npast && n0 < 8; i++) c.list0[n0++] = past[i];
            for (int i = 0; i < nfut && n0 < 8; i++) c.list0[n0++] = fut[i];
            for (int i = 0; i < nfut && n1 < 8; i++) c.list1[n1++] = fut[i];
            for (int i = 0; i < npast && n1 < 8; i++) c.list1[n1++] = past[i];
            c.n_refs = n0;
            c.n_l1 = n1;
        }
    }
    int ok = c.mv_x && c.mv_y && c.mb_ref && c.mb_skip && c.mb_bdirect &&
             c.mvd_ax &&
             c.mvd_ay && c.mv1_x && c.mv1_y && c.mb_ref1 && c.blk_direct &&
             c.ref_poc0 && c.ref_poc1 && c.mvd1_ax && c.mvd1_ay &&
             c.Y && c.U && c.V && c.i4_mode && c.nzL && c.nzC[0] &&
             c.nzC[1] && c.mb_qp && c.mb_cat && c.mb_cmode && c.mb_cbp &&
             c.cbf_l && c.cbf_ldc && c.cbf_c[0] && c.cbf_c[1] &&
             c.cbf_cdc[0] && c.cbf_cdc[1] && c.mb_t8 && c.mb_slice &&
             c.mb_dbf_idc && c.mb_dbf_a && c.mb_dbf_b;
    if (ok) {
        memset(c.mb_slice, 0xFF, nmbs * sizeof(uint16_t));
        memset(c.mb_ref, 0xFF, (size_t)bw * bh);   /* -1 = intra/none */
        memset(c.mb_ref1, 0xFF, (size_t)bw * bh);
        for (uint32_t i = 0; i < (size_t)bw * bh; i++) {
            c.ref_poc0[i] = POC_NONE;
            c.ref_poc1[i] = POC_NONE;
        }
    }
    if (!ok) {
        out->err = H264_ERR_INTERNAL;
        goto fail;
    }

    {
    const uint8_t (*aw4)[16] = pps->scaling_present ? pps->w4 : sps->w4;
    const uint8_t (*aw8)[64] = pps->scaling_present ? pps->w8 : sps->w8;
    int dbg = trace_level();
    int use_cabac = pps->entropy_coding_mode;
    uint32_t total_mbs = c.mb_w * c.mb_h;
    uint32_t mbs_done = 0;
    /* ref_pic_list_modification l0 (8.2.4.3.1): each command pulls the
     * picture with the computed picNum to the front of the remaining
     * list (duplicates allowed — x264 --weightp 2 relies on this). */
    if (nslices > 0 && ents[0].sh.n_mod_l0 > 0) {
        const slice_hdr_t *msh = &ents[0].sh;
        uint32_t max_fn = 1u << sps->log2_max_frame_num;
        int32_t pred = (int32_t)msh->frame_num;
        int idx = 0;
        for (int m = 0; m < msh->n_mod_l0 && idx < 8; m++) {
            int32_t pn = pred;
            if (msh->mod_idc[m] == 0) {
                pn -= (int32_t)msh->mod_val[m];
                if (pn < 0) pn += (int32_t)max_fn;
            } else {
                pn += (int32_t)msh->mod_val[m];
                if (pn >= (int32_t)max_fn) pn -= (int32_t)max_fn;
            }
            pred = pn;
            const dpb_ent_t *pic = NULL;
            for (int i = 0; i < ndpb; i++) {
                if ((int32_t)dpb[i].frame_num == pn) { pic = &dpb[i]; break; }
            }
            if (!pic) { out->err = H264_ERR_BAD_STREAM; goto fail; }
            for (int i = (c.n_refs < 8 ? c.n_refs : 7); i > idx; i--)
                c.list0[i] = c.list0[i - 1];
            c.list0[idx] = pic;
            idx++;
            if (c.n_refs < 8 && idx > c.n_refs) c.n_refs = idx;
        }
    }

    for (int s = 0; s < nslices; s++) {
        if (ents[s].sh.is_p && c.n_refs < 1) {
            out->err = H264_ERR_BAD_STREAM;   /* P needs a reference */
            goto fail;
        }
        if (ents[s].sh.is_b) {
            if (c.n_refs < 1 || c.n_l1 < 1) {
                out->err = H264_ERR_BAD_STREAM;
                goto fail;
            }
        }
    }
    /* The declared active counts may exceed the frames actually present
     * (x264's first GOP); pad with the last entry so ref_idx values up
     * to the declared count stay addressable. */
    if (nslices > 0 && (ents[0].sh.is_p || ents[0].sh.is_b) && c.n_refs > 0) {
        uint32_t want = ents[0].sh.num_ref_l0;
        while ((uint32_t)c.n_refs < want && c.n_refs < 8) {
            c.list0[c.n_refs] = c.list0[c.n_refs - 1];
            c.n_refs++;
        }
    }
    if (nslices > 0 && ents[0].sh.is_b && c.n_l1 > 0) {
        uint32_t want = ents[0].sh.num_ref_l1;
        while ((uint32_t)c.n_l1 < want && c.n_l1 < 8) {
            c.list1[c.n_l1] = c.list1[c.n_l1 - 1];
            c.n_l1++;
        }
    }

    for (int sid = 0; sid < nslices; sid++) {
    const slice_hdr_t *sh = &ents[sid].sh;
    bs_t bsv;
    bs_t *bs = &bsv;
    bs_init(bs, ents[sid].rbsp, ents[sid].size);
    bs->byte = ents[sid].byte;
    bs->bit = ents[sid].bit;

    int qp = (int)sh->slice_qp;
    c.wp_sh = sh;
    c.imp_wp = 0;
    if (sh->is_b && pps->weighted_bipred == 2) {
        /* short-circuit: single refs symmetric around cur_poc -> average */
        if (!(sh->num_ref_l0 == 1 && sh->num_ref_l1 == 1 &&
              c.list0[0]->poc + c.list1[0]->poc == 2 * poc)) {
            c.imp_wp = 1;
            for (uint32_t i0 = 0; i0 < sh->num_ref_l0 && i0 < 8; i0++) {
                int32_t poc0 = c.list0[i0]->poc;
                for (uint32_t i1 = 0; i1 < sh->num_ref_l1 && i1 < 8; i1++) {
                    int w = 32;
                    int32_t poc1 = c.list1[i1]->poc;
                    int td = clip3(-128, 127, (int)(poc1 - poc0));
                    if (td != 0) {
                        int tb = clip3(-128, 127, (int)(poc - poc0));
                        int ad = td < 0 ? -td : td;
                        int tx = (16384 + (ad >> 1)) / td;
                        int dsf = (tb * tx + 32) >> 8;
                        if (dsf >= -64 && dsf <= 128) w = 64 - dsf;
                    }
                    c.wimp[i0][i1] = (uint8_t)w;
                }
            }
        }
    }
    int last_qpd_nz = 0;
    int skip_run = -1;
    cabac_t cbx;
    memset(&cbx, 0, sizeof(cbx));
    if (use_cabac) {
        bs_byte_align(bs);             /* cabac_alignment_one_bit(s) */
        cabac_init(&cbx, bs->data, bs->size, bs->byte, qp,
                   (sh->is_p || sh->is_b) ? sh->cabac_init_idc : -1);
    }

    uint32_t addr = sh->first_mb;
    if (addr != mbs_done) {            /* contiguous coverage, no ASO */
        out->err = H264_ERR_UNSUP;
        goto fail;
    }
    for (;;) {
        if (addr >= total_mbs) { out->err = H264_ERR_BAD_STREAM; goto fail; }
        uint32_t mbx = addr % c.mb_w;
        uint32_t mby = addr / c.mb_w;
        /* Mark ownership first: intra-MB neighbor queries during parsing
         * (mode prediction, nC, cbf) must see this MB as in-slice. */
        c.mb_slice[mby * c.mb_w + mbx] = (uint16_t)sid;
        /* Undecided motion state for this MB (mv_pred C-neighbor rule). */
        for (int k = 0; k < 16; k++) {
            uint32_t gi = (mby * 4 + zscan_y[k]) * bw + mbx * 4 + zscan_x[k];
            c.mb_ref[gi] = -2;
        }

        rtl_p_rec_t prec;
        int prec_nmvd = 0;
        int prec_on = (sh->is_p && !use_cabac && !sh->is_b &&
                       sh->num_ref_l0 == 1 && !pps->transform_8x8 &&
                       rtl_dump_p_file() != NULL);
        rtl_b_rec_t brec;
        int brec_nmvd[2] = {0, 0};
        int brec_on = (sh->is_b && !use_cabac &&
                       sh->num_ref_l0 == 1 && sh->num_ref_l1 == 1 &&
                       !pps->weighted_pred && !pps->weighted_bipred &&
                       !pps->transform_8x8 && rtl_dump_b_file() != NULL);
        if (brec_on) {
            memset(&brec, 0, sizeof(brec));
            brec.mbx = (uint8_t)mbx;
            brec.mby = (uint8_t)mby;
            brec.dsp = (uint8_t)sh->direct_spatial;
        }
#define BREC_MVD(lst, vx, vy) do { \
            if (brec_on && brec_nmvd[lst] < 16) { \
                brec.mvd[lst][brec_nmvd[lst]][0] = (vx); \
                brec.mvd[lst][brec_nmvd[lst]][1] = (vy); \
                brec_nmvd[lst]++; \
            } } while (0)
        if (prec_on) {
            if (c.list0[0])
                rtl_dump_ref_once(c.mb_w, c.mb_h, c.list0[0]->Y,
                                  c.list0[0]->U, c.list0[0]->V);
            memset(&prec, 0, sizeof(prec));
            prec.mbx = (uint8_t)mbx;
            prec.mby = (uint8_t)mby;
            prec.qp = (uint8_t)qp;
        }

        int this_skip = 0;
        if ((sh->is_p || sh->is_b) && use_cabac) {
            this_skip = cabac_mb_skip(&cbx, &c, sid, sh->is_b, mbx, mby);
            if (cbx.error) { out->err = H264_ERR_TRUNC; goto fail; }
        } else if (sh->is_p || sh->is_b) {
            if (skip_run < 0) skip_run = (int)bs_ue(bs);
            if (bs->error) { out->err = H264_ERR_TRUNC; goto fail; }
            if (skip_run > 0) {
                skip_run--;
                this_skip = 1;
            } else {
                skip_run = -1;             /* a coded MB follows */
            }
        }
        if (this_skip) {
            if (dbg >= 2) fprintf(stderr, "SKIP %u,%u\n", mbx, mby);
            if (sh->is_b) {
                if (sh->direct_spatial)
                    b_spatial_direct(&c, sid, mbx, mby,
                                     (int)(mbx * 4), (int)(mby * 4), 4, 4);
                else
                    b_temporal_direct(&c, poc,
                                      (int)(mbx * 4), (int)(mby * 4), 4, 4);
                c.mb_bdirect[mby * c.mb_w + mbx] = 1;
            } else {
                int16_t smx, smy;
                p_skip_mv(&c, sid, mbx, mby, &smx, &smy);
                inter_pred_part(&c, 0, (int)(mbx * 4), (int)(mby * 4), 4, 4,
                                smx, smy);
            }
            for (int k = 0; k < 16; k++) {
                uint32_t gx2 = mbx * 4 + zscan_x[k];
                uint32_t gy2 = mby * 4 + zscan_y[k];
                c.nzL[gy2 * bw + gx2] = 0;
                c.cbf_l[gy2 * bw + gx2] = 0;
                c.i4_mode[gy2 * bw + gx2] = 2;
            }
            for (int k = 0; k < 4; k++) {
                uint32_t gx2 = mbx * 2 + (uint32_t)(k & 1);
                uint32_t gy2 = mby * 2 + (uint32_t)(k >> 1);
                c.nzC[0][gy2 * (bw / 2) + gx2] = 0;
                c.nzC[1][gy2 * (bw / 2) + gx2] = 0;
                c.cbf_c[0][gy2 * (bw / 2) + gx2] = 0;
                c.cbf_c[1][gy2 * (bw / 2) + gx2] = 0;
            }
            c.mb_qp[mby * c.mb_w + mbx] = (uint8_t)qp;
            c.mb_cat[mby * c.mb_w + mbx] = 3;
            c.mb_cbp[mby * c.mb_w + mbx] = 0;
            c.mb_cmode[mby * c.mb_w + mbx] = 0;
            c.mb_skip[mby * c.mb_w + mbx] = 1;
            last_qpd_nz = 0;
            if (prec_on) prec.skip = 1;
            if (brec_on) brec.skip = 1;
            goto mb_done;
        }
        uint32_t mb_type;
        int is_inter = 0;                  /* 1 = P inter, 2 = B inter */
        if (use_cabac) {
            if (sh->is_b) {
                mb_type = cabac_b_mb_type(&cbx, &c, sid, mbx, mby);
                if (mb_type < 23) is_inter = 2;
                else mb_type -= 23;
            } else if (sh->is_p) {
                mb_type = cabac_p_mb_type(&cbx);
                if (mb_type < 5) {
                    is_inter = 1;
                } else {
                    mb_type -= 5;
                }
            } else {
                mb_type = cabac_mb_type_I(&cbx, &c, sid, mbx, mby);
            }
            if (cbx.error) { out->err = H264_ERR_TRUNC; goto fail; }
        } else {
            mb_type = bs_ue(bs);
            if (bs->error) { out->err = H264_ERR_TRUNC; goto fail; }
            if (sh->is_b) {
                if (mb_type < 23) is_inter = 2;
                else {
                    if (brec_on) brec.mb_type = (uint8_t)mb_type;
                    mb_type -= 23;
                }
            } else if (sh->is_p) {
                if (mb_type < 5) {
                    is_inter = 1;
                } else {
                    if (prec_on) prec.mb_type = (uint8_t)mb_type;
                    mb_type -= 5;          /* intra MB inside a P slice */
                }
            }
            if (!is_inter && mb_type > 25) {
                out->err = H264_ERR_BAD_STREAM;
                goto fail;
            }
        }

        if (is_inter) {
            /* P_L0 partitions: parse sub types + mvd, predict, then CBP,
             * qp_delta and inter residuals (7.3.5.1 / 8.4). */
            int gx0 = (int)(mbx * 4), gy0 = (int)(mby * 4);
            int16_t pmx, pmy;
            int16_t dx, dy;
            int adx, ady;
            int all_sub8x8 = 1;
            int nref = (int)sh->num_ref_l0;
            if (prec_on) prec.mb_type = (uint8_t)mb_type;
            if (brec_on) brec.mb_type = (uint8_t)mb_type;
            if (is_inter == 2) {
                /* ---- B macroblock (Table 7-14) ---- */
                if (dbg >= 2) fprintf(stderr, "BMB %u,%u type=%u\n",
                                      mbx, mby, mb_type);
                int nref1 = (int)sh->num_ref_l1;
                static const uint8_t bpair[9][2] = {
                    {1,1},{2,2},{1,2},{2,1},{1,3},{2,3},{3,1},{3,2},{3,3}
                };
                if (mb_type == 0) {                /* B_Direct_16x16 */
                    if (sh->direct_spatial)
                        b_spatial_direct(&c, sid, mbx, mby, gx0, gy0, 4, 4);
                    else
                        b_temporal_direct(&c, poc, gx0, gy0, 4, 4);
                    c.mb_bdirect[mby * c.mb_w + mbx] = 1;
                } else if (mb_type <= 3) {         /* 16x16 L0/L1/Bi */
                    int mode = (int)mb_type;       /* 1,2,3 */
                    int r0 = 0, r1 = 0;
                    int16_t m0x = 0, m0y = 0, m1x = 0, m1y = 0;
                    if (mode & 1) {
                        r0 = read_ref_idx(bs, &cbx, use_cabac, &c, 0, sid,
                                          gx0, gy0, nref, &out->err);
                        if (r0 < 0) goto fail;
                    }
                    if (mode & 2) {
                        r1 = read_ref_idx(bs, &cbx, use_cabac, &c, 1, sid,
                                          gx0, gy0, nref1, &out->err);
                        if (r1 < 0) goto fail;
                    }
                    int16_t pmx2, pmy2;
                    if (mode & 1) {
                        if (read_mvd_pair(bs, &cbx, use_cabac, &c, 0, sid,
                                          gx0, gy0, &dx, &dy, &adx, &ady,
                                          &out->err)) goto fail;
                        BREC_MVD(0, dx, dy);
                        mv_pred(&c, 0, sid, gx0, gy0, 4, 0, r0, &pmx2, &pmy2);
                        m0x = (int16_t)(pmx2 + dx);
                        m0y = (int16_t)(pmy2 + dy);
                        store_mvd(&c, 0, gx0, gy0, 4, 4, adx, ady);
                    } else {
                        store_mvd(&c, 0, gx0, gy0, 4, 4, 0, 0);
                    }
                    if (mode & 2) {
                        if (read_mvd_pair(bs, &cbx, use_cabac, &c, 1, sid,
                                          gx0, gy0, &dx, &dy, &adx, &ady,
                                          &out->err)) goto fail;
                        BREC_MVD(1, dx, dy);
                        mv_pred(&c, 1, sid, gx0, gy0, 4, 0, r1, &pmx2, &pmy2);
                        m1x = (int16_t)(pmx2 + dx);
                        m1y = (int16_t)(pmy2 + dy);
                        store_mvd(&c, 1, gx0, gy0, 4, 4, adx, ady);
                    } else {
                        store_mvd(&c, 1, gx0, gy0, 4, 4, 0, 0);
                    }
                    inter_pred_lx(&c, mode, r0, r1, gx0, gy0, 4, 4,
                                  m0x, m0y, m1x, m1y);
                } else if (mb_type <= 21) {        /* two partitions */
                    int pair = (int)(mb_type - 4) >> 1;
                    int is8x16 = (int)(mb_type - 4) & 1;
                    int w4 = is8x16 ? 2 : 4, h4 = is8x16 ? 4 : 2;
                    int rr[2][2] = {{0, 0}, {0, 0}};
                    /* refs: l0 both parts, then l1 both parts (7.3.5.1) */
                    for (int list = 0; list < 2; list++) {
                        for (int part = 0; part < 2; part++) {
                            int mode = bpair[pair][part];
                            if (!(mode & (1 << list))) continue;
                            int px = is8x16 ? gx0 + part * 2 : gx0;
                            int py = is8x16 ? gy0 : gy0 + part * 2;
                            int rv = read_ref_idx(bs, &cbx, use_cabac, &c,
                                                  list, sid, px, py,
                                                  list ? nref1 : nref,
                                                  &out->err);
                            if (rv < 0) goto fail;
                            rr[list][part] = rv;
                            /* the second partition's ref_idx ctxInc must
                             * see this one */
                            for (int j = 0; j < h4; j++)
                                for (int i = 0; i < w4; i++) {
                                    uint32_t gi =
                                        (uint32_t)(py + j) * bw +
                                        (uint32_t)(px + i);
                                    if (list == 0)
                                        c.mb_ref[gi] = (int8_t)rv;
                                    else
                                        c.mb_ref1[gi] = (int8_t)rv;
                                }
                        }
                    }
                    /* mvds in the same list-major order; remember both
                     * partitions' mvs, predict as we go per list. */
                    int16_t mv[2][2][2];
                    memset(mv, 0, sizeof(mv));
                    for (int list = 0; list < 2; list++) {
                        for (int part = 0; part < 2; part++) {
                            int mode = bpair[pair][part];
                            int px = is8x16 ? gx0 + part * 2 : gx0;
                            int py = is8x16 ? gy0 : gy0 + part * 2;
                            if (!(mode & (1 << list))) {
                                store_mvd(&c, list, px, py, w4, h4, 0, 0);
                                if (list == 0) {
                                    /* settle the undecoded sentinel: this
                                     * partition has no L0 prediction but IS
                                     * decoded — the second partition's L1
                                     * prediction must see it */
                                    for (int j = 0; j < h4; j++)
                                        for (int i = 0; i < w4; i++) {
                                            uint32_t gi =
                                                (uint32_t)(py + j) * bw +
                                                (uint32_t)(px + i);
                                            c.mb_ref[gi] = -1;
                                            c.mv_x[gi] = 0;
                                            c.mv_y[gi] = 0;
                                        }
                                }
                                continue;
                            }
                            if (read_mvd_pair(bs, &cbx, use_cabac, &c, list,
                                              sid, px, py, &dx, &dy,
                                              &adx, &ady, &out->err))
                                goto fail;
                            int16_t pmx2, pmy2;
                            BREC_MVD(list, dx, dy);
                            mv_pred(&c, list, sid, px, py, w4,
                                    (is8x16 ? 3 : 1) + part, rr[list][part],
                                    &pmx2, &pmy2);
                            mv[list][part][0] = (int16_t)(pmx2 + dx);
                            mv[list][part][1] = (int16_t)(pmy2 + dy);
                            store_mvd(&c, list, px, py, w4, h4, adx, ady);
                            /* partial motion write so the second
                             * partition's prediction sees this one */
                            for (int j = 0; j < h4; j++)
                                for (int i = 0; i < w4; i++) {
                                    uint32_t gi =
                                        (uint32_t)(py + j) * bw +
                                        (uint32_t)(px + i);
                                    if (list == 0) {
                                        c.mv_x[gi] = mv[0][part][0];
                                        c.mv_y[gi] = mv[0][part][1];
                                        c.mb_ref[gi] = (int8_t)rr[0][part];
                                    } else {
                                        c.mv1_x[gi] = mv[1][part][0];
                                        c.mv1_y[gi] = mv[1][part][1];
                                        c.mb_ref1[gi] = (int8_t)rr[1][part];
                                    }
                                }
                        }
                    }
                    for (int part = 0; part < 2; part++) {
                        int mode = bpair[pair][part];
                        int px = is8x16 ? gx0 + part * 2 : gx0;
                        int py = is8x16 ? gy0 : gy0 + part * 2;
                        inter_pred_lx(&c, mode, rr[0][part], rr[1][part],
                                      px, py, w4, h4,
                                      mv[0][part][0], mv[0][part][1],
                                      mv[1][part][0], mv[1][part][1]);
                    }
                } else {                           /* B_8x8 */
                    static const struct { uint8_t mode, w4, h4, nsub; }
                    bsub[13] = {
                        {0, 2, 2, 1}, {1, 2, 2, 1}, {2, 2, 2, 1},
                        {3, 2, 2, 1}, {1, 2, 1, 2}, {1, 1, 2, 2},
                        {2, 2, 1, 2}, {2, 1, 2, 2}, {3, 2, 1, 2},
                        {3, 1, 2, 2}, {1, 1, 1, 4}, {2, 1, 1, 4},
                        {3, 1, 1, 4}
                    };
                    uint32_t sub[4];
                    int r8b[2][4] = {{0}, {0}};
                    for (int b = 0; b < 4; b++) {
                        sub[b] = use_cabac ? cabac_b_sub_type(&cbx)
                                           : bs_ue(bs);
                        if (brec_on) brec.sub[b] = (uint8_t)sub[b];
                        if (sub[b] > 12) {
                            out->err = H264_ERR_BAD_STREAM;
                goto fail;
                        }
                        if (sub[b] >= 4) all_sub8x8 = 0;
                    }
                    for (int list = 0; list < 2; list++) {
                        for (int b = 0; b < 4; b++) {
                            if (sub[b] == 0) continue;
                            if (!(bsub[sub[b]].mode & (1 << list))) continue;
                            int bx0 = gx0 + (b & 1) * 2;
                            int by0 = gy0 + (b >> 1) * 2;
                            int rv = read_ref_idx(bs, &cbx, use_cabac, &c,
                                                  list, sid, bx0, by0,
                                                  list ? nref1 : nref,
                                                  &out->err);
                            if (rv < 0) goto fail;
                            r8b[list][b] = rv;
                            for (int j = 0; j < 2; j++)
                                for (int i = 0; i < 2; i++) {
                                    uint32_t gi =
                                        (uint32_t)(by0 + j) * bw +
                                        (uint32_t)(bx0 + i);
                                    if (list == 0)
                                        c.mb_ref[gi] = (int8_t)rv;
                                    else
                                        c.mb_ref1[gi] = (int8_t)rv;
                                }
                        }
                    }
                    /* direct sub-blocks predict first (no syntax) */
                    for (int b = 0; b < 4; b++) {
                        if (sub[b] != 0) continue;
                        int bx0 = gx0 + (b & 1) * 2;
                        int by0 = gy0 + (b >> 1) * 2;
                        if (sh->direct_spatial)
                            b_spatial_direct(&c, sid, mbx, mby,
                                             bx0, by0, 2, 2);
                        else
                            b_temporal_direct(&c, poc, bx0, by0, 2, 2);
                    }
                    int16_t smv[2][4][4][2];       /* [list][8x8][sub] */
                    memset(smv, 0, sizeof(smv));
                    for (int list = 0; list < 2; list++) {
                        for (int b = 0; b < 4; b++) {
                            if (sub[b] == 0) continue;
                            int mode = bsub[sub[b]].mode;
                            int w4 = bsub[sub[b]].w4, h4 = bsub[sub[b]].h4;
                            int nsub = bsub[sub[b]].nsub;
                            int bx0 = gx0 + (b & 1) * 2;
                            int by0 = gy0 + (b >> 1) * 2;
                            for (int s = 0; s < nsub; s++) {
                                int sx = bx0 + ((w4 == 1) ? (s & 1) : 0);
                                int sy = by0;
                                if (h4 == 1) sy += s;
                                else if (w4 == 1 && h4 == 2) sy += 0;
                                if (w4 == 1 && h4 == 1) sy = by0 + (s >> 1);
                                if (!(mode & (1 << list))) {
                                    store_mvd(&c, list, sx, sy, w4, h4, 0, 0);
                                    if (list == 0) {
                                        for (int j = 0; j < h4; j++)
                                            for (int i = 0; i < w4; i++) {
                                                uint32_t gi =
                                                    (uint32_t)(sy + j) * bw +
                                                    (uint32_t)(sx + i);
                                                c.mb_ref[gi] = -1;
                                                c.mv_x[gi] = 0;
                                                c.mv_y[gi] = 0;
                                            }
                                    }
                                    continue;
                                }
                                if (read_mvd_pair(bs, &cbx, use_cabac, &c,
                                                  list, sid, sx, sy,
                                                  &dx, &dy, &adx, &ady,
                                                  &out->err)) goto fail;
                                int16_t pmx2, pmy2;
                                BREC_MVD(list, dx, dy);
                                mv_pred(&c, list, sid, sx, sy, w4, 0,
                                        r8b[list][b], &pmx2, &pmy2);
                                smv[list][b][s][0] = (int16_t)(pmx2 + dx);
                                smv[list][b][s][1] = (int16_t)(pmy2 + dy);
                                store_mvd(&c, list, sx, sy, w4, h4,
                                          adx, ady);
                                for (int j = 0; j < h4; j++)
                                    for (int i = 0; i < w4; i++) {
                                        uint32_t gi =
                                            (uint32_t)(sy + j) * bw +
                                            (uint32_t)(sx + i);
                                        if (list == 0) {
                                            c.mv_x[gi] = smv[0][b][s][0];
                                            c.mv_y[gi] = smv[0][b][s][1];
                                        } else {
                                            c.mv1_x[gi] = smv[1][b][s][0];
                                            c.mv1_y[gi] = smv[1][b][s][1];
                                        }
                                    }
                            }
                        }
                    }
                    for (int b = 0; b < 4; b++) {
                        if (sub[b] == 0) continue;
                        int mode = bsub[sub[b]].mode;
                        int w4 = bsub[sub[b]].w4, h4 = bsub[sub[b]].h4;
                        int nsub = bsub[sub[b]].nsub;
                        int bx0 = gx0 + (b & 1) * 2;
                        int by0 = gy0 + (b >> 1) * 2;
                        for (int s = 0; s < nsub; s++) {
                            int sx = bx0 + ((w4 == 1) ? (s & 1) : 0);
                            int sy = by0;
                            if (h4 == 1) sy += s;
                            if (w4 == 1 && h4 == 1) sy = by0 + (s >> 1);
                            inter_pred_lx(&c, mode,
                                          r8b[0][b], r8b[1][b],
                                          sx, sy, w4, h4,
                                          smv[0][b][s][0], smv[0][b][s][1],
                                          smv[1][b][s][0], smv[1][b][s][1]);
                        }
                    }
                }
            } else
            if (mb_type == 0) {                    /* 16x16 */
                int r0 = read_ref_idx(bs, &cbx, use_cabac, &c, 0, sid,
                                      gx0, gy0, nref, &out->err);
                if (r0 < 0) goto fail;
                if (read_mvd_pair(bs, &cbx, use_cabac, &c, 0, sid, gx0, gy0,
                                  &dx, &dy, &adx, &ady, &out->err)) goto fail;
                if (prec_on && prec_nmvd < 16) {
                    prec.mvd[prec_nmvd][0] = dx;
                    prec.mvd[prec_nmvd][1] = dy;
                    prec_nmvd++;
                }
                mv_pred(&c, 0, sid, gx0, gy0, 4, 0, r0, &pmx, &pmy);
                inter_pred_part(&c, r0, gx0, gy0, 4, 4,
                                (int16_t)(pmx + dx), (int16_t)(pmy + dy));
                store_mvd(&c, 0, gx0, gy0, 4, 4, adx, ady);
            } else if (mb_type == 1 || mb_type == 2) {  /* 16x8 / 8x16 */
                int r[2];
                /* refs for both partitions precede both mvds (7.3.5.1).
                 * ref_idx ctxInc uses the partition origin's neighbors;
                 * the second partition's A/B blocks are outside this MB
                 * or in the (not yet written) first partition — write
                 * each partition's ref into mb_ref before reading the
                 * next so intra-MB neighbors resolve. */
                for (int part = 0; part < 2; part++) {
                    int px = (mb_type == 1) ? gx0 : gx0 + part * 2;
                    int py = (mb_type == 1) ? gy0 + part * 2 : gy0;
                    r[part] = read_ref_idx(bs, &cbx, use_cabac, &c, 0, sid,
                                           px, py, nref, &out->err);
                    if (r[part] < 0) goto fail;
                    int w4 = (mb_type == 1) ? 4 : 2;
                    int h4 = (mb_type == 1) ? 2 : 4;
                    for (int j = 0; j < h4; j++)
                        for (int i = 0; i < w4; i++)
                            c.mb_ref[(uint32_t)(py + j) * bw +
                                     (uint32_t)(px + i)] = (int8_t)r[part];
                }
                for (int part = 0; part < 2; part++) {
                    int px = (mb_type == 1) ? gx0 : gx0 + part * 2;
                    int py = (mb_type == 1) ? gy0 + part * 2 : gy0;
                    if (read_mvd_pair(bs, &cbx, use_cabac, &c, 0, sid,
                                      px, py, &dx, &dy, &adx, &ady,
                                      &out->err))
                        goto fail;
                    if (prec_on && prec_nmvd < 16) {
                        prec.mvd[prec_nmvd][0] = dx;
                        prec.mvd[prec_nmvd][1] = dy;
                        prec_nmvd++;
                    }
                    mv_pred(&c, 0, sid, px, py, (mb_type == 1) ? 4 : 2,
                            (mb_type == 1 ? 1 : 3) + part, r[part],
                            &pmx, &pmy);
                    inter_pred_part(&c, r[part], px, py,
                                    (mb_type == 1) ? 4 : 2,
                                    (mb_type == 1) ? 2 : 4,
                                    (int16_t)(pmx + dx), (int16_t)(pmy + dy));
                    store_mvd(&c, 0, px, py, (mb_type == 1) ? 4 : 2,
                              (mb_type == 1) ? 2 : 4, adx, ady);
                }
            } else {                               /* P_8x8 / P_8x8ref0 */
                uint32_t sub[4];
                int r8[4];
                for (int b = 0; b < 4; b++) {
                    sub[b] = use_cabac ? cabac_p_sub_type(&cbx) : bs_ue(bs);
                    if (sub[b] > 3) { out->err = H264_ERR_BAD_STREAM; goto fail; }
                    if (sub[b] != 0) all_sub8x8 = 0;
                    if (prec_on) prec.sub[b] = (uint8_t)sub[b];
                }
                for (int b = 0; b < 4; b++) {
                    int bx0 = gx0 + (b & 1) * 2, by0 = gy0 + (b >> 1) * 2;
                    if (mb_type == 4) {            /* P_8x8ref0 */
                        r8[b] = 0;
                        continue;
                    }
                    r8[b] = read_ref_idx(bs, &cbx, use_cabac, &c, 0, sid,
                                         bx0, by0, nref, &out->err);
                    if (r8[b] < 0) goto fail;
                    for (int j = 0; j < 2; j++)
                        for (int i = 0; i < 2; i++)
                            c.mb_ref[(uint32_t)(by0 + j) * bw +
                                     (uint32_t)(bx0 + i)] = (int8_t)r8[b];
                }
                for (int b = 0; b < 4; b++) {
                    int bx0 = gx0 + (b & 1) * 2, by0 = gy0 + (b >> 1) * 2;
                    int nsub = (sub[b] == 0) ? 1 : (sub[b] == 3) ? 4 : 2;
                    for (int s = 0; s < nsub; s++) {
                        int sx, sy, w4, h4;
                        if (sub[b] == 0) { sx = bx0; sy = by0; w4 = 2; h4 = 2; }
                        else if (sub[b] == 1) {        /* 8x4 */
                            sx = bx0; sy = by0 + s; w4 = 2; h4 = 1;
                        } else if (sub[b] == 2) {      /* 4x8 */
                            sx = bx0 + s; sy = by0; w4 = 1; h4 = 2;
                        } else {                       /* 4x4 */
                            sx = bx0 + (s & 1); sy = by0 + (s >> 1);
                            w4 = 1; h4 = 1;
                        }
                        if (read_mvd_pair(bs, &cbx, use_cabac, &c, 0, sid,
                                          sx, sy, &dx, &dy, &adx, &ady,
                                          &out->err)) goto fail;
                        if (prec_on && prec_nmvd < 16) {
                            prec.mvd[prec_nmvd][0] = dx;
                            prec.mvd[prec_nmvd][1] = dy;
                            prec_nmvd++;
                        }
                        mv_pred(&c, 0, sid, sx, sy, w4, 0, r8[b],
                                &pmx, &pmy);
                        inter_pred_part(&c, r8[b], sx, sy, w4, h4,
                                        (int16_t)(pmx + dx),
                                        (int16_t)(pmy + dy));
                        store_mvd(&c, 0, sx, sy, w4, h4, adx, ady);
                    }
                }
            }
            if (bs->error || cbx.error) { out->err = H264_ERR_TRUNC; goto fail; }

            /* CBP + qp_delta. */
            uint32_t cbp;
            if (use_cabac) {
                cbp = cabac_cbp(&cbx, &c, sid, mbx, mby);
                if (cbx.error) { out->err = H264_ERR_TRUNC; goto fail; }
            } else {
                uint32_t code = bs_ue(bs);
                if (code >= 48 || bs->error) {
                    out->err = bs->error ? H264_ERR_TRUNC
                                         : H264_ERR_BAD_STREAM;
                    goto fail;
                }
                cbp = golomb_to_inter_cbp[code];
            }
            uint32_t cbp_luma = cbp & 15, cbp_chroma = cbp >> 4;
            if (cbp_chroma > 2) { out->err = H264_ERR_BAD_STREAM; goto fail; }
            int t8i = 0;
            {
                int parts_ok = (mb_type <= 2) || all_sub8x8;
                if (pps->transform_8x8 && cbp_luma != 0 && parts_ok) {
                    if (use_cabac) {
                        int inc = 0;
                        if (mb_avail(&c, sid, (int)mbx - 1, (int)mby) &&
                            c.mb_t8[mby * c.mb_w + mbx - 1]) inc++;
                        if (mb_avail(&c, sid, (int)mbx, (int)mby - 1) &&
                            c.mb_t8[(mby - 1) * c.mb_w + mbx]) inc++;
                        t8i = cabac_decision(&cbx, 399 + inc);
                    } else {
                        t8i = (int)bs_u1(bs);
                    }
                }
            }
            c.mb_t8[mby * c.mb_w + mbx] = (uint8_t)t8i;
            c.mb_cat[mby * c.mb_w + mbx] = 3;
            c.mb_cbp[mby * c.mb_w + mbx] =
                (uint8_t)((cbp_chroma << 4) | cbp_luma);
            c.mb_cmode[mby * c.mb_w + mbx] = 0;
            for (int k = 0; k < 16; k++) {
                uint32_t gx2 = mbx * 4 + zscan_x[k];
                uint32_t gy2 = mby * 4 + zscan_y[k];
                c.i4_mode[gy2 * bw + gx2] = 2;
            }
            if (cbp_luma != 0 || cbp_chroma != 0) {
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

            /* Inter residuals on the inter scaling lists. */
            int16_t scan[16];
            int16_t resid[16][16];
            int16_t iresid8[4][64];
            memset(resid, 0, sizeof(resid));
            memset(iresid8, 0, sizeof(iresid8));
            if (t8i) {
                int16_t scan64[64];
                for (int b = 0; b < 4; b++) {
                    int bx0 = (int)(mbx * 4 + (uint32_t)(b & 1) * 2);
                    int by0 = (int)(mby * 4 + (uint32_t)(b >> 1) * 2);
                    if (cbp_luma & (1u << b)) {
                        if (use_cabac) {
                            int tc = cabac_residual8x8(&cbx, scan64,
                                                       &out->err);
                            if (tc < 0) goto fail;
                            for (int k = 0; k < 64; k++)
                                iresid8[b][h264_zigzag8x8[k]] = scan64[k];
                            for (int dy2 = 0; dy2 < 2; dy2++)
                                for (int dx2 = 0; dx2 < 2; dx2++) {
                                    uint32_t gi =
                                        ((uint32_t)(by0 + dy2)) * bw +
                                        (uint32_t)(bx0 + dx2);
                                    c.nzL[gi] = (uint8_t)(tc > 16 ? 16 : tc);
                                    c.cbf_l[gi] = (tc != 0);
                                }
                        } else {
                            for (int j = 0; j < 4; j++) {
                                int gx = bx0 + (j & 1);
                                int gy = by0 + (j >> 1);
                                int nc = derive_nc(c.nzL, bw, gx, gy,
                                    blk4_avail(&c, sid, gx - 1, gy),
                                    blk4_avail(&c, sid, gx, gy - 1));
                                int tc = cavlc_residual_block(bs, nc, 16,
                                                              scan, &out->err);
                                if (tc < 0) goto fail;
                                uint32_t gi = (uint32_t)gy * bw + (uint32_t)gx;
                                c.nzL[gi] = (uint8_t)tc;
                                c.cbf_l[gi] = (tc != 0);
                                for (int k = 0; k < 16; k++)
                                    iresid8[b][h264_zigzag8x8[4 * k + j]] =
                                        scan[k];
                            }
                        }
                    } else {
                        for (int dy2 = 0; dy2 < 2; dy2++)
                            for (int dx2 = 0; dx2 < 2; dx2++) {
                                uint32_t gi = ((uint32_t)(by0 + dy2)) * bw +
                                              (uint32_t)(bx0 + dx2);
                                c.nzL[gi] = 0;
                                c.cbf_l[gi] = 0;
                            }
                    }
                }
            } else
            for (int k = 0; k < 16; k++) {
                int gx = (int)(mbx * 4 + zscan_x[k]);
                int gy = (int)(mby * 4 + zscan_y[k]);
                if (cbp_luma & (1u << (k >> 2))) {
                    int tc;
                    if (use_cabac) {
                        int ca = cbf_cond_luma4(&c, 0, sid, gx - 1, gy);
                        int cbn = cbf_cond_luma4(&c, 0, sid, gx, gy - 1);
                        tc = cabac_residual(&cbx, 2, ca, cbn, 16, scan,
                                            &out->err);
                    } else {
                        int nc = derive_nc(c.nzL, bw, gx, gy,
                                           blk4_avail(&c, sid, gx - 1, gy),
                                           blk4_avail(&c, sid, gx, gy - 1));
                        tc = cavlc_residual_block(bs, nc, 16, scan, &out->err);
                    }
                    if (tc < 0) goto fail;
                    c.nzL[(uint32_t)gy * bw + (uint32_t)gx] = (uint8_t)tc;
                    c.cbf_l[(uint32_t)gy * bw + (uint32_t)gx] = (tc != 0);
                    for (int i = 0; i < 16; i++)
                        resid[k][h264_zigzag4x4[i]] = scan[i];
                } else {
                    c.nzL[(uint32_t)gy * bw + (uint32_t)gx] = 0;
                    c.cbf_l[(uint32_t)gy * bw + (uint32_t)gx] = 0;
                }
            }
            int16_t cdc[2][4];
            memset(cdc, 0, sizeof(cdc));
            if (cbp_chroma != 0) {
                for (int comp = 0; comp < 2; comp++) {
                    int tc;
                    if (use_cabac) {
                        int ca = cbf_cond_chromadc(&c, 0, sid, comp,
                                                   mbx, mby, -1, 0);
                        int cbn = cbf_cond_chromadc(&c, 0, sid, comp,
                                                    mbx, mby, 0, -1);
                        tc = cabac_residual(&cbx, 3, ca, cbn, 4, scan,
                                            &out->err);
                        if (tc < 0) goto fail;
                        c.cbf_cdc[comp][mby * c.mb_w + mbx] = (tc != 0);
                    } else {
                        tc = cavlc_residual_block(bs, -1, 4, scan, &out->err);
                        if (tc < 0) goto fail;
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
                            int ca = cbf_cond_chroma4(&c, 0, sid, comp,
                                                      gx - 1, gy);
                            int cbn = cbf_cond_chroma4(&c, 0, sid, comp,
                                                       gx, gy - 1);
                            tc = cabac_residual(&cbx, 4, ca, cbn, 15, scan,
                                                &out->err);
                        } else {
                            int avA = gx > 0 &&
                                mb_avail(&c, sid, (gx - 1) >> 1, gy >> 1);
                            int avB = gy > 0 &&
                                mb_avail(&c, sid, gx >> 1, (gy - 1) >> 1);
                            tc = cavlc_residual_block(bs,
                                derive_nc(c.nzC[comp], bw / 2, gx, gy,
                                          avA, avB),
                                15, scan, &out->err);
                        }
                        if (tc < 0) goto fail;
                        c.nzC[comp][(uint32_t)gy * (bw / 2) + (uint32_t)gx] =
                            (uint8_t)tc;
                        c.cbf_c[comp][(uint32_t)gy * (bw / 2) + (uint32_t)gx] =
                            (tc != 0);
                        for (int i = 0; i < 15; i++)
                            cres[comp][k][h264_zigzag4x4[i + 1]] = scan[i];
                    } else {
                        c.nzC[comp][(uint32_t)gy * (bw / 2) + (uint32_t)gx] = 0;
                        c.cbf_c[comp][(uint32_t)gy * (bw / 2) + (uint32_t)gx] = 0;
                    }
                }
            }

            /* Add residuals onto the MC prediction. */
            int32_t d[16];
            uint8_t *ydst2 = c.Y + (size_t)mby * 16 * c.ls + (size_t)mbx * 16;
            if (t8i) {
                int32_t d64[64];
                for (int b = 0; b < 4; b++) {
                    if (!(cbp_luma & (1u << b))) continue;
                    h264_dequant8x8(iresid8[b], qp, aw8[1], d64);
                    h264_idct8x8_add(ydst2 + (size_t)(b >> 1) * 8 * c.ls
                                           + (size_t)(b & 1) * 8, c.ls, d64);
                }
            } else
            for (int k = 0; k < 16; k++) {
                if (!(cbp_luma & (1u << (k >> 2)))) continue;
                uint32_t x4 = zscan_x[k], y4 = zscan_y[k];
                h264_dequant4x4(resid[k], qp, aw4[3], d);
                h264_idct4x4_add(ydst2 + (size_t)y4 * 4 * c.ls + (size_t)x4 * 4,
                                 c.ls, d);
            }
            for (int comp = 0; comp < 2; comp++) {
                if (cbp_chroma == 0) break;
                int qpc = h264_chroma_qp(clip3(0, 51,
                    qp + (int)(comp ? pps->second_chroma_qp_offset
                                    : pps->chroma_qp_offset)));
                const uint8_t *wc = aw4[4 + comp];
                uint8_t *cdst2 = (comp ? c.V : c.U)
                                 + (size_t)mby * 8 * c.cs + (size_t)mbx * 8;
                int32_t cdcd[4];
                h264_chroma_dc_dequant(cdc[comp], qpc, wc[0], cdcd);
                for (int k = 0; k < 4; k++) {
                    h264_dequant4x4(cres[comp][k], qpc, wc, d);
                    d[0] = cdcd[k];
                    h264_idct4x4_add(cdst2 + (size_t)(k >> 1) * 4 * c.cs
                                           + (size_t)(k & 1) * 4, c.cs, d);
                }
            }
            goto mb_done;
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
            goto mb_done;
        }

        int intra4x4 = (mb_type == 0);
        int modes[16];
        int modes8[4] = { 2, 2, 2, 2 };
        int i16_mode = 0;
        int t8 = 0;
        uint32_t cbp_luma, cbp_chroma;

        if (intra4x4 && pps->transform_8x8) {
            if (use_cabac) {
                int inc = 0;
                if (mb_avail(&c, sid, (int)mbx - 1, (int)mby) &&
                    c.mb_t8[mby * c.mb_w + mbx - 1]) inc++;
                if (mb_avail(&c, sid, (int)mbx, (int)mby - 1) &&
                    c.mb_t8[(mby - 1) * c.mb_w + mbx]) inc++;
                t8 = cabac_decision(&cbx, 399 + inc);
            } else {
                t8 = (int)bs_u1(bs);
            }
        }

        if (intra4x4 && t8) {
            /* Four 8x8 partitions, prev/rem syntax as in 4x4; the decoded
             * mode fills the block's 2x2 patch of the 4x4 mode grid. */
            for (int b = 0; b < 4; b++) {
                int gx = (int)(mbx * 4 + (uint32_t)(b & 1) * 2);
                int gy = (int)(mby * 4 + (uint32_t)(b >> 1) * 2);
                int pA = blk4_avail(&c, sid, gx - 1, gy)
                             ? c.i4_mode[(uint32_t)gy * bw + (uint32_t)gx - 1] : -1;
                int pB = blk4_avail(&c, sid, gx, gy - 1)
                             ? c.i4_mode[((uint32_t)gy - 1) * bw + (uint32_t)gx] : -1;
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
                modes8[b] = mode;
                for (int dy = 0; dy < 2; dy++)
                    for (int dx = 0; dx < 2; dx++)
                        c.i4_mode[((uint32_t)gy + (uint32_t)dy) * bw +
                                  (uint32_t)gx + (uint32_t)dx] = (int8_t)mode;
            }
        } else if (intra4x4) {
            for (int k = 0; k < 16; k++) {
                int gx = (int)(mbx * 4 + zscan_x[k]);
                int gy = (int)(mby * 4 + zscan_y[k]);
                int pA = blk4_avail(&c, sid, gx - 1, gy)
                             ? c.i4_mode[(uint32_t)gy * bw + (uint32_t)gx - 1] : -1;
                int pB = blk4_avail(&c, sid, gx, gy - 1)
                             ? c.i4_mode[((uint32_t)gy - 1) * bw + (uint32_t)gx] : -1;
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
        }
        if (!intra4x4) {
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
            chroma_mode = cabac_chroma_mode(&cbx, &c, sid, mbx, mby);
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
                cbp = cabac_cbp(&cbx, &c, sid, mbx, mby);
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
        c.mb_t8[mby * c.mb_w + mbx] = (uint8_t)t8;
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
        int16_t dcraw[16];
        memset(luma_dc, 0, sizeof(luma_dc));
        memset(dcraw, 0, sizeof(dcraw));
        if (!intra4x4) {
            if (use_cabac) {
                int ca = cbf_cond_lumadc(&c, 1, sid, mbx, mby, -1, 0);
                int cbn = cbf_cond_lumadc(&c, 1, sid, mbx, mby, 0, -1);
                int tc = cabac_residual(&cbx, 0, ca, cbn, 16, scan, &out->err);
                if (tc < 0) goto fail;
                c.cbf_ldc[mby * c.mb_w + mbx] = (tc != 0);
            } else {
                int nc = derive_nc(c.nzL, bw, (int)(mbx * 4), (int)(mby * 4),
                                   mb_avail(&c, sid, (int)mbx - 1, (int)mby),
                                   mb_avail(&c, sid, (int)mbx, (int)mby - 1));
                if (cavlc_residual_block(bs, nc, 16, scan, &out->err) < 0)
                    goto fail;
            }
            for (int i = 0; i < 16; i++) dcraw[h264_zigzag4x4[i]] = scan[i];
            h264_luma_dc_dequant(dcraw, qp, aw4[0][0], luma_dc);
        }

        int16_t resid[16][16];                     /* raster per 4x4 block */
        int16_t resid8[4][64];                     /* raster per 8x8 block */
        memset(resid, 0, sizeof(resid));
        memset(resid8, 0, sizeof(resid8));
        if (t8) {
            int16_t scan64[64];
            for (int b = 0; b < 4; b++) {
                int bx0 = (int)(mbx * 4 + (uint32_t)(b & 1) * 2);
                int by0 = (int)(mby * 4 + (uint32_t)(b >> 1) * 2);
                if (cbp_luma & (1u << b)) {
                    if (use_cabac) {
                        int tc = cabac_residual8x8(&cbx, scan64, &out->err);
                        if (tc < 0) goto fail;
                        for (int k = 0; k < 64; k++)
                            resid8[b][h264_zigzag8x8[k]] = scan64[k];
                        for (int dy = 0; dy < 2; dy++)
                            for (int dx = 0; dx < 2; dx++) {
                                uint32_t gi = ((uint32_t)(by0 + dy)) * bw +
                                              (uint32_t)(bx0 + dx);
                                c.nzL[gi] = (uint8_t)(tc > 16 ? 16 : tc);
                                c.cbf_l[gi] = (tc != 0);
                            }
                    } else {
                        /* CAVLC: the 8x8 block is sent as 4 interleaved 4x4
                         * blocks; sub-block j carries scan positions 4k+j of
                         * the 8x8 zigzag (7.4.5.3.3). */
                        for (int j = 0; j < 4; j++) {
                            int gx = bx0 + (j & 1);
                            int gy = by0 + (j >> 1);
                            int nc = derive_nc(c.nzL, bw, gx, gy,
                                               blk4_avail(&c, sid, gx - 1, gy),
                                               blk4_avail(&c, sid, gx, gy - 1));
                            int tc = cavlc_residual_block(bs, nc, 16, scan,
                                                          &out->err);
                            if (tc < 0) goto fail;
                            uint32_t gi = (uint32_t)gy * bw + (uint32_t)gx;
                            c.nzL[gi] = (uint8_t)tc;
                            c.cbf_l[gi] = (tc != 0);
                            for (int k = 0; k < 16; k++)
                                resid8[b][h264_zigzag8x8[4 * k + j]] = scan[k];
                        }
                    }
                } else {
                    for (int dy = 0; dy < 2; dy++)
                        for (int dx = 0; dx < 2; dx++) {
                            uint32_t gi = ((uint32_t)(by0 + dy)) * bw +
                                          (uint32_t)(bx0 + dx);
                            c.nzL[gi] = 0;
                            c.cbf_l[gi] = 0;
                        }
                }
            }
        } else
        for (int k = 0; k < 16; k++) {
            int gx = (int)(mbx * 4 + zscan_x[k]);
            int gy = (int)(mby * 4 + zscan_y[k]);
            if (cbp_luma & (1u << (k >> 2))) {
                int maxc = intra4x4 ? 16 : 15;
                int tc;
                if (use_cabac) {
                    int ca = cbf_cond_luma4(&c, 1, sid, gx - 1, gy);
                    int cbn = cbf_cond_luma4(&c, 1, sid, gx, gy - 1);
                    tc = cabac_residual(&cbx, intra4x4 ? 2 : 1, ca, cbn,
                                        maxc, scan, &out->err);
                    if (tc < 0) goto fail;
                    c.cbf_l[(uint32_t)gy * bw + (uint32_t)gx] = (tc != 0);
                } else {
                    int nc = derive_nc(c.nzL, bw, gx, gy,
                                       blk4_avail(&c, sid, gx - 1, gy),
                                       blk4_avail(&c, sid, gx, gy - 1));
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
                    int ca = cbf_cond_chromadc(&c, 1, sid, comp, mbx, mby, -1, 0);
                    int cbn = cbf_cond_chromadc(&c, 1, sid, comp, mbx, mby, 0, -1);
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
                        int ca = cbf_cond_chroma4(&c, 1, sid, comp, gx - 1, gy);
                        int cbn = cbf_cond_chroma4(&c, 1, sid, comp, gx, gy - 1);
                        tc = cabac_residual(&cbx, 4, ca, cbn, 15, scan,
                                            &out->err);
                        if (tc < 0) goto fail;
                        c.cbf_c[comp][(uint32_t)gy * (bw / 2) + (uint32_t)gx] =
                            (tc != 0);
                    } else {
                        int avA = gx > 0 &&
                            mb_avail(&c, sid, (gx - 1) >> 1, gy >> 1);
                        int avB = gy > 0 &&
                            mb_avail(&c, sid, gx >> 1, (gy - 1) >> 1);
                        int nc = derive_nc(c.nzC[comp], bw / 2, gx, gy,
                                           avA, avB);
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

        if (!t8 && !sh->is_p && !sh->is_b) {
            uint8_t i4m[16];
            for (int k = 0; k < 16; k++) {
                i4m[k] = (uint8_t)c.i4_mode[(mby * 4 + zscan_y[k]) * bw +
                                            mbx * 4 + zscan_x[k]];
            }
            rtl_dump_mb(mbx, mby, intra4x4 ? 0 : 1,
                        (uint32_t)((cbp_chroma << 4) | cbp_luma), qp, i16_mode,
                        chroma_mode, i4m,
                        (const int16_t (*)[16])resid, dcraw,
                        (const int16_t (*)[4])cdc,
                        (const int16_t (*)[4][16])cres);
        }

        /* ---- reconstruction ---- */
        int32_t d[16];
        if (intra4x4 && t8) {
            int32_t d64[64];
            for (int b = 0; b < 4; b++) {
                uint8_t *bdst = ydst + (size_t)(b >> 1) * 8 * c.ls
                                     + (size_t)(b & 1) * 8;
                int avL = mb_avail(&c, sid, (int)mbx - 1, (int)mby);
                int avT = mb_avail(&c, sid, (int)mbx, (int)mby - 1);
                int avTL = mb_avail(&c, sid, (int)mbx - 1, (int)mby - 1);
                int avTR = mb_avail(&c, sid, (int)mbx + 1, (int)mby - 1);
                int aL = (b & 1) ? 1 : avL;
                int aT = (b >> 1) ? 1 : avT;
                int aTL = (b == 0) ? avTL
                        : (b == 1) ? avT
                        : (b == 2) ? avL : 1;
                int aTR = (b == 0) ? avT
                        : (b == 1) ? avTR
                        : (b == 2) ? 1 : 0;
                if (h264_intra8x8_pred(bdst, c.ls, modes8[b],
                                       aL, aT, aTL, aTR)) {
                    out->err = H264_ERR_BAD_STREAM;
                goto fail;
                }
                if (cbp_luma & (1u << b)) {
                    h264_dequant8x8(resid8[b], qp, aw8[0], d64);
                    h264_idct8x8_add(bdst, c.ls, d64);
                }
            }
        } else if (intra4x4) {
            for (int k = 0; k < 16; k++) {
                int gx = (int)(mbx * 4 + zscan_x[k]);
                int gy = (int)(mby * 4 + zscan_y[k]);
                uint8_t *bdst = c.Y + (size_t)gy * 4 * c.ls + (size_t)gx * 4;
                int aL = ((gx & 3) != 0) || blk4_avail(&c, sid, gx - 1, gy);
                int aT = ((gy & 3) != 0) || blk4_avail(&c, sid, gx, gy - 1);
                int aTL = ((gx & 3) && (gy & 3))
                              ? 1 : blk4_avail(&c, sid, gx - 1, gy - 1);
                int aTR = blk_decoded(&c, sid, mbx, mby, k, gx + 1, gy - 1);
                if (h264_intra4x4_pred(bdst, c.ls, modes[k], aL, aT, aTL, aTR)) {
                    out->err = H264_ERR_BAD_STREAM;
                goto fail;
                }
                if (cbp_luma & (1u << (k >> 2))) {
                    h264_dequant4x4(resid[k], qp, aw4[0], d);
                    h264_idct4x4_add(bdst, c.ls, d);
                }
            }
        } else {
            if (h264_intra16x16_pred(ydst, c.ls, i16_mode,
                                     mb_avail(&c, sid, (int)mbx - 1, (int)mby),
                                     mb_avail(&c, sid, (int)mbx, (int)mby - 1))) {
                out->err = H264_ERR_BAD_STREAM;
                goto fail;
            }
            for (int k = 0; k < 16; k++) {
                uint32_t x4 = zscan_x[k], y4 = zscan_y[k];
                uint8_t *bdst = ydst + (size_t)y4 * 4 * c.ls + (size_t)x4 * 4;
                h264_dequant4x4(resid[k], qp, aw4[0], d);
                d[0] = luma_dc[y4 * 4 + x4];
                h264_idct4x4_add(bdst, c.ls, d);
            }
        }

        for (int comp = 0; comp < 2; comp++) {
            int qpc = h264_chroma_qp(clip3(0, 51,
                qp + (int)(comp ? pps->second_chroma_qp_offset
                                : pps->chroma_qp_offset)));
            uint8_t *cdst = comp ? vdst : udst;
            if (h264_intra_chroma_pred(cdst, c.cs, (int)chroma_mode,
                                       mb_avail(&c, sid, (int)mbx - 1, (int)mby),
                                       mb_avail(&c, sid, (int)mbx, (int)mby - 1))) {
                out->err = H264_ERR_BAD_STREAM;
                goto fail;
            }
            if (cbp_chroma == 0) continue;
            const uint8_t *wc = aw4[1 + comp];
            int32_t cdcd[4];
            h264_chroma_dc_dequant(cdc[comp], qpc, wc[0], cdcd);
            for (int k = 0; k < 4; k++) {
                uint8_t *bdst = cdst + (size_t)(k >> 1) * 4 * c.cs
                                     + (size_t)(k & 1) * 4;
                h264_dequant4x4(cres[comp][k], qpc, wc, d);
                d[0] = cdcd[k];
                h264_idct4x4_add(bdst, c.cs, d);
            }
        }

        if (!use_cabac && !t8 && !sh->is_p && !sh->is_b) {
            rtl_dump_rec(ydst, c.ls, udst, vdst, c.cs);
        }

mb_done:
        if (brec_on) {
            brec.qp = (uint8_t)qp;
            for (int k = 0; k < 16; k++) {
                uint32_t gi = (mby * 4 + zscan_y[k]) * bw +
                              mbx * 4 + zscan_x[k];
                int l0 = (c.mb_ref[gi] >= 0);
                int l1 = (c.mb_ref1[gi] >= 0);
                brec.mv[0][k][0] = l0 ? c.mv_x[gi] : (int16_t)0;
                brec.mv[0][k][1] = l0 ? c.mv_y[gi] : (int16_t)0;
                brec.mv[1][k][0] = l1 ? c.mv1_x[gi] : (int16_t)0;
                brec.mv[1][k][1] = l1 ? c.mv1_y[gi] : (int16_t)0;
                brec.pmode[k] = (uint8_t)(l0 | (l1 << 1));
            }
            rtl_dump_b(&brec);
        }
        if (prec_on) {
            for (int k = 0; k < 16; k++) {
                uint32_t gi = (mby * 4 + zscan_y[k]) * bw +
                              mbx * 4 + zscan_x[k];
                prec.mv[k][0] = (c.mb_ref[gi] == -2) ? (int16_t)0
                                                     : c.mv_x[gi];
                prec.mv[k][1] = (c.mb_ref[gi] == -2) ? (int16_t)0
                                                     : c.mv_y[gi];
            }
            rtl_dump_p(&prec);
            if (!pps->weighted_pred)
                rtl_dump_prec(
                    c.Y + (size_t)mby * 16 * c.ls + (size_t)mbx * 16, c.ls,
                    c.U + (size_t)mby * 8 * c.cs + (size_t)mbx * 8,
                    c.V + (size_t)mby * 8 * c.cs + (size_t)mbx * 8, c.cs);
        }
        /* Intra MBs (and PCM) never wrote motion state: turn the -2
         * sentinels into -1 = intra, mv (0,0) for neighbor prediction. */
        for (int k = 0; k < 16; k++) {
            uint32_t gi = (mby * 4 + zscan_y[k]) * bw + mbx * 4 + zscan_x[k];
            if (c.mb_ref[gi] == -2) {
                c.mb_ref[gi] = -1;
                c.mv_x[gi] = 0;
                c.mv_y[gi] = 0;
                c.mb_ref1[gi] = -1;
                c.mv1_x[gi] = 0;
                c.mv1_y[gi] = 0;
                c.ref_poc0[gi] = POC_NONE;
                c.ref_poc1[gi] = POC_NONE;
                c.blk_direct[gi] = 0;
            }
        }
        c.mb_dbf_idc[mby * c.mb_w + mbx] = (int8_t)sh->disable_deblock;
        c.mb_dbf_a[mby * c.mb_w + mbx] = (int8_t)sh->alpha_c0_offset;
        c.mb_dbf_b[mby * c.mb_w + mbx] = (int8_t)sh->beta_offset;
        addr++;
        mbs_done++;
        if (use_cabac) {
            int eos = cabac_terminate(&cbx);
            if (cbx.error) { out->err = H264_ERR_TRUNC; goto fail; }
            if (eos) break;
        } else {
            /* a pending skip run keeps the loop alive even when the
             * RBSP is exhausted — the run was its last syntax element */
            if (skip_run <= 0 && !bs_more_rbsp_data(bs)) break;
        }
    }
    }                                      /* slice loop */

    if (mbs_done != total_mbs) {
        out->err = H264_ERR_BAD_STREAM;
                goto fail;
    }
    }

    /* 8x8-transform MBs: bS "non-zero coefficients" applies to the
     * TRANSFORM block (8.7.2.1) — promote per-4x4 nz to 8x8-block level
     * before filtering (nC derivation has already consumed the true
     * per-4x4 counts during parsing). */
    for (uint32_t mb = 0; mb < c.mb_w * c.mb_h; mb++) {
        if (!c.mb_t8[mb]) continue;
        uint32_t mbx2 = mb % c.mb_w, mby2 = mb / c.mb_w;
        for (int b = 0; b < 4; b++) {
            uint32_t bx0 = mbx2 * 4 + (uint32_t)(b & 1) * 2;
            uint32_t by0 = mby2 * 4 + (uint32_t)(b >> 1) * 2;
            int any = 0;
            for (int j = 0; j < 2; j++)
                for (int i = 0; i < 2; i++)
                    if (c.nzL[(by0 + (uint32_t)j) * bw + bx0 + (uint32_t)i])
                        any = 1;
            if (any) {
                for (int j = 0; j < 2; j++)
                    for (int i = 0; i < 2; i++)
                        c.nzL[(by0 + (uint32_t)j) * bw + bx0 +
                              (uint32_t)i] = 1;
            }
        }
    }

    /* ---- in-loop deblocking (8.7), per-MB slice parameters ---- */
    h264_deblock_frame(c.Y, c.U, c.V, c.ls, c.cs, c.mb_w, c.mb_h,
                       c.mb_qp, c.mb_t8, c.mb_slice,
                       c.mb_dbf_idc, c.mb_dbf_a, c.mb_dbf_b,
                       c.mb_cat, c.nzL, c.mv_x, c.mv_y, c.mv1_x, c.mv1_y,
                       c.ref_poc0, c.ref_poc1,
                       (int)pps->chroma_qp_offset,
                       (int)pps->second_chroma_qp_offset);

    /* ---- crop and append this frame to the output sequence ---- */
    {
    uint32_t W = c.mb_w * 16 - 2 * (sps->crop_l + sps->crop_r);
    uint32_t H = c.mb_h * 16 - 2 * (sps->crop_t + sps->crop_b);
    out->width = (uint16_t)W;
    out->height = (uint16_t)H;
    uint32_t cw = W / 2, chh = H / 2;
    size_t ysz = (size_t)W * H, csz = (size_t)cw * chh;
    uint32_t fr = out->nframes;
    uint8_t *ny = (uint8_t *)realloc(out->y_plane, ysz * (fr + 1));
    uint8_t *nu = (uint8_t *)realloc(out->cb_plane, csz * (fr + 1));
    uint8_t *nv = (uint8_t *)realloc(out->cr_plane, csz * (fr + 1));
    if (!ny || !nu || !nv) {
        free(ny ? ny : out->y_plane);
        free(nu ? nu : out->cb_plane);
        free(nv ? nv : out->cr_plane);
        out->y_plane = out->cb_plane = out->cr_plane = NULL;
        out->err = H264_ERR_INTERNAL;
        goto fail;
    }
    out->y_plane = ny;
    out->cb_plane = nu;
    out->cr_plane = nv;
    size_t yoff = (size_t)sps->crop_t * 2 * c.ls + (size_t)sps->crop_l * 2;
    size_t coff = (size_t)sps->crop_t * c.cs + (size_t)sps->crop_l;
    for (uint32_t r = 0; r < H; r++)
        memcpy(out->y_plane + fr * ysz + (size_t)r * W,
               c.Y + yoff + (size_t)r * c.ls, W);
    for (uint32_t r = 0; r < chh; r++) {
        memcpy(out->cb_plane + fr * csz + (size_t)r * cw,
               c.U + coff + (size_t)r * c.cs, cw);
        memcpy(out->cr_plane + fr * csz + (size_t)r * cw,
               c.V + coff + (size_t)r * c.cs, cw);
    }
    out->nframes = fr + 1;
    }

    free(c.i4_mode); free(c.nzL); free(c.nzC[0]); free(c.nzC[1]);
    free(c.mb_qp); free(c.mb_cat); free(c.mb_cmode); free(c.mb_cbp);
    free(c.cbf_l); free(c.cbf_ldc); free(c.cbf_c[0]); free(c.cbf_c[1]);
    free(c.cbf_cdc[0]); free(c.cbf_cdc[1]); free(c.mb_t8);
    free(c.mb_slice); free(c.mb_dbf_idc); free(c.mb_dbf_a); free(c.mb_dbf_b);
    free(c.mb_skip); free(c.mb_bdirect); free(c.mvd_ax); free(c.mvd_ay);
    free(c.blk_direct);
    free(c.ref_poc0); free(c.ref_poc1); free(c.mvd1_ax); free(c.mvd1_ay);
    keep->mv1x = c.mv1_x;
    keep->mv1y = c.mv1_y;
    keep->ref1 = c.mb_ref1;
    keep->Y = c.Y;                      /* caller keeps the padded frame */
    keep->U = c.U;
    keep->V = c.V;
    keep->mvx = c.mv_x;                 /* ...and the motion field */
    keep->mvy = c.mv_y;
    keep->ref = c.mb_ref;
    keep->poc = poc;
    keep->frame_num = ents[0].sh.frame_num;
    keep->n_ref2poc = c.n_refs < 8 ? c.n_refs : 8;
    for (int i = 0; i < keep->n_ref2poc; i++)
        keep->ref2poc[i] = c.list0[i]->poc;
    out->err = 0;
    return 0;

fail:
    free(c.Y); free(c.U); free(c.V);
    free(c.i4_mode); free(c.nzL); free(c.nzC[0]); free(c.nzC[1]);
    free(c.mb_qp); free(c.mb_cat); free(c.mb_cmode); free(c.mb_cbp);
    free(c.cbf_l); free(c.cbf_ldc); free(c.cbf_c[0]); free(c.cbf_c[1]);
    free(c.cbf_cdc[0]); free(c.cbf_cdc[1]); free(c.mb_t8);
    free(c.mb_slice); free(c.mb_dbf_idc); free(c.mb_dbf_a); free(c.mb_dbf_b);
    free(c.mv_x); free(c.mv_y); free(c.mb_ref);
    free(c.mb_skip); free(c.mb_bdirect); free(c.mvd_ax); free(c.mvd_ay);
    free(c.mv1_x); free(c.mv1_y); free(c.mb_ref1); free(c.blk_direct);
    free(c.ref_poc0); free(c.ref_poc1); free(c.mvd1_ax); free(c.mvd1_ay);
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
            if (parse_pps(&bs, &pps, sps.valid ? &sps : NULL, &out->err)) { nal_free(&n); return -1; }
            if (trace_level()) {
                fprintf(stderr,
                        "[PPS] entropy=%d init_qp=%d cqp_off=%d dbf_ctrl=%d "
                        "scal=%d w4[0][0]=%d w4[1][0]=%d w8[0][0]=%d\n",
                        pps.entropy_coding_mode, pps.pic_init_qp,
                        pps.chroma_qp_offset, pps.deblock_control_present,
                        pps.scaling_present, pps.w4[0][0], pps.w4[1][0],
                        pps.w8[0][0]);
            }
        } else if (n.type == NAL_SLICE_IDR || n.type == NAL_SLICE_NON_IDR) {
            if (!sps.valid) { out->err = H264_ERR_NO_SPS; nal_free(&n); return -1; }
            if (!pps.valid) { out->err = H264_ERR_NO_PPS; nal_free(&n); return -1; }
            /* Decode pictures until the stream runs out of slices. A slice
             * with first_mb==0 (after the first) starts the next picture. */
            enum { MAX_SLICES = 256 };
            slice_ent_t ents[MAX_SLICES];
            int nslices = 0;
            int have_nal = 1;                      /* n holds a slice NAL */
            enum { MAX_REFS = 8, MAX_OUT = 512 };
            dpb_ent_t dpb[MAX_REFS];
            memset(dpb, 0, sizeof(dpb));
            int ndpb = 0;
            /* POC state (8.2.1.1) and the output-order map. */
            int32_t prev_msb = 0;
            uint32_t prev_lsb = 0;
            int32_t out_poc[MAX_OUT];
            int n_out = 0;
            int32_t dec_idx = 0;
            for (;;) {
                slice_hdr_t sh;
                if (parse_slice_header(&bs, &sps, &pps, n.type, n.ref_idc,
                                       &sh, &out->err)) {
                    nal_free(&n);
                    goto ents_fail;
                }
                if (sh.first_mb == 0 && nslices > 0) {
                    /* picture boundary: decode what we have first */
                    int32_t poc;
                    if (ents[0].is_idr) { prev_msb = 0; prev_lsb = 0; }
                    if (sps.poc_type == 0) {
                        uint32_t maxlsb = 1u << sps.log2_max_poc_lsb;
                        uint32_t lsb = ents[0].sh.poc_lsb;
                        int32_t msb = prev_msb;
                        if (lsb < prev_lsb &&
                            prev_lsb - lsb >= maxlsb / 2) {
                            msb = prev_msb + (int32_t)maxlsb;
                        } else if (lsb > prev_lsb &&
                                   lsb - prev_lsb > maxlsb / 2) {
                            msb = prev_msb - (int32_t)maxlsb;
                        }
                        poc = msb + (int32_t)lsb;
                        if (ents[0].is_ref) {
                            prev_msb = msb;
                            prev_lsb = lsb;
                        }
                    } else {
                        poc = dec_idx;             /* type 2: decode order */
                    }
                    dec_idx++;
                    dpb_ent_t k;
                    memset(&k, 0, sizeof(k));
                    if (decode_picture(ents, nslices, &sps, &pps,
                                       dpb, ndpb, poc, &k, out)) {
                        nal_free(&n);
                        goto ents_fail;
                    }
                    if (n_out >= MAX_OUT) {
                        dpb_ent_free(&k);
                        out->err = H264_ERR_UNSUP;
                        nal_free(&n);
                        goto ents_fail;
                    }
                    out_poc[n_out++] = poc;
                    if (ents[0].is_idr) {          /* IDR empties the DPB */
                        for (int i = 0; i < ndpb; i++) dpb_ent_free(&dpb[i]);
                        ndpb = 0;
                    }
                    if (ents[0].is_ref) {
                        /* MMCO 1: release named short-term references */
                        for (int m = 0; m < ents[0].sh.n_mmco; m++) {
                            uint32_t max_fn = 1u << sps.log2_max_frame_num;
                            int32_t pnx = (int32_t)ents[0].sh.frame_num -
                                (int32_t)(ents[0].sh.mmco_diff[m] + 1);
                            while (pnx < 0) pnx += (int32_t)max_fn;
                            for (int i = 0; i < ndpb; i++) {
                                if ((int32_t)dpb[i].frame_num == pnx) {
                                    dpb_ent_free(&dpb[i]);
                                    for (int j = i; j < ndpb - 1; j++)
                                        dpb[j] = dpb[j + 1];
                                    memset(&dpb[ndpb - 1], 0,
                                           sizeof(dpb[0]));
                                    ndpb--;
                                    break;
                                }
                            }
                        }
                        /* push front (most recent first) */
                        if (ndpb == MAX_REFS) dpb_ent_free(&dpb[--ndpb]);
                        for (int i = ndpb; i > 0; i--) dpb[i] = dpb[i - 1];
                        dpb[0] = k;
                        ndpb++;
                    } else {
                        dpb_ent_free(&k);          /* non-ref B */
                    }
                    for (int i = 0; i < nslices; i++) free(ents[i].rbsp);
                    nslices = 0;
                }
                if (trace_level()) {
                    fprintf(stderr,
                            "[SLICE %d] first_mb=%u type=%u qp=%d dbf=%d\n",
                            nslices, sh.first_mb, sh.slice_type, sh.slice_qp,
                            sh.disable_deblock);
                }
                if (nslices >= MAX_SLICES) {
                    out->err = H264_ERR_UNSUP;
                    nal_free(&n);
                    goto ents_fail;
                }
                ents[nslices].rbsp = n.rbsp;       /* take ownership */
                ents[nslices].size = n.size;
                ents[nslices].byte = bs.byte;
                ents[nslices].bit = bs.bit;
                ents[nslices].is_idr = (n.type == NAL_SLICE_IDR);
                ents[nslices].is_ref = (n.ref_idc != 0);
                ents[nslices].sh = sh;
                nslices++;
                n.rbsp = NULL;

                /* Advance to the next slice NAL (skip SEI etc.). */
                have_nal = 0;
                while (nal_next(data, size, &pos, &n) == 0) {
                    if (n.type == NAL_SLICE_IDR ||
                        n.type == NAL_SLICE_NON_IDR) {
                        bs_init(&bs, n.rbsp, n.size);
                        have_nal = 1;
                        break;
                    }
                    nal_free(&n);
                }
                if (!have_nal) break;
            }
            int32_t poc;
            if (ents[0].is_idr) { prev_msb = 0; prev_lsb = 0; }
            if (sps.poc_type == 0) {
                uint32_t maxlsb = 1u << sps.log2_max_poc_lsb;
                uint32_t lsb = ents[0].sh.poc_lsb;
                int32_t msb = prev_msb;
                if (lsb < prev_lsb && prev_lsb - lsb >= maxlsb / 2) {
                    msb = prev_msb + (int32_t)maxlsb;
                } else if (lsb > prev_lsb && lsb - prev_lsb > maxlsb / 2) {
                    msb = prev_msb - (int32_t)maxlsb;
                }
                poc = msb + (int32_t)lsb;
            } else {
                poc = dec_idx;
            }
            dpb_ent_t k;
            memset(&k, 0, sizeof(k));
            int rc = decode_picture(ents, nslices, &sps, &pps,
                                    dpb, ndpb, poc, &k, out);
            dpb_ent_free(&k);
            for (int i = 0; i < ndpb; i++) dpb_ent_free(&dpb[i]);
            for (int i = 0; i < nslices; i++) free(ents[i].rbsp);
            if (rc == 0 && n_out < MAX_OUT) {
                out_poc[n_out++] = poc;
                /* Reorder output frames to display (POC) order. */
                size_t ysz = (size_t)out->width * out->height;
                size_t csz = ((size_t)out->width >> 1) *
                             ((size_t)out->height >> 1);
                int order[MAX_OUT];
                for (int i = 0; i < n_out; i++) order[i] = i;
                for (int i = 1; i < n_out; i++) {      /* stable insertion */
                    int oi = order[i];
                    int j = i;
                    while (j > 0 && out_poc[order[j - 1]] > out_poc[oi]) {
                        order[j] = order[j - 1];
                        j--;
                    }
                    order[j] = oi;
                }
                int sorted = 1;
                for (int i = 0; i < n_out; i++)
                    if (order[i] != i) sorted = 0;
                if (!sorted && out->nframes == (uint32_t)n_out) {
                    uint8_t *ny = (uint8_t *)malloc(ysz * (size_t)n_out);
                    uint8_t *nu = (uint8_t *)malloc(csz * (size_t)n_out);
                    uint8_t *nv = (uint8_t *)malloc(csz * (size_t)n_out);
                    if (!ny || !nu || !nv) {
                        free(ny); free(nu); free(nv);
                        out->err = H264_ERR_INTERNAL;
                        free(out->y_plane); free(out->cb_plane);
                        free(out->cr_plane);
                        out->y_plane = out->cb_plane = out->cr_plane = NULL;
                        return -1;
                    }
                    for (int i = 0; i < n_out; i++) {
                        memcpy(ny + (size_t)i * ysz,
                               out->y_plane + (size_t)order[i] * ysz, ysz);
                        memcpy(nu + (size_t)i * csz,
                               out->cb_plane + (size_t)order[i] * csz, csz);
                        memcpy(nv + (size_t)i * csz,
                               out->cr_plane + (size_t)order[i] * csz, csz);
                    }
                    free(out->y_plane); free(out->cb_plane);
                    free(out->cr_plane);
                    out->y_plane = ny;
                    out->cb_plane = nu;
                    out->cr_plane = nv;
                }
            }
            return rc;
ents_fail:
            for (int i = 0; i < ndpb; i++) dpb_ent_free(&dpb[i]);
            for (int i = 0; i < nslices; i++) free(ents[i].rbsp);
            return -1;
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
