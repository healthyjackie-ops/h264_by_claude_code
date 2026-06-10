#include "params.h"

#include <string.h>

#include "decoder.h"
#include "transform.h"

/* Default scaling matrices, raster order (Tables 7-3/7-4, transcribed
 * from JM quant.c). */
static const uint8_t default4_intra[16] = {
     6, 13, 20, 28, 13, 20, 28, 32, 20, 28, 32, 37, 28, 32, 37, 42
};
static const uint8_t default4_inter[16] = {
    10, 14, 20, 24, 14, 20, 24, 27, 20, 24, 27, 30, 24, 27, 30, 34
};
static const uint8_t default8_intra[64] = {
     6, 10, 13, 16, 18, 23, 25, 27, 10, 11, 16, 18, 23, 25, 27, 29,
    13, 16, 18, 23, 25, 27, 29, 31, 16, 18, 23, 25, 27, 29, 31, 33,
    18, 23, 25, 27, 29, 31, 33, 36, 23, 25, 27, 29, 31, 33, 36, 38,
    25, 27, 29, 31, 33, 36, 38, 40, 27, 29, 31, 33, 36, 38, 40, 42
};
static const uint8_t default8_inter[64] = {
     9, 13, 15, 17, 19, 21, 22, 24, 13, 13, 17, 19, 21, 22, 24, 25,
    15, 17, 19, 21, 22, 24, 25, 27, 17, 19, 21, 22, 24, 25, 27, 28,
    19, 21, 22, 24, 25, 27, 28, 30, 21, 22, 24, 25, 27, 28, 30, 32,
    22, 24, 25, 27, 28, 30, 32, 33, 24, 25, 27, 28, 30, 32, 33, 35
};

/* scaling_list() (7.3.2.1.1.1): delta_scale chain in zigzag order.
 * Returns 0 on success; sets *use_default when the first nextScale==0. */
static int parse_scaling_list(bs_t *bs, uint8_t *list, int size,
                              int *use_default) {
    const uint8_t *scan = (size == 16) ? h264_zigzag4x4 : h264_zigzag8x8;
    int last = 8, next = 8;
    *use_default = 0;
    for (int j = 0; j < size; j++) {
        int pos = scan[j];
        if (next != 0) {
            int32_t delta = bs_se(bs);
            if (delta < -128 || delta > 127) return -1;
            next = (last + delta + 256) % 256;
            if (j == 0 && next == 0) *use_default = 1;
        }
        list[pos] = (uint8_t)((next == 0) ? last : next);
        last = list[pos];
    }
    return 0;
}

static int profile_has_chroma_info(uint32_t p) {
    switch (p) {
    case 100: case 110: case 122: case 244: case 44:
    case 83: case 86: case 118: case 128:
    case 134: case 135: case 138: case 139:
        return 1;
    default:
        return 0;
    }
}

int parse_sps(bs_t *bs, sps_t *sps, uint32_t *err) {
    memset(sps, 0, sizeof(*sps));
    memset(sps->w4, 16, sizeof(sps->w4));
    memset(sps->w8, 16, sizeof(sps->w8));
    sps->profile_idc = bs_u(bs, 8);
    bs_skip(bs, 8);                                /* constraint flags + reserved */
    sps->level_idc = bs_u(bs, 8);
    sps->sps_id = bs_ue(bs);
    if (sps->sps_id > 31) { *err = H264_ERR_BAD_STREAM; return -1; }

    sps->chroma_format_idc = 1;
    sps->bit_depth_luma = 8;
    sps->bit_depth_chroma = 8;
    if (profile_has_chroma_info(sps->profile_idc)) {
        sps->chroma_format_idc = bs_ue(bs);
        if (sps->chroma_format_idc == 3) bs_skip(bs, 1);   /* separate_colour */
        sps->bit_depth_luma = bs_ue(bs) + 8;
        sps->bit_depth_chroma = bs_ue(bs) + 8;
        bs_skip(bs, 1);                            /* qpprime_y_zero */
        if (bs_u1(bs)) {                           /* seq_scaling_matrix_present */
            /* 8 lists at 4:2:0 (6x 4x4 + 2x 8x8), fall-back rule A. */
            sps->scaling_present = 1;
            for (int i = 0; i < 8; i++) {
                int present = (int)bs_u1(bs);
                if (!present) {
                    if (i == 0) memcpy(sps->w4[0], default4_intra, 16);
                    else if (i == 3) memcpy(sps->w4[3], default4_inter, 16);
                    else if (i == 6) memcpy(sps->w8[0], default8_intra, 64);
                    else if (i == 7) memcpy(sps->w8[1], default8_inter, 64);
                    else memcpy(sps->w4[i], sps->w4[i - 1], 16);
                    continue;
                }
                int use_def = 0;
                if (i < 6) {
                    if (parse_scaling_list(bs, sps->w4[i], 16, &use_def)) {
                        *err = H264_ERR_BAD_STREAM;
                        return -1;
                    }
                    if (use_def) {
                        memcpy(sps->w4[i], i < 3 ? default4_intra
                                                 : default4_inter, 16);
                    }
                } else {
                    if (parse_scaling_list(bs, sps->w8[i - 6], 64, &use_def)) {
                        *err = H264_ERR_BAD_STREAM;
                        return -1;
                    }
                    if (use_def) {
                        memcpy(sps->w8[i - 6], i == 6 ? default8_intra
                                                      : default8_inter, 64);
                    }
                }
            }
        }
    }
    if (sps->chroma_format_idc != 1 ||
        sps->bit_depth_luma != 8 || sps->bit_depth_chroma != 8) {
        *err = H264_ERR_UNSUP;
        return -1;
    }

    sps->log2_max_frame_num = bs_ue(bs) + 4;
    if (sps->log2_max_frame_num > 16) { *err = H264_ERR_BAD_STREAM; return -1; }
    sps->poc_type = bs_ue(bs);
    if (sps->poc_type == 0) {
        sps->log2_max_poc_lsb = bs_ue(bs) + 4;
        if (sps->log2_max_poc_lsb > 16) { *err = H264_ERR_BAD_STREAM; return -1; }
    } else if (sps->poc_type == 1) {
        sps->delta_pic_order_always_zero = (int)bs_u1(bs);
        (void)bs_se(bs);                           /* offset_for_non_ref_pic */
        (void)bs_se(bs);                           /* offset_for_top_to_bottom */
        uint32_t n = bs_ue(bs);
        if (n > 255) { *err = H264_ERR_BAD_STREAM; return -1; }
        for (uint32_t i = 0; i < n; i++) (void)bs_se(bs);
    } else if (sps->poc_type != 2) {
        *err = H264_ERR_BAD_STREAM;
        return -1;
    }
    sps->max_num_ref_frames = bs_ue(bs);
    bs_skip(bs, 1);                                /* gaps_in_frame_num_allowed */
    sps->mb_width = bs_ue(bs) + 1;
    sps->mb_height = bs_ue(bs) + 1;
    if (sps->mb_width == 0 || sps->mb_width > 256 ||
        sps->mb_height == 0 || sps->mb_height > 256) {
        *err = H264_ERR_BAD_STREAM;
        return -1;
    }
    sps->frame_mbs_only = (int)bs_u1(bs);
    if (!sps->frame_mbs_only) {                    /* fields / MBAFF out of scope */
        *err = H264_ERR_UNSUP;
        return -1;
    }
    sps->direct_8x8 = (int)bs_u1(bs);
    sps->crop = (int)bs_u1(bs);
    if (sps->crop) {
        sps->crop_l = bs_ue(bs);
        sps->crop_r = bs_ue(bs);
        sps->crop_t = bs_ue(bs);
        sps->crop_b = bs_ue(bs);
        /* 4:2:0 frame: crop unit = 2 luma samples each direction. */
        if (2 * (sps->crop_l + sps->crop_r) >= sps->mb_width * 16 ||
            2 * (sps->crop_t + sps->crop_b) >= sps->mb_height * 16) {
            *err = H264_ERR_BAD_STREAM;
            return -1;
        }
    }
    /* vui_parameters: not needed for sample reconstruction — stop here. */
    if (bs->error) { *err = H264_ERR_TRUNC; return -1; }
    sps->valid = 1;
    return 0;
}

int parse_pps(bs_t *bs, pps_t *pps, const sps_t *sps, uint32_t *err) {
    memset(pps, 0, sizeof(*pps));
    pps->pps_id = bs_ue(bs);
    pps->sps_id = bs_ue(bs);
    if (pps->pps_id > 255 || pps->sps_id > 31) {
        *err = H264_ERR_BAD_STREAM;
        return -1;
    }
    pps->entropy_coding_mode = (int)bs_u1(bs);   /* 0 CAVLC / 1 CABAC */
    pps->bottom_field_poc_present = (int)bs_u1(bs);
    pps->num_slice_groups = bs_ue(bs) + 1;
    if (pps->num_slice_groups != 1) {              /* FMO out of scope */
        *err = H264_ERR_UNSUP;
        return -1;
    }
    pps->num_ref_idx_l0 = bs_ue(bs) + 1;
    pps->num_ref_idx_l1 = bs_ue(bs) + 1;
    pps->weighted_pred = (int)bs_u1(bs);
    pps->weighted_bipred = bs_u(bs, 2);
    pps->pic_init_qp = 26 + bs_se(bs);
    pps->pic_init_qs = 26 + bs_se(bs);
    pps->chroma_qp_offset = bs_se(bs);
    if (pps->pic_init_qp < 0 || pps->pic_init_qp > 51 ||
        pps->chroma_qp_offset < -12 || pps->chroma_qp_offset > 12) {
        *err = H264_ERR_BAD_STREAM;
        return -1;
    }
    pps->deblock_control_present = (int)bs_u1(bs);
    pps->constrained_intra = (int)bs_u1(bs);
    pps->redundant_pic_cnt_present = (int)bs_u1(bs);
    if (pps->constrained_intra || pps->redundant_pic_cnt_present) {
        *err = H264_ERR_UNSUP;
        return -1;
    }
    pps->second_chroma_qp_offset = pps->chroma_qp_offset;
    if (bs_more_rbsp_data(bs)) {
        pps->transform_8x8 = (int)bs_u1(bs);
        if (bs_u1(bs)) {                           /* pic_scaling_matrix */
            /* Fall-back rule B: an absent list inherits the SPS list when
             * SPS matrices exist; otherwise rule A defaults apply. x264
             * --cqm writes matrices here (PPS), not in the SPS. */
            /* Rule B inherits SPS lists only when the SPS actually
             * carried matrices; a matrix-less SPS means rule A defaults. */
            int sps_has = (sps && sps->valid && sps->scaling_present);
            pps->scaling_present = 1;
            int nlists = 6 + (pps->transform_8x8 ? 2 : 0);
            memset(pps->w4, 16, sizeof(pps->w4));
            memset(pps->w8, 16, sizeof(pps->w8));
            for (int i = 0; i < nlists; i++) {
                int present = (int)bs_u1(bs);
                if (!present) {
                    if (i == 0) {
                        memcpy(pps->w4[0], sps_has ? sps->w4[0]
                                                   : default4_intra, 16);
                    } else if (i == 3) {
                        memcpy(pps->w4[3], sps_has ? sps->w4[3]
                                                   : default4_inter, 16);
                    } else if (i == 6) {
                        memcpy(pps->w8[0], sps_has ? sps->w8[0]
                                                   : default8_intra, 64);
                    } else if (i == 7) {
                        memcpy(pps->w8[1], sps_has ? sps->w8[1]
                                                   : default8_inter, 64);
                    } else {
                        memcpy(pps->w4[i], pps->w4[i - 1], 16);
                    }
                    continue;
                }
                int use_def = 0;
                if (i < 6) {
                    if (parse_scaling_list(bs, pps->w4[i], 16, &use_def)) {
                        *err = H264_ERR_BAD_STREAM;
                        return -1;
                    }
                    if (use_def) {
                        memcpy(pps->w4[i], i < 3 ? default4_intra
                                                 : default4_inter, 16);
                    }
                } else {
                    if (parse_scaling_list(bs, pps->w8[i - 6], 64, &use_def)) {
                        *err = H264_ERR_BAD_STREAM;
                        return -1;
                    }
                    if (use_def) {
                        memcpy(pps->w8[i - 6], i == 6 ? default8_intra
                                                      : default8_inter, 64);
                    }
                }
            }
        }
        pps->second_chroma_qp_offset = bs_se(bs);
        if (pps->second_chroma_qp_offset < -12 ||
            pps->second_chroma_qp_offset > 12) {
            *err = H264_ERR_BAD_STREAM;
            return -1;
        }
    }
    if (bs->error) { *err = H264_ERR_TRUNC; return -1; }
    pps->valid = 1;
    return 0;
}
