#ifndef H264_MC_H
#define H264_MC_H

#include <stddef.h>
#include <stdint.h>

/* Inter prediction sample interpolation (8.4.2.2).
 *
 * ref points at the reference plane (padded frame, stride given); pw/ph
 * are the plane dimensions used for edge clamping. x/y is the full-pel
 * block origin (may be negative / beyond the edge), fx/fy the fractional
 * phase: quarter-pel 0..3 for luma, eighth-pel 0..7 for chroma. */
void h264_mc_luma(const uint8_t *ref, size_t stride, int pw, int ph,
                  int x, int y, int fx, int fy,
                  uint8_t *dst, size_t dst_stride, int bw, int bh);

void h264_mc_chroma(const uint8_t *ref, size_t stride, int pw, int ph,
                    int x, int y, int fx, int fy,
                    uint8_t *dst, size_t dst_stride, int bw, int bh);

#endif
