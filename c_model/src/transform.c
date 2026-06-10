#include "transform.h"

const uint8_t h264_zigzag4x4[16] = {
    0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15
};

/* Table 8-15 normalization matrix V, collapsed to the three position
 * classes: (even,even) / (odd,odd) / mixed. */
static const int16_t dequant_v[6][3] = {
    { 10, 16, 13 },
    { 11, 18, 14 },
    { 13, 20, 16 },
    { 14, 23, 18 },
    { 16, 25, 20 },
    { 18, 29, 23 },
};

static int vclass(int pos) {
    int r = pos >> 2, c = pos & 3;
    if (((r | c) & 1) == 0) return 0;     /* both even */
    if ((r & c & 1) == 1) return 1;       /* both odd */
    return 2;
}

int h264_chroma_qp(int qp) {
    static const int8_t map[22] = {
        29, 30, 31, 32, 32, 33, 34, 34, 35, 35, 36,
        36, 37, 37, 37, 38, 38, 38, 39, 39, 39, 39
    };
    if (qp < 30) return qp;
    return map[qp - 30];
}

void h264_dequant4x4(const int16_t c[16], int qp, int32_t d[16]) {
    int shift = qp / 6, rem = qp % 6;
    for (int i = 0; i < 16; i++) {
        d[i] = ((int32_t)c[i] * dequant_v[rem][vclass(i)]) << shift;
    }
}

void h264_luma_dc_dequant(const int16_t c[16], int qp, int32_t out[16]) {
    /* 4x4 inverse Hadamard (rows then columns, no normalization). */
    int32_t t[16], f[16];
    for (int i = 0; i < 4; i++) {
        int32_t a = c[i * 4 + 0], b = c[i * 4 + 1];
        int32_t cc = c[i * 4 + 2], dd = c[i * 4 + 3];
        int32_t s0 = a + cc, s1 = a - cc, s2 = b - dd, s3 = b + dd;
        t[i * 4 + 0] = s0 + s3;
        t[i * 4 + 1] = s1 + s2;
        t[i * 4 + 2] = s1 - s2;
        t[i * 4 + 3] = s0 - s3;
    }
    for (int j = 0; j < 4; j++) {
        int32_t a = t[0 * 4 + j], b = t[1 * 4 + j];
        int32_t cc = t[2 * 4 + j], dd = t[3 * 4 + j];
        int32_t s0 = a + cc, s1 = a - cc, s2 = b - dd, s3 = b + dd;
        f[0 * 4 + j] = s0 + s3;
        f[1 * 4 + j] = s1 + s2;
        f[2 * 4 + j] = s1 - s2;
        f[3 * 4 + j] = s0 - s3;
    }
    /* 8.5.10 with LevelScale = 16 * normAdjust (flat weightScale):
     * qp >= 36: dc = (f * 16v) << (qp/6 - 6)  =  (f * v) << (qp/6 - 2)
     * else:     dc = (f * 16v + 2^(5 - qp/6)) >> (6 - qp/6)              */
    int v0 = dequant_v[qp % 6][0];
    if (qp >= 36) {
        int sh = qp / 6 - 2;
        for (int i = 0; i < 16; i++) out[i] = (f[i] * v0) << sh;
    } else {
        int sh = 6 - qp / 6;
        int64_t round = (int64_t)1 << (sh - 1);
        for (int i = 0; i < 16; i++) {
            out[i] = (int32_t)(((int64_t)f[i] * v0 * 16 + round) >> sh);
        }
    }
}

void h264_chroma_dc_dequant(const int16_t c[4], int qp, int32_t out[4]) {
    int32_t f0 = c[0] + c[1] + c[2] + c[3];
    int32_t f1 = c[0] - c[1] + c[2] - c[3];
    int32_t f2 = c[0] + c[1] - c[2] - c[3];
    int32_t f3 = c[0] - c[1] - c[2] + c[3];
    /* 8.5.11 with LevelScale = 16 * normAdjust:
     * dc = ((f * 16v) << (qp/6)) >> 5  =  ((f * v) << (qp/6)) >> 1 */
    int v0 = dequant_v[qp % 6][0];
    int sh = qp / 6;
    out[0] = ((f0 * v0) << sh) >> 1;
    out[1] = ((f1 * v0) << sh) >> 1;
    out[2] = ((f2 * v0) << sh) >> 1;
    out[3] = ((f3 * v0) << sh) >> 1;
}

static uint8_t clip_u8(int32_t v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return (uint8_t)v;
}

void h264_idct4x4_add(uint8_t *dst, size_t stride, const int32_t d[16]) {
    int32_t t[16];
    for (int i = 0; i < 4; i++) {
        const int32_t *r = d + i * 4;
        int32_t e0 = r[0] + r[2];
        int32_t e1 = r[0] - r[2];
        int32_t e2 = (r[1] >> 1) - r[3];
        int32_t e3 = r[1] + (r[3] >> 1);
        t[i * 4 + 0] = e0 + e3;
        t[i * 4 + 1] = e1 + e2;
        t[i * 4 + 2] = e1 - e2;
        t[i * 4 + 3] = e0 - e3;
    }
    for (int j = 0; j < 4; j++) {
        int32_t e0 = t[0 * 4 + j] + t[2 * 4 + j];
        int32_t e1 = t[0 * 4 + j] - t[2 * 4 + j];
        int32_t e2 = (t[1 * 4 + j] >> 1) - t[3 * 4 + j];
        int32_t e3 = t[1 * 4 + j] + (t[3 * 4 + j] >> 1);
        int32_t g0 = e0 + e3, g1 = e1 + e2, g2 = e1 - e2, g3 = e0 - e3;
        dst[0 * stride + (size_t)j] = clip_u8((int32_t)dst[0 * stride + (size_t)j] + ((g0 + 32) >> 6));
        dst[1 * stride + (size_t)j] = clip_u8((int32_t)dst[1 * stride + (size_t)j] + ((g1 + 32) >> 6));
        dst[2 * stride + (size_t)j] = clip_u8((int32_t)dst[2 * stride + (size_t)j] + ((g2 + 32) >> 6));
        dst[3 * stride + (size_t)j] = clip_u8((int32_t)dst[3 * stride + (size_t)j] + ((g3 + 32) >> 6));
    }
}
