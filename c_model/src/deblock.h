#ifndef H264_DEBLOCK_H
#define H264_DEBLOCK_H

#include <stddef.h>
#include <stdint.h>

/* In-loop deblocking (clause 8.7) over a fully reconstructed all-intra
 * frame: MB raster order, vertical edges then horizontal, bS = 4 on MB
 * boundaries and 3 on internal 4x4 edges. mb_qp holds each MB's final
 * luma QP (for cross-edge averages). Offsets are the slice-header
 * FilterOffsetA/B (already x2). */
/* mb_dbf_idc/a/b carry each MB's slice-header filter parameters:
 * idc==1 disables the MB entirely, idc==2 skips edges whose p-side MB
 * belongs to a different slice; offsets follow the q-side MB. */
/* mb_cat (<3 = intra), nzL (total_coeff per 4x4) and the quarter-pel
 * motion arrays drive the inter boundary strengths (8.7.2.1). */
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
                        int chroma_qp_offset, int second_chroma_qp_offset);

void h264_filter_edge_test(uint8_t *q0p, ptrdiff_t pstep, ptrdiff_t lstep,
                           int len, int alpha, int beta,
                           const int bs4[4], const int tc04[4], int seg,
                           int chroma);

#endif
