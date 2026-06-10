#include "slice.h"

#include <string.h>

#include "decoder.h"
#include "nal.h"

int parse_slice_header(bs_t *bs, const sps_t *sps, const pps_t *pps,
                       int nal_type, int nal_ref_idc,
                       slice_hdr_t *sh, uint32_t *err) {
    memset(sh, 0, sizeof(*sh));
    sh->first_mb = bs_ue(bs);
    sh->slice_type = bs_ue(bs);
    sh->is_p = (sh->slice_type % 5 == 0);
    if (sh->slice_type % 5 != 2 && !sh->is_p) {    /* I and P slices */
        *err = H264_ERR_UNSUP;
        return -1;
    }
    sh->pps_id = bs_ue(bs);
    sh->frame_num = bs_u(bs, (int)sps->log2_max_frame_num);
    /* frame_mbs_only == 1 enforced at SPS level: no field flags here. */
    if (nal_type == NAL_SLICE_IDR) {
        sh->idr_pic_id = bs_ue(bs);
    }
    if (sps->poc_type == 0) {
        bs_skip(bs, (int)sps->log2_max_poc_lsb);   /* pic_order_cnt_lsb */
        if (pps->bottom_field_poc_present) (void)bs_se(bs);
    } else if (sps->poc_type == 1 && !sps->delta_pic_order_always_zero) {
        (void)bs_se(bs);
        if (pps->bottom_field_poc_present) (void)bs_se(bs);
    }
    if (sh->is_p) {
        if (bs_u1(bs)) {                           /* num_ref_idx_override */
            uint32_t n0 = bs_ue(bs) + 1;
            if (n0 != 1) { *err = H264_ERR_UNSUP; return -1; }
        } else if (pps->num_ref_idx_l0 != 1) {
            *err = H264_ERR_UNSUP;                 /* single-reference scope */
            return -1;
        }
        if (bs_u1(bs)) {                           /* ref_pic_list_modification */
            *err = H264_ERR_UNSUP;
            return -1;
        }
        if (pps->weighted_pred) {                  /* pred_weight_table */
            *err = H264_ERR_UNSUP;
            return -1;
        }
    }
    /* No pred-weight table for I; marking below. */
    if (nal_type == NAL_SLICE_IDR) {
        bs_skip(bs, 1);                            /* no_output_of_prior_pics */
        bs_skip(bs, 1);                            /* long_term_reference_flag */
    } else if (nal_ref_idc != 0) {
        if (bs_u1(bs)) {                           /* adaptive_ref_pic_marking */
            *err = H264_ERR_UNSUP;
            return -1;
        }
    }
    sh->slice_qp = pps->pic_init_qp + bs_se(bs);
    if (sh->slice_qp < 0 || sh->slice_qp > 51) {
        *err = H264_ERR_BAD_STREAM;
        return -1;
    }
    if (pps->deblock_control_present) {
        sh->disable_deblock = (int)bs_ue(bs);
        if (sh->disable_deblock > 2) { *err = H264_ERR_BAD_STREAM; return -1; }
        if (sh->disable_deblock != 1) {
            sh->alpha_c0_offset = 2 * bs_se(bs);
            sh->beta_offset = 2 * bs_se(bs);
        }
    }
    if (bs->error) { *err = H264_ERR_TRUNC; return -1; }
    return 0;
}
