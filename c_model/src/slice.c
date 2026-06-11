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
    sh->is_b = (sh->slice_type % 5 == 1);
    if (sh->slice_type % 5 != 2 && !sh->is_p && !sh->is_b) {
        *err = H264_ERR_UNSUP;                     /* SP/SI out of scope */
        return -1;
    }
    sh->pps_id = bs_ue(bs);
    sh->frame_num = bs_u(bs, (int)sps->log2_max_frame_num);
    /* frame_mbs_only == 1 enforced at SPS level: no field flags here. */
    if (nal_type == NAL_SLICE_IDR) {
        sh->idr_pic_id = bs_ue(bs);
    }
    if (sps->poc_type == 0) {
        sh->poc_lsb = bs_u(bs, (int)sps->log2_max_poc_lsb);
        if (pps->bottom_field_poc_present) (void)bs_se(bs);
    } else if (sps->poc_type == 1 && !sps->delta_pic_order_always_zero) {
        (void)bs_se(bs);
        if (pps->bottom_field_poc_present) (void)bs_se(bs);
    }
    if (sh->is_b) {
        sh->direct_spatial = (int)bs_u1(bs);
    }
    if (sh->is_p || sh->is_b) {
        sh->num_ref_l0 = pps->num_ref_idx_l0;
        sh->num_ref_l1 = pps->num_ref_idx_l1;
        if (bs_u1(bs)) {                           /* num_ref_idx_override */
            sh->num_ref_l0 = bs_ue(bs) + 1;
            if (sh->is_b) sh->num_ref_l1 = bs_ue(bs) + 1;
        }
        if (sh->num_ref_l0 < 1 || sh->num_ref_l0 > 8 ||
            (sh->is_b && (sh->num_ref_l1 < 1 || sh->num_ref_l1 > 8))) {
            *err = H264_ERR_UNSUP;
            return -1;
        }
        if (bs_u1(bs)) {                           /* ref_pic_list_modification l0 */
            for (;;) {
                uint32_t idc = bs_ue(bs);
                if (idc == 3) break;
                if (idc > 1 || sh->n_mod_l0 >= 8) {
                    *err = H264_ERR_UNSUP;         /* long-term unused */
                    return -1;
                }
                sh->mod_idc[sh->n_mod_l0] = (uint8_t)idc;
                sh->mod_val[sh->n_mod_l0] = bs_ue(bs) + 1;  /* abs_diff */
                sh->n_mod_l0++;
            }
            if (bs->error) { *err = H264_ERR_TRUNC; return -1; }
        }
        if (sh->is_b && bs_u1(bs)) {               /* ...modification l1 */
            *err = H264_ERR_UNSUP;
            return -1;
        }
        for (int i = 0; i < 8; i++) {              /* identity defaults */
            sh->lw[i] = 1; sh->lo[i] = 0;
            sh->cw[i][0] = sh->cw[i][1] = 1;
            sh->co[i][0] = sh->co[i][1] = 0;
        }
        if (sh->is_b && pps->weighted_bipred == 1) {
            *err = H264_ERR_UNSUP;                 /* explicit B WP unused */
            return -1;
        }
        if (pps->weighted_pred && sh->is_p) {      /* pred_weight_table */
            sh->wp = 1;
            sh->luma_log2_denom = (int)bs_ue(bs);
            sh->chroma_log2_denom = (int)bs_ue(bs);
            if (sh->luma_log2_denom > 7 || sh->chroma_log2_denom > 7) {
                *err = H264_ERR_BAD_STREAM;
                return -1;
            }
            for (uint32_t i = 0; i < sh->num_ref_l0; i++) {
                sh->lw[i] = (int16_t)(1 << sh->luma_log2_denom);
                sh->cw[i][0] = sh->cw[i][1] =
                    (int16_t)(1 << sh->chroma_log2_denom);
                if (bs_u1(bs)) {                   /* luma_weight_l0_flag */
                    sh->lw[i] = (int16_t)bs_se(bs);
                    sh->lo[i] = (int16_t)bs_se(bs);
                }
                if (bs_u1(bs)) {                   /* chroma_weight_l0_flag */
                    for (int j = 0; j < 2; j++) {
                        sh->cw[i][j] = (int16_t)bs_se(bs);
                        sh->co[i][j] = (int16_t)bs_se(bs);
                    }
                }
            }
        }
    }
    /* No pred-weight table for I; marking below. */
    if (nal_type == NAL_SLICE_IDR) {
        bs_skip(bs, 1);                            /* no_output_of_prior_pics */
        bs_skip(bs, 1);                            /* long_term_reference_flag */
    } else if (nal_ref_idc != 0) {
        if (bs_u1(bs)) {                           /* adaptive_ref_pic_marking */
            /* x264's B-pyramid releases short-term refs via MMCO 1. */
            for (;;) {
                uint32_t op = bs_ue(bs);
                if (op == 0) break;
                if (op != 1 || sh->n_mmco >= 8) {
                    *err = H264_ERR_UNSUP;
                    return -1;
                }
                sh->mmco_diff[sh->n_mmco++] = bs_ue(bs);
            }
            if (bs->error) { *err = H264_ERR_TRUNC; return -1; }
        }
    }
    if ((sh->is_p || sh->is_b) && pps->entropy_coding_mode) {
        uint32_t idc = bs_ue(bs);                  /* cabac_init_idc */
        if (idc > 2) { *err = H264_ERR_BAD_STREAM; return -1; }
        sh->cabac_init_idc = (int)idc;
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
