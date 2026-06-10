#include "intra.h"

static uint8_t clip_u8(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return (uint8_t)v;
}

/* ---------------- Intra_4x4 (8.3.1) ---------------- */

int h264_intra4x4_pred(uint8_t *dst, size_t stride, int mode,
                       int avail_left, int avail_top,
                       int avail_topleft, int avail_topright) {
    /* Neighbor sample array: l[0..3] = left column (I..L), t[-1] = corner
     * (M), t[0..7] = above row (A..H). */
    uint8_t l[4], tbuf[9];
    uint8_t *t = tbuf + 1;
    if (avail_left) {
        for (int y = 0; y < 4; y++) l[y] = *(dst + (size_t)y * stride - 1);
    }
    if (avail_topleft) t[-1] = *(dst - stride - 1);
    if (avail_top) {
        for (int x = 0; x < 4; x++) t[x] = *(dst - stride + (size_t)x);
        if (avail_topright) {
            for (int x = 4; x < 8; x++) t[x] = *(dst - stride + (size_t)x);
        } else {
            for (int x = 4; x < 8; x++) t[x] = t[3];
        }
    }

    switch (mode) {
    case 0:                                   /* Vertical */
        if (!avail_top) return -1;
        for (int y = 0; y < 4; y++)
            for (int x = 0; x < 4; x++) dst[(size_t)y * stride + (size_t)x] = t[x];
        return 0;
    case 1:                                   /* Horizontal */
        if (!avail_left) return -1;
        for (int y = 0; y < 4; y++)
            for (int x = 0; x < 4; x++) dst[(size_t)y * stride + (size_t)x] = l[y];
        return 0;
    case 2: {                                 /* DC */
        int sum = 0, n = 0;
        if (avail_top) { sum += t[0] + t[1] + t[2] + t[3]; n += 4; }
        if (avail_left) { sum += l[0] + l[1] + l[2] + l[3]; n += 4; }
        uint8_t v = (n == 8) ? (uint8_t)((sum + 4) >> 3)
                  : (n == 4) ? (uint8_t)((sum + 2) >> 2) : 128;
        for (int y = 0; y < 4; y++)
            for (int x = 0; x < 4; x++) dst[(size_t)y * stride + (size_t)x] = v;
        return 0;
    }
    case 3:                                   /* Diagonal down-left */
        if (!avail_top) return -1;
        for (int y = 0; y < 4; y++) {
            for (int x = 0; x < 4; x++) {
                int v;
                if (x == 3 && y == 3) {
                    v = (t[6] + 3 * t[7] + 2) >> 2;
                } else {
                    int i = x + y;
                    v = (t[i] + 2 * t[i + 1] + t[i + 2] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    case 4:                                   /* Diagonal down-right */
        if (!avail_top || !avail_left || !avail_topleft) return -1;
        for (int y = 0; y < 4; y++) {
            for (int x = 0; x < 4; x++) {
                int v;
                if (x > y) {
                    int i = x - y;       /* i>=1; t[-1] is the corner */
                    v = (t[i - 2] + 2 * t[i - 1] + t[i] + 2) >> 2;
                } else if (x < y) {
                    int i = y - x;       /* uses left column */
                    int p0 = (i - 2 >= 0) ? l[i - 2] : t[-1];
                    int p1 = (i - 1 >= 0) ? l[i - 1] : t[-1];
                    v = (p0 + 2 * p1 + l[i] + 2) >> 2;
                    /* i>=1: l[i-2] valid for i>=2; i==1 → p0 = corner */
                } else {
                    v = (t[0] + 2 * t[-1] + l[0] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    case 5:                                   /* Vertical-right */
        if (!avail_top || !avail_left || !avail_topleft) return -1;
        for (int y = 0; y < 4; y++) {
            for (int x = 0; x < 4; x++) {
                int z = 2 * x - y;
                int v;
                if (z >= 0 && (z & 1) == 0) {
                    int i = x - (y >> 1);
                    v = (t[i - 1] + t[i] + 1) >> 1;
                } else if (z >= 0) {
                    int i = x - (y >> 1);
                    v = (t[i - 2] + 2 * t[i - 1] + t[i] + 2) >> 2;
                } else if (z == -1) {
                    v = (l[0] + 2 * t[-1] + t[0] + 2) >> 2;
                } else {
                    int i = y - 2 * x;   /* z <= -2 ⇒ i >= 2 */
                    int p0 = (i - 3 >= 0) ? l[i - 3] : t[-1];
                    v = (p0 + 2 * l[i - 2] + l[i - 1] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    case 6:                                   /* Horizontal-down */
        if (!avail_top || !avail_left || !avail_topleft) return -1;
        for (int y = 0; y < 4; y++) {
            for (int x = 0; x < 4; x++) {
                int z = 2 * y - x;
                int v;
                if (z >= 0 && (z & 1) == 0) {
                    int i = y - (x >> 1);
                    int p0 = (i - 1 >= 0) ? l[i - 1] : t[-1];
                    v = (p0 + l[i] + 1) >> 1;
                } else if (z >= 0) {
                    int i = y - (x >> 1);
                    int p0 = (i - 2 >= 0) ? l[i - 2] : t[-1];
                    int p1 = (i - 1 >= 0) ? l[i - 1] : t[-1];
                    v = (p0 + 2 * p1 + l[i] + 2) >> 2;
                } else if (z == -1) {
                    v = (l[0] + 2 * t[-1] + t[0] + 2) >> 2;
                } else {
                    int i = x - 2 * y;   /* z <= -2 ⇒ i >= 2 */
                    int p0 = (i - 3 >= 0) ? t[i - 3] : t[-1];
                    v = (p0 + 2 * t[i - 2] + t[i - 1] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    case 7:                                   /* Vertical-left */
        if (!avail_top) return -1;
        for (int y = 0; y < 4; y++) {
            for (int x = 0; x < 4; x++) {
                int i = x + (y >> 1);
                int v;
                if ((y & 1) == 0) {
                    v = (t[i] + t[i + 1] + 1) >> 1;
                } else {
                    v = (t[i] + 2 * t[i + 1] + t[i + 2] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    case 8:                                   /* Horizontal-up */
        if (!avail_left) return -1;
        for (int y = 0; y < 4; y++) {
            for (int x = 0; x < 4; x++) {
                int z = x + 2 * y;
                int v;
                if (z > 5) {
                    v = l[3];
                } else if (z == 5) {
                    v = (l[2] + 3 * l[3] + 2) >> 2;
                } else if ((z & 1) == 0) {
                    int i = y + (x >> 1);
                    v = (l[i] + l[i + 1] + 1) >> 1;
                } else {
                    int i = y + (x >> 1);
                    v = (l[i] + 2 * l[i + 1] + l[i + 2] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    default:
        return -1;
    }
}

/* ---------------- Intra_16x16 (8.3.3) ---------------- */

int h264_intra16x16_pred(uint8_t *dst, size_t stride, int mode,
                         int avail_left, int avail_top) {
    switch (mode) {
    case 0:                                   /* Vertical */
        if (!avail_top) return -1;
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 16; x++)
                dst[(size_t)y * stride + (size_t)x] = *(dst - stride + (size_t)x);
        return 0;
    case 1:                                   /* Horizontal */
        if (!avail_left) return -1;
        for (int y = 0; y < 16; y++) {
            uint8_t v = *(dst + (size_t)y * stride - 1);
            for (int x = 0; x < 16; x++) dst[(size_t)y * stride + (size_t)x] = v;
        }
        return 0;
    case 2: {                                 /* DC */
        int sum = 0, n = 0;
        if (avail_top) {
            for (int x = 0; x < 16; x++) sum += *(dst - stride + (size_t)x);
            n += 16;
        }
        if (avail_left) {
            for (int y = 0; y < 16; y++) sum += *(dst + (size_t)y * stride - 1);
            n += 16;
        }
        uint8_t v = (n == 32) ? (uint8_t)((sum + 16) >> 5)
                  : (n == 16) ? (uint8_t)((sum + 8) >> 4) : 128;
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 16; x++) dst[(size_t)y * stride + (size_t)x] = v;
        return 0;
    }
    case 3: {                                 /* Plane */
        if (!avail_top || !avail_left) return -1;
        const uint8_t *top = dst - stride;
        int h = 0, v = 0;
        for (int i = 0; i < 8; i++) {
            h += (i + 1) * ((int)top[8 + i] - (int)top[6 - i]);
            v += (i + 1) * ((int)*(dst + (size_t)(8 + i) * stride - 1) -
                            (int)*(dst + (6 - i) * (ptrdiff_t)stride - 1));
        }
        /* x=6-i reaches -1: top[-1] / left[-1] are the corner sample. */
        int a = 16 * ((int)*(dst + 15 * stride - 1) + (int)top[15]);
        int b = (5 * h + 32) >> 6;
        int c = (5 * v + 32) >> 6;
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 16; x++)
                dst[(size_t)y * stride + (size_t)x] =
                    clip_u8((a + b * (x - 7) + c * (y - 7) + 16) >> 5);
        return 0;
    }
    default:
        return -1;
    }
}

/* ---------------- Chroma 8x8 (8.3.4) ---------------- */

static int avg_n(const uint8_t *p, ptrdiff_t step, int n) {
    int s = 0;
    for (int i = 0; i < n; i++) s += p[step * i];
    return (s + n / 2) / n;
}

int h264_intra_chroma_pred(uint8_t *dst, size_t stride, int mode,
                           int avail_left, int avail_top) {
    switch (mode) {
    case 0: {                                 /* DC, per 4x4 sub-block */
        for (int sb = 0; sb < 4; sb++) {
            int bx = (sb & 1) * 4, by = (sb >> 1) * 4;
            uint8_t *d = dst + (size_t)by * stride + (size_t)bx;
            const uint8_t *top = dst - stride + (size_t)bx;
            const uint8_t *left = dst + (size_t)by * stride - 1;
            int v;
            int use_top, use_left;
            if (sb == 1) {        /* (4,0): top first, else left */
                use_top = avail_top;
                use_left = !avail_top && avail_left;
            } else if (sb == 2) { /* (0,4): left first, else top */
                use_left = avail_left;
                use_top = !avail_left && avail_top;
            } else {              /* (0,0) and (4,4): both when available */
                use_top = avail_top;
                use_left = avail_left;
            }
            if (use_top && use_left) {
                int s = 0;
                for (int i = 0; i < 4; i++) s += top[i];
                for (int i = 0; i < 4; i++) s += left[(size_t)i * stride];
                v = (s + 4) >> 3;
            } else if (use_top) {
                v = avg_n(top, 1, 4);
            } else if (use_left) {
                v = avg_n(left, (ptrdiff_t)stride, 4);
            } else {
                v = 128;
            }
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++)
                    d[(size_t)y * stride + (size_t)x] = (uint8_t)v;
        }
        return 0;
    }
    case 1:                                   /* Horizontal */
        if (!avail_left) return -1;
        for (int y = 0; y < 8; y++) {
            uint8_t v = *(dst + (size_t)y * stride - 1);
            for (int x = 0; x < 8; x++) dst[(size_t)y * stride + (size_t)x] = v;
        }
        return 0;
    case 2:                                   /* Vertical */
        if (!avail_top) return -1;
        for (int y = 0; y < 8; y++)
            for (int x = 0; x < 8; x++)
                dst[(size_t)y * stride + (size_t)x] = *(dst - stride + (size_t)x);
        return 0;
    case 3: {                                 /* Plane */
        if (!avail_top || !avail_left) return -1;
        const uint8_t *top = dst - stride;
        int h = 0, v = 0;
        for (int i = 0; i < 4; i++) {
            h += (i + 1) * ((int)top[4 + i] - (int)top[2 - i]);
            v += (i + 1) * ((int)*(dst + (size_t)(4 + i) * stride - 1) -
                            (int)*(dst + (2 - i) * (ptrdiff_t)stride - 1));
        }
        int a = 16 * ((int)*(dst + 7 * stride - 1) + (int)top[7]);
        int b = (34 * h + 32) >> 6;
        int c = (34 * v + 32) >> 6;
        for (int y = 0; y < 8; y++)
            for (int x = 0; x < 8; x++)
                dst[(size_t)y * stride + (size_t)x] =
                    clip_u8((a + b * (x - 3) + c * (y - 3) + 16) >> 5);
        return 0;
    }
    default:
        return -1;
    }
}

/* ---------------- Intra_8x8 (8.3.2) ---------------- */

int h264_intra8x8_pred(uint8_t *dst, size_t stride, int mode,
                       int avail_left, int avail_top,
                       int avail_topleft, int avail_topright) {
    /* Gather raw neighbors: l[0..7], tl, t[0..15] (E..H run substituted
     * with t[7] when top-right is unavailable). */
    uint8_t lr[8], tr_[16], tlr = 0;
    if (avail_left) {
        for (int y = 0; y < 8; y++) lr[y] = *(dst + (size_t)y * stride - 1);
    }
    if (avail_topleft) tlr = *(dst - stride - 1);
    if (avail_top) {
        for (int x = 0; x < 8; x++) tr_[x] = *(dst - stride + (size_t)x);
        if (avail_topright) {
            for (int x = 8; x < 16; x++) tr_[x] = *(dst - stride + (size_t)x);
        } else {
            for (int x = 8; x < 16; x++) tr_[x] = tr_[7];
        }
    }

    /* Reference sample filtering (8.3.2.2.1). */
    uint8_t l[8], tbuf[17];
    uint8_t *t = tbuf + 1;
    if (avail_top) {
        t[0] = avail_topleft
                   ? (uint8_t)((tlr + 2 * tr_[0] + tr_[1] + 2) >> 2)
                   : (uint8_t)((3 * tr_[0] + tr_[1] + 2) >> 2);
        for (int x = 1; x < 15; x++) {
            t[x] = (uint8_t)((tr_[x - 1] + 2 * tr_[x] + tr_[x + 1] + 2) >> 2);
        }
        t[15] = (uint8_t)((tr_[14] + 3 * tr_[15] + 2) >> 2);
    }
    if (avail_topleft) {
        if (avail_top && avail_left) {
            t[-1] = (uint8_t)((tr_[0] + 2 * tlr + lr[0] + 2) >> 2);
        } else if (avail_top) {
            t[-1] = (uint8_t)((3 * tlr + tr_[0] + 2) >> 2);
        } else if (avail_left) {
            t[-1] = (uint8_t)((3 * tlr + lr[0] + 2) >> 2);
        } else {
            t[-1] = tlr;
        }
    }
    if (avail_left) {
        l[0] = avail_topleft
                   ? (uint8_t)((tlr + 2 * lr[0] + lr[1] + 2) >> 2)
                   : (uint8_t)((3 * lr[0] + lr[1] + 2) >> 2);
        for (int y = 1; y < 7; y++) {
            l[y] = (uint8_t)((lr[y - 1] + 2 * lr[y] + lr[y + 1] + 2) >> 2);
        }
        l[7] = (uint8_t)((lr[6] + 3 * lr[7] + 2) >> 2);
    }

    switch (mode) {
    case 0:                                   /* Vertical */
        if (!avail_top) return -1;
        for (int y = 0; y < 8; y++)
            for (int x = 0; x < 8; x++)
                dst[(size_t)y * stride + (size_t)x] = t[x];
        return 0;
    case 1:                                   /* Horizontal */
        if (!avail_left) return -1;
        for (int y = 0; y < 8; y++)
            for (int x = 0; x < 8; x++)
                dst[(size_t)y * stride + (size_t)x] = l[y];
        return 0;
    case 2: {                                 /* DC */
        int sum = 0, n = 0;
        if (avail_top) { for (int x = 0; x < 8; x++) sum += t[x]; n += 8; }
        if (avail_left) { for (int y = 0; y < 8; y++) sum += l[y]; n += 8; }
        uint8_t v = (n == 16) ? (uint8_t)((sum + 8) >> 4)
                  : (n == 8) ? (uint8_t)((sum + 4) >> 3) : 128;
        for (int y = 0; y < 8; y++)
            for (int x = 0; x < 8; x++)
                dst[(size_t)y * stride + (size_t)x] = v;
        return 0;
    }
    case 3:                                   /* Diagonal down-left */
        if (!avail_top) return -1;
        for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
                int v;
                if (x == 7 && y == 7) {
                    v = (t[14] + 3 * t[15] + 2) >> 2;
                } else {
                    int i = x + y;
                    v = (t[i] + 2 * t[i + 1] + t[i + 2] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    case 4:                                   /* Diagonal down-right */
        if (!avail_top || !avail_left || !avail_topleft) return -1;
        for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
                int v;
                if (x > y) {
                    int i = x - y;       /* i>=1; t[-1] is the corner */
                    v = (t[i - 2] + 2 * t[i - 1] + t[i] + 2) >> 2;
                } else if (x < y) {
                    int i = y - x;
                    int p0 = (i - 2 >= 0) ? l[i - 2] : t[-1];
                    int p1 = l[i - 1];
                    v = (p0 + 2 * p1 + l[i] + 2) >> 2;
                } else {
                    v = (t[0] + 2 * t[-1] + l[0] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    case 5:                                   /* Vertical-right */
        if (!avail_top || !avail_left || !avail_topleft) return -1;
        for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
                int z = 2 * x - y;
                int v;
                if (z >= 0 && (z & 1) == 0) {
                    int i = x - (y >> 1);
                    v = (t[i - 1] + t[i] + 1) >> 1;
                } else if (z >= 0) {
                    int i = x - (y >> 1);
                    v = (t[i - 2] + 2 * t[i - 1] + t[i] + 2) >> 2;
                } else if (z == -1) {
                    v = (l[0] + 2 * t[-1] + t[0] + 2) >> 2;
                } else {
                    int i = y - 2 * x;   /* z <= -2 ⇒ i >= 2 */
                    int p0 = (i - 3 >= 0) ? l[i - 3] : t[-1];
                    v = (p0 + 2 * l[i - 2] + l[i - 1] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    case 6:                                   /* Horizontal-down */
        if (!avail_top || !avail_left || !avail_topleft) return -1;
        for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
                int z = 2 * y - x;
                int v;
                if (z >= 0 && (z & 1) == 0) {
                    int i = y - (x >> 1);
                    int p0 = (i - 1 >= 0) ? l[i - 1] : t[-1];
                    v = (p0 + l[i] + 1) >> 1;
                } else if (z >= 0) {
                    int i = y - (x >> 1);
                    int p0 = (i - 2 >= 0) ? l[i - 2] : t[-1];
                    int p1 = (i - 1 >= 0) ? l[i - 1] : t[-1];
                    v = (p0 + 2 * p1 + l[i] + 2) >> 2;
                } else if (z == -1) {
                    v = (l[0] + 2 * t[-1] + t[0] + 2) >> 2;
                } else {
                    int i = x - 2 * y;   /* z <= -2 ⇒ i >= 2 */
                    int p0 = (i - 3 >= 0) ? t[i - 3] : t[-1];
                    v = (p0 + 2 * t[i - 2] + t[i - 1] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    case 7:                                   /* Vertical-left */
        if (!avail_top) return -1;
        for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
                int i = x + (y >> 1);
                int v;
                if ((y & 1) == 0) {
                    v = (t[i] + t[i + 1] + 1) >> 1;
                } else {
                    v = (t[i] + 2 * t[i + 1] + t[i + 2] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    case 8:                                   /* Horizontal-up */
        if (!avail_left) return -1;
        for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
                int z = x + 2 * y;
                int v;
                if (z > 13) {
                    v = l[7];
                } else if (z == 13) {
                    v = (l[6] + 3 * l[7] + 2) >> 2;
                } else if ((z & 1) == 0) {
                    int i = y + (x >> 1);
                    v = (l[i] + l[i + 1] + 1) >> 1;
                } else {
                    int i = y + (x >> 1);
                    v = (l[i] + 2 * l[i + 1] + l[i + 2] + 2) >> 2;
                }
                dst[(size_t)y * stride + (size_t)x] = (uint8_t)v;
            }
        }
        return 0;
    default:
        return -1;
    }
}
