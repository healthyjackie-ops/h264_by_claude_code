#ifndef H264_PARAMS_H
#define H264_PARAMS_H

#include "bitstream.h"

typedef struct {
    int valid;
    uint32_t profile_idc, level_idc;
    uint32_t sps_id;
    uint32_t chroma_format_idc;          /* must be 1 (4:2:0) */
    uint32_t bit_depth_luma, bit_depth_chroma;   /* must be 8 */
    uint32_t log2_max_frame_num;
    uint32_t poc_type, log2_max_poc_lsb;
    int delta_pic_order_always_zero;
    uint32_t max_num_ref_frames;
    uint32_t mb_width, mb_height;        /* picture size in MBs */
    int frame_mbs_only;
    int direct_8x8;
    int crop;
    uint32_t crop_l, crop_r, crop_t, crop_b;   /* in chroma units (×2 luma) */
} sps_t;

typedef struct {
    int valid;
    uint32_t pps_id, sps_id;
    int entropy_coding_mode;             /* must be 0 (CAVLC) */
    int bottom_field_poc_present;
    uint32_t num_slice_groups;           /* must be 1 */
    uint32_t num_ref_idx_l0, num_ref_idx_l1;
    int weighted_pred;
    uint32_t weighted_bipred;
    int32_t pic_init_qp;
    int32_t pic_init_qs;
    int32_t chroma_qp_offset;
    int deblock_control_present;
    int constrained_intra;               /* must be 0 */
    int redundant_pic_cnt_present;       /* must be 0 */
} pps_t;

/* Both return 0 on success, -1 with *err set otherwise. */
int parse_sps(bs_t *bs, sps_t *sps, uint32_t *err);
int parse_pps(bs_t *bs, pps_t *pps, uint32_t *err);

#endif
