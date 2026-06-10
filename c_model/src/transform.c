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

void h264_dequant4x4(const int16_t c[16], int qp, const uint8_t w[16],
                     int32_t d[16]) {
    /* JM form: d = ((c * w * V) << (qp/6) + 8) >> 4 — exact for flat 16. */
    int shift = qp / 6, rem = qp % 6;
    for (int i = 0; i < 16; i++) {
        int64_t v = (int64_t)c[i] * w[i] * dequant_v[rem][vclass(i)];
        d[i] = (int32_t)(((v << shift) + 8) >> 4);
    }
}

void h264_luma_dc_dequant(const int16_t c[16], int qp, int w0,
                          int32_t out[16]) {
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
    /* JM form (equivalent to 8.5.10 with LevelScale = w0 * normAdjust):
     * dc = ((f * w0 * V0) << (qp/6) + 32) >> 6 */
    int v0 = dequant_v[qp % 6][0];
    int sh = qp / 6;
    for (int i = 0; i < 16; i++) {
        int64_t v = (int64_t)f[i] * w0 * v0;
        out[i] = (int32_t)(((v << sh) + 32) >> 6);
    }
}

void h264_chroma_dc_dequant(const int16_t c[4], int qp, int w0,
                            int32_t out[4]) {
    int32_t f0 = c[0] + c[1] + c[2] + c[3];
    int32_t f1 = c[0] - c[1] + c[2] - c[3];
    int32_t f2 = c[0] + c[1] - c[2] - c[3];
    int32_t f3 = c[0] - c[1] - c[2] + c[3];
    /* JM form, NO rounding term: dc = ((f * w0 * V0) << (qp/6)) >> 5
     * (verified against instrumented JM read_comp_cavlc). */
    int v0 = dequant_v[qp % 6][0];
    int sh = qp / 6;
    int32_t f[4] = { f0, f1, f2, f3 };
    for (int i = 0; i < 4; i++) {
        int64_t v = (int64_t)f[i] * w0 * v0;
        out[i] = (int32_t)((v << sh) >> 5);
    }
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

/* ---------------- High profile 8x8 transform (8.5.13) ---------------- */

const uint8_t h264_zigzag8x8[64] = {
     0,  1,  8, 16,  9,  2,  3, 10, 17, 24, 32, 25, 18, 11,  4,  5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13,  6,  7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63
};

/* normAdjust8x8 (Table 8-15 analogue) — 4x4 periodic pattern, transcribed
 * from JM dequant_coef8. Indexed [qp%6][y%4][x%4]. */
static const int16_t dequant8_v[6][4][4] = {
    { {20, 19, 25, 19}, {19, 18, 24, 18}, {25, 24, 32, 24}, {19, 18, 24, 18} },
    { {22, 21, 28, 21}, {21, 19, 26, 19}, {28, 26, 35, 26}, {21, 19, 26, 19} },
    { {26, 24, 33, 24}, {24, 23, 31, 23}, {33, 31, 42, 31}, {24, 23, 31, 23} },
    { {28, 26, 35, 26}, {26, 25, 33, 25}, {35, 33, 45, 33}, {26, 25, 33, 25} },
    { {32, 30, 40, 30}, {30, 28, 38, 28}, {40, 38, 51, 38}, {30, 28, 38, 28} },
    { {36, 34, 46, 34}, {34, 32, 43, 32}, {46, 43, 58, 43}, {34, 32, 43, 32} },
};

void h264_dequant8x8(const int16_t c[64], int qp, const uint8_t w[64],
                     int32_t d[64]) {
    /* JM form: d = ((c * w * V8) << (qp/6) + 32) >> 6 */
    int per = qp / 6, rem = qp % 6;
    for (int i = 0; i < 64; i++) {
        int y = i >> 3, x = i & 7;
        int64_t v = (int64_t)c[i] * w[i] * dequant8_v[rem][y & 3][x & 3];
        d[i] = (int32_t)(((v << per) + 32) >> 6);
    }
}

static uint8_t clip_u8t(int32_t v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return (uint8_t)v;
}

void h264_idct8x8_add(uint8_t *dst, size_t stride, const int32_t d[64]) {
    int32_t t[64];
    for (int i = 0; i < 8; i++) {                  /* rows */
        const int32_t *r = d + i * 8;
        int32_t a0 = r[0] + r[4];
        int32_t a4 = r[0] - r[4];
        int32_t a2 = (r[2] >> 1) - r[6];
        int32_t a6 = r[2] + (r[6] >> 1);
        int32_t b0 = a0 + a6, b2 = a4 + a2, b4 = a4 - a2, b6 = a0 - a6;
        int32_t a1 = -r[3] + r[5] - r[7] - (r[7] >> 1);
        int32_t a3 =  r[1] + r[7] - r[3] - (r[3] >> 1);
        int32_t a5 = -r[1] + r[7] + r[5] + (r[5] >> 1);
        int32_t a7 =  r[3] + r[5] + r[1] + (r[1] >> 1);
        int32_t b1 = a1 + (a7 >> 2), b7 = a7 - (a1 >> 2);
        int32_t b3 = a3 + (a5 >> 2), b5 = (a3 >> 2) - a5;
        int32_t *o = t + i * 8;
        o[0] = b0 + b7; o[1] = b2 + b5; o[2] = b4 + b3; o[3] = b6 + b1;
        o[4] = b6 - b1; o[5] = b4 - b3; o[6] = b2 - b5; o[7] = b0 - b7;
    }
    for (int j = 0; j < 8; j++) {                  /* columns */
        int32_t c0 = t[0 * 8 + j], c1 = t[1 * 8 + j], c2 = t[2 * 8 + j];
        int32_t c3 = t[3 * 8 + j], c4 = t[4 * 8 + j], c5 = t[5 * 8 + j];
        int32_t c6 = t[6 * 8 + j], c7 = t[7 * 8 + j];
        int32_t a0 = c0 + c4;
        int32_t a4 = c0 - c4;
        int32_t a2 = (c2 >> 1) - c6;
        int32_t a6 = c2 + (c6 >> 1);
        int32_t b0 = a0 + a6, b2 = a4 + a2, b4 = a4 - a2, b6 = a0 - a6;
        int32_t a1 = -c3 + c5 - c7 - (c7 >> 1);
        int32_t a3 =  c1 + c7 - c3 - (c3 >> 1);
        int32_t a5 = -c1 + c7 + c5 + (c5 >> 1);
        int32_t a7 =  c3 + c5 + c1 + (c1 >> 1);
        int32_t b1 = a1 + (a7 >> 2), b7 = a7 - (a1 >> 2);
        int32_t b3 = a3 + (a5 >> 2), b5 = (a3 >> 2) - a5;
        int32_t g[8] = { b0 + b7, b2 + b5, b4 + b3, b6 + b1,
                         b6 - b1, b4 - b3, b2 - b5, b0 - b7 };
        for (int y = 0; y < 8; y++) {
            uint8_t *px = dst + (size_t)y * stride + (size_t)j;
            *px = clip_u8t((int32_t)*px + ((g[y] + 32) >> 6));
        }
    }
}
