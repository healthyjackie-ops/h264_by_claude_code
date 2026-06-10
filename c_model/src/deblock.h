#ifndef H264_DEBLOCK_H
#define H264_DEBLOCK_H

#include <stddef.h>
#include <stdint.h>

/* In-loop deblocking (clause 8.7) over a fully reconstructed all-intra
 * frame: MB raster order, vertical edges then horizontal, bS = 4 on MB
 * boundaries and 3 on internal 4x4 edges. mb_qp holds each MB's final
 * luma QP (for cross-edge averages). Offsets are the slice-header
 * FilterOffsetA/B (already x2). */
void h264_deblock_frame(uint8_t *Y, uint8_t *U, uint8_t *V,
                        size_t ls, size_t cs,
                        uint32_t mb_w, uint32_t mb_h,
                        const uint8_t *mb_qp,
                        int chroma_qp_offset,
                        int alpha_off, int beta_off);

#endif
