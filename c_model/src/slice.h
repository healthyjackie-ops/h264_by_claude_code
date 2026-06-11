#ifndef H264_SLICE_H
#define H264_SLICE_H

#include "bitstream.h"
#include "params.h"

typedef struct {
    uint32_t first_mb;
    uint32_t slice_type;        /* raw; %5: 2 = I, 0 = P */
    int is_p;
    uint32_t pps_id;
    uint32_t frame_num;
    uint32_t idr_pic_id;
    int32_t slice_qp;           /* pic_init_qp + slice_qp_delta */
    int disable_deblock;        /* disable_deblocking_filter_idc (0 when absent) */
    int32_t alpha_c0_offset;    /* ×2 applied, per spec */
    int32_t beta_offset;
    int cabac_init_idc;         /* P slices, CABAC only */
    uint32_t num_ref_l0;        /* active list0 size (P) */
    /* Explicit weighted prediction (pred_weight_table). When wp==0 the
     * defaults below are identity. */
    int wp;
    int luma_log2_denom, chroma_log2_denom;
    int16_t lw[8], lo[8];                /* luma weight/offset per ref */
    int16_t cw[8][2], co[8][2];          /* chroma, [ref][Cb/Cr] */
} slice_hdr_t;

/* Parse an I/IDR slice header (everything before slice_data). Returns 0 on
 * success, -1 with *err set otherwise. */
int parse_slice_header(bs_t *bs, const sps_t *sps, const pps_t *pps,
                       int nal_type, int nal_ref_idc,
                       slice_hdr_t *sh, uint32_t *err);

#endif
