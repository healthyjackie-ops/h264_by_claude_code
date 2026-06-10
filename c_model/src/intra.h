#ifndef H264_INTRA_H
#define H264_INTRA_H

#include <stddef.h>
#include <stdint.h>

/* Intra_4x4 prediction modes (8.3.1). dst points at the block's top-left
 * sample inside the reconstructed plane; neighbors are read from the plane
 * itself. avail_* describe decoded-neighbor availability; when the
 * top-right run is unavailable but top is, E..H are substituted with D.
 * Returns 0, or -1 if the mode requires unavailable samples. */
int h264_intra4x4_pred(uint8_t *dst, size_t stride, int mode,
                       int avail_left, int avail_top,
                       int avail_topleft, int avail_topright);

/* Intra_16x16 modes: 0=V 1=H 2=DC 3=Plane (8.3.3). */
int h264_intra16x16_pred(uint8_t *dst, size_t stride, int mode,
                         int avail_left, int avail_top);

/* Chroma 8x8 modes: 0=DC 1=H 2=V 3=Plane (8.3.4). */
int h264_intra_chroma_pred(uint8_t *dst, size_t stride, int mode,
                           int avail_left, int avail_top);

/* Intra_8x8 luma prediction (8.3.2): same nine modes as Intra_4x4 at 8x8
 * size, with the mandatory reference-sample low-pass filter (8.3.2.2.1)
 * applied first. Neighbor samples are read from the plane around dst. */
int h264_intra8x8_pred(uint8_t *dst, size_t stride, int mode,
                       int avail_left, int avail_top,
                       int avail_topleft, int avail_topright);

#endif
