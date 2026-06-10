#include "mc.h"

static int clampi(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static uint8_t clip_u8(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return (uint8_t)v;
}

/* Six-tap {1,-5,20,20,-5,1} over six ints. */
static int tap6(int a, int b, int c, int d, int e, int f) {
    return a - 5 * b + 20 * c + 20 * d - 5 * e + f;
}

/* Luma quarter-pel interpolation. A clamped (bw+5)x(bh+5) window makes
 * the 6-tap taps branch-free; intermediate j uses unclipped horizontal
 * half-pel sums per 8.4.2.2.1. Window origin is (x-2, y-2). */
void h264_mc_luma(const uint8_t *ref, size_t stride, int pw, int ph,
                  int x, int y, int fx, int fy,
                  uint8_t *dst, size_t dst_stride, int bw, int bh) {
    enum { MAXB = 16, PAD = 5 };
    uint8_t win[(MAXB + PAD) * (MAXB + PAD)];
    int ww = bw + PAD, wh = bh + PAD;
    for (int j = 0; j < wh; j++) {
        int sy = clampi(y - 2 + j, 0, ph - 1);
        const uint8_t *row = ref + (size_t)sy * stride;
        for (int i = 0; i < ww; i++) {
            win[j * ww + i] = row[clampi(x - 2 + i, 0, pw - 1)];
        }
    }
#define W(i, j) ((int)win[(j) * ww + (i)])

    /* G (integer) at window (2,2). */
    if (fx == 0 && fy == 0) {
        for (int j = 0; j < bh; j++)
            for (int i = 0; i < bw; i++)
                dst[(size_t)j * dst_stride + (size_t)i] =
                    (uint8_t)W(i + 2, j + 2);
        return;
    }

    /* Horizontal half-pel b at each needed row; vertical half-pel h at
     * each needed column; center j from unclipped horizontal sums. */
    if (fy == 0) {                                /* a, b, c */
        for (int j = 0; j < bh; j++) {
            for (int i = 0; i < bw; i++) {
                int b1 = tap6(W(i, j + 2), W(i + 1, j + 2), W(i + 2, j + 2),
                              W(i + 3, j + 2), W(i + 4, j + 2), W(i + 5, j + 2));
                int b = clip_u8((b1 + 16) >> 5);
                int v;
                if (fx == 2) {
                    v = b;
                } else {
                    int g = (fx == 1) ? W(i + 2, j + 2) : W(i + 3, j + 2);
                    v = (g + b + 1) >> 1;
                }
                dst[(size_t)j * dst_stride + (size_t)i] = (uint8_t)v;
            }
        }
        return;
    }
    if (fx == 0) {                                /* d, h, n */
        for (int j = 0; j < bh; j++) {
            for (int i = 0; i < bw; i++) {
                int h1 = tap6(W(i + 2, j), W(i + 2, j + 1), W(i + 2, j + 2),
                              W(i + 2, j + 3), W(i + 2, j + 4), W(i + 2, j + 5));
                int h = clip_u8((h1 + 16) >> 5);
                int v;
                if (fy == 2) {
                    v = h;
                } else {
                    int g = (fy == 1) ? W(i + 2, j + 2) : W(i + 2, j + 3);
                    v = (g + h + 1) >> 1;
                }
                dst[(size_t)j * dst_stride + (size_t)i] = (uint8_t)v;
            }
        }
        return;
    }

    /* Mixed phases need j (and its half-pel neighbors). Precompute the
     * unclipped horizontal 6-tap rows over the whole window height. */
    int hrow[(MAXB + PAD) * MAXB];                /* [wh][bw] */
    for (int j = 0; j < wh; j++) {
        for (int i = 0; i < bw; i++) {
            hrow[j * bw + i] = tap6(W(i, j), W(i + 1, j), W(i + 2, j),
                                    W(i + 3, j), W(i + 4, j), W(i + 5, j));
        }
    }
    for (int j = 0; j < bh; j++) {
        for (int i = 0; i < bw; i++) {
            int j1 = tap6(hrow[j * bw + i], hrow[(j + 1) * bw + i],
                          hrow[(j + 2) * bw + i], hrow[(j + 3) * bw + i],
                          hrow[(j + 4) * bw + i], hrow[(j + 5) * bw + i]);
            int jj = clip_u8((j1 + 512) >> 10);
            int v;
            if (fx == 2 && fy == 2) {
                v = jj;
            } else if (fy == 2) {                 /* i, k: j with vertical h */
                int col = (fx == 1) ? i + 2 : i + 3;
                int h1 = tap6(W(col, j), W(col, j + 1), W(col, j + 2),
                              W(col, j + 3), W(col, j + 4), W(col, j + 5));
                v = (clip_u8((h1 + 16) >> 5) + jj + 1) >> 1;
            } else if (fx == 2) {                 /* f, q: j with horizontal b */
                int row = (fy == 1) ? j + 2 : j + 3;
                int b = clip_u8((hrow[row * bw + i] + 16) >> 5);
                v = (b + jj + 1) >> 1;
            } else {                              /* e, g, p, r: b with h */
                int row = (fy == 1) ? j + 2 : j + 3;
                int b = clip_u8((hrow[row * bw + i] + 16) >> 5);
                int col = (fx == 1) ? i + 2 : i + 3;
                int h1 = tap6(W(col, j), W(col, j + 1), W(col, j + 2),
                              W(col, j + 3), W(col, j + 4), W(col, j + 5));
                int h = clip_u8((h1 + 16) >> 5);
                v = (b + h + 1) >> 1;
            }
            dst[(size_t)j * dst_stride + (size_t)i] = (uint8_t)v;
        }
    }
#undef W
}

void h264_mc_chroma(const uint8_t *ref, size_t stride, int pw, int ph,
                    int x, int y, int fx, int fy,
                    uint8_t *dst, size_t dst_stride, int bw, int bh) {
    for (int j = 0; j < bh; j++) {
        int y0 = clampi(y + j, 0, ph - 1);
        int y1 = clampi(y + j + 1, 0, ph - 1);
        const uint8_t *r0 = ref + (size_t)y0 * stride;
        const uint8_t *r1 = ref + (size_t)y1 * stride;
        for (int i = 0; i < bw; i++) {
            int x0 = clampi(x + i, 0, pw - 1);
            int x1 = clampi(x + i + 1, 0, pw - 1);
            int a = r0[x0], b = r0[x1], c = r1[x0], d = r1[x1];
            dst[(size_t)j * dst_stride + (size_t)i] = (uint8_t)(
                ((8 - fx) * (8 - fy) * a + fx * (8 - fy) * b +
                 (8 - fx) * fy * c + fx * fy * d + 32) >> 6);
        }
    }
}
