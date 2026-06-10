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
} slice_hdr_t;

/* Parse an I/IDR slice header (everything before slice_data). Returns 0 on
 * success, -1 with *err set otherwise. */
int parse_slice_header(bs_t *bs, const sps_t *sps, const pps_t *pps,
                       int nal_type, int nal_ref_idc,
                       slice_hdr_t *sh, uint32_t *err);

#endif
