#ifndef H264_TRANSFORM_H
#define H264_TRANSFORM_H

#include <stddef.h>
#include <stdint.h>

/* 4x4 zigzag: scan position -> raster position. */
extern const uint8_t h264_zigzag4x4[16];

/* Map QPy (+ chroma offset, pre-clipped to 0..51) to QPc. */
int h264_chroma_qp(int qp);

/* Dequantize a 4x4 residual block (raster order, DC included) in place
 * into 32-bit working coefficients: d = c * V(qp%6,pos) << (qp/6). */
void h264_dequant4x4(const int16_t c[16], int qp, int32_t d[16]);

/* Inverse-Hadamard + dequantize the Intra_16x16 luma DC block (raster
 * order in/out, out[by*4+bx] = DC for luma 4x4 block (bx,by)). */
void h264_luma_dc_dequant(const int16_t c[16], int qp, int32_t out[16]);

/* 2x2 inverse Hadamard + dequant for one chroma component's DC
 * (raster: c00 c01 c10 c11), qp = QPc. */
void h264_chroma_dc_dequant(const int16_t c[4], int qp, int32_t out[4]);

/* Core 4x4 inverse transform of dequantized coefficients; adds the
 * (r+32)>>6 rounded residual onto dst with clipping. */
void h264_idct4x4_add(uint8_t *dst, size_t stride, const int32_t d[16]);

/* High profile 8x8 transform path (8.5.13). */
extern const uint8_t h264_zigzag8x8[64];
void h264_dequant8x8(const int16_t c[64], int qp, int32_t d[64]);
void h264_idct8x8_add(uint8_t *dst, size_t stride, const int32_t d[64]);

#endif
