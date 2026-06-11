#include "cavlc.h"

#include <stdio.h>
#include <stdlib.h>

#include <string.h>

#include "decoder.h"

/* VLC code tables transcribed from ISO/IEC 14496-10 Tables 9-5 / 9-7 /
 * 9-8 / 9-9(a) / 9-10 (numeric layout as in ffmpeg h264_cavlc.c, the
 * battle-tested transcription of the same spec tables).
 *
 * coeff_token: index = 4*TotalCoeff + TrailingOnes, len 0 = invalid entry.
 * Class 0: 0<=nC<2, class 1: 2<=nC<4, class 2: 4<=nC<8, class 3: nC>=8
 * (6-bit FLC). Chroma DC (nC==-1, 4:2:0) has its own 5-row table. */

static const uint8_t coeff_token_len[4][4 * 17] = {
    {
         1, 0, 0, 0,
         6, 2, 0, 0,     8, 6, 3, 0,     9, 8, 7, 5,    10, 9, 8, 6,
        11,10, 9, 7,    13,11,10, 8,    13,13,11, 9,    13,13,13,10,
        14,14,13,11,    14,14,14,13,    15,15,14,14,    15,15,15,14,
        16,15,15,15,    16,16,16,15,    16,16,16,16,    16,16,16,16,
    },
    {
         2, 0, 0, 0,
         6, 2, 0, 0,     6, 5, 3, 0,     7, 6, 6, 4,     8, 6, 6, 4,
         8, 7, 7, 5,     9, 8, 8, 6,    11, 9, 9, 6,    11,11,11, 7,
        12,11,11, 9,    12,12,12,11,    12,12,12,11,    13,13,13,12,
        13,13,13,13,    13,14,13,13,    14,14,14,13,    14,14,14,14,
    },
    {
         4, 0, 0, 0,
         6, 4, 0, 0,     6, 5, 4, 0,     6, 5, 5, 4,     7, 5, 5, 4,
         7, 5, 5, 4,     7, 6, 6, 4,     7, 6, 6, 4,     8, 7, 7, 5,
         8, 8, 7, 6,     9, 8, 8, 7,     9, 9, 8, 8,     9, 9, 9, 8,
        10, 9, 9, 9,    10,10,10,10,    10,10,10,10,    10,10,10,10,
    },
    {
         6, 0, 0, 0,
         6, 6, 0, 0,     6, 6, 6, 0,     6, 6, 6, 6,     6, 6, 6, 6,
         6, 6, 6, 6,     6, 6, 6, 6,     6, 6, 6, 6,     6, 6, 6, 6,
         6, 6, 6, 6,     6, 6, 6, 6,     6, 6, 6, 6,     6, 6, 6, 6,
         6, 6, 6, 6,     6, 6, 6, 6,     6, 6, 6, 6,     6, 6, 6, 6,
    }
};

static const uint8_t coeff_token_bits[4][4 * 17] = {
    {
         1, 0, 0, 0,
         5, 1, 0, 0,     7, 4, 1, 0,     7, 6, 5, 3,     7, 6, 5, 3,
         7, 6, 5, 4,    15, 6, 5, 4,    11,14, 5, 4,     8,10,13, 4,
        15,14, 9, 4,    11,10,13,12,    15,14, 9,12,    11,10,13, 8,
        15, 1, 9,12,    11,14,13, 8,     7,10, 9,12,     4, 6, 5, 8,
    },
    {
         3, 0, 0, 0,
        11, 2, 0, 0,     7, 7, 3, 0,     7,10, 9, 5,     7, 6, 5, 4,
         4, 6, 5, 6,     7, 6, 5, 8,    15, 6, 5, 4,    11,14,13, 4,
        15,10, 9, 4,    11,14,13,12,     8,10, 9, 8,    15,14,13,12,
        11,10, 9,12,     7,11, 6, 8,     9, 8,10, 1,     7, 6, 5, 4,
    },
    {
        15, 0, 0, 0,
        15,14, 0, 0,    11,15,13, 0,     8,12,14,12,    15,10,11,11,
        11, 8, 9,10,     9,14,13, 9,     8,10, 9, 8,    15,14,13,13,
        11,14,10,12,    15,10,13,12,    11,14, 9,12,     8,10,13, 8,
        13, 7, 9,12,     9,12,11,10,     5, 8, 7, 6,     1, 4, 3, 2,
    },
    {
         3, 0, 0, 0,
         0, 1, 0, 0,     4, 5, 6, 0,     8, 9,10,11,    12,13,14,15,
        16,17,18,19,    20,21,22,23,    24,25,26,27,    28,29,30,31,
        32,33,34,35,    36,37,38,39,    40,41,42,43,    44,45,46,47,
        48,49,50,51,    52,53,54,55,    56,57,58,59,    60,61,62,63,
    }
};

static const uint8_t chroma_dc_coeff_token_len[4 * 5] = {
    2, 0, 0, 0,
    6, 1, 0, 0,
    6, 6, 3, 0,
    6, 7, 7, 6,
    6, 8, 8, 7,
};

static const uint8_t chroma_dc_coeff_token_bits[4 * 5] = {
    1, 0, 0, 0,
    7, 1, 0, 0,
    4, 6, 1, 0,
    3, 3, 2, 5,
    2, 3, 2, 0,
};

/* total_zeros[tc-1][tz] for 4x4 blocks (tc 1..15). */
static const uint8_t total_zeros_len[15][16] = {
    {1,3,3,4,4,5,5,6,6,7,7,8,8,9,9,9},
    {3,3,3,3,3,4,4,4,4,5,5,6,6,6,6},
    {4,3,3,3,4,4,3,3,4,5,5,6,5,6},
    {5,3,4,4,3,3,3,4,3,4,5,5,5},
    {4,4,4,3,3,3,3,3,4,5,4,5},
    {6,5,3,3,3,3,3,3,4,3,6},
    {6,5,3,3,3,2,3,4,3,6},
    {6,4,5,3,2,2,3,3,6},
    {6,6,4,2,2,3,2,5},
    {5,5,3,2,2,2,4},
    {4,4,3,3,1,3},
    {4,4,2,1,3},
    {3,3,1,2},
    {2,2,1},
    {1,1},
};

static const uint8_t total_zeros_bits[15][16] = {
    {1,3,2,3,2,3,2,3,2,3,2,3,2,3,2,1},
    {7,6,5,4,3,5,4,3,2,3,2,3,2,1,0},
    {5,7,6,5,4,3,4,3,2,3,2,1,1,0},
    {3,7,5,4,6,5,4,3,3,2,2,1,0},
    {5,4,3,7,6,5,4,3,2,1,1,0},
    {1,1,7,6,5,4,3,2,1,1,0},
    {1,1,5,4,3,3,2,1,1,0},
    {1,1,1,3,3,2,2,1,0},
    {1,0,1,3,2,1,1,1},
    {1,0,1,3,2,1,1},
    {0,1,1,2,1,3},
    {0,1,1,1,1},
    {0,1,1,1},
    {0,1,1},
    {0,1},
};

/* chroma DC (4:2:0) total_zeros[tc-1][tz], tc 1..3. */
static const uint8_t chroma_dc_total_zeros_len[3][4] = {
    { 1, 2, 3, 3 },
    { 1, 2, 2, 0 },
    { 1, 1, 0, 0 },
};

static const uint8_t chroma_dc_total_zeros_bits[3][4] = {
    { 1, 1, 1, 0 },
    { 1, 1, 0, 0 },
    { 1, 0, 0, 0 },
};

/* run_before[min(zerosLeft,7)-1][run]. */
static const uint8_t run_len[7][16] = {
    {1,1},
    {1,2,2},
    {2,2,2,2},
    {2,2,2,3,3},
    {2,2,3,3,3,3},
    {2,3,3,3,3,3,3},
    {3,3,3,3,3,3,3,4,5,6,7,8,9,10,11},
};

static const uint8_t run_bits[7][16] = {
    {1,0},
    {1,1,0},
    {3,2,1,0},
    {3,2,1,1,0},
    {3,2,3,2,1,0},
    {3,0,1,3,2,5,4},
    {7,6,5,4,3,2,1,1,1,1,1,1,1,1,1},
};

/* Table 9-4, Intra_4x4 column. */
static const uint8_t golomb_to_intra4x4_cbp[48] = {
    47, 31, 15, 0,  23, 27, 29, 30, 7,  11, 13, 14, 39, 43, 45, 46,
    16, 3,  5,  10, 12, 19, 21, 26, 28, 35, 37, 42, 44, 1,  2,  4,
    8,  17, 18, 20, 24, 6,  9,  22, 25, 32, 33, 34, 36, 40, 38, 41
};

int cavlc_intra_cbp(uint32_t code_num) {
    if (code_num >= 48) return -1;
    return golomb_to_intra4x4_cbp[code_num];
}

/* Match a VLC from (len,bits) arrays laid out as [4*tc + t1]. Returns 0 on
 * success with tc and t1 set. */
static int match_coeff_token(bs_t *bs, const uint8_t *len, const uint8_t *bits,
                             int nrows, int *tc, int *t1) {
    for (int i = 0; i < 4 * nrows; i++) {
        int l = len[i];
        if (l == 0) continue;
        if (bs_peek(bs, l) == bits[i]) {
            bs_skip(bs, l);
            *tc = i >> 2;
            *t1 = i & 3;
            return 0;
        }
    }
    return -1;
}

static int match_vlc(bs_t *bs, const uint8_t *len, const uint8_t *bits,
                     int count) {
    for (int i = 0; i < count; i++) {
        int l = len[i];
        if (l == 0) continue;
        if (bs_peek(bs, l) == bits[i]) {
            bs_skip(bs, l);
            return i;
        }
    }
    return -1;
}

/* RTL replay log (rtl_spec.md R1b): per-block record of the raw bits
 * consumed plus the decoded outputs, for the cavlc_block testbench. */
static FILE *cavlc_log_file(void) {
    static FILE *f;
    static int tried;
    if (!tried) {
        tried = 1;
        const char *path = getenv("H264_CAVLC_LOG");
        if (path) f = fopen(path, "wb");
    }
    return f;
}

static int cavlc_residual_block_impl(bs_t *bs, int nC, int max_coeffs,
                                     int16_t coefs[16], uint32_t *err);

int cavlc_residual_block(bs_t *bs, int nC, int max_coeffs,
                         int16_t coefs[16], uint32_t *err) {
    FILE *f = cavlc_log_file();
    if (!f) return cavlc_residual_block_impl(bs, nC, max_coeffs, coefs, err);

    size_t b0 = bs->byte * 8 + (size_t)bs->bit;
    int tc = cavlc_residual_block_impl(bs, nC, max_coeffs, coefs, err);
    if (tc < 0) return tc;
    size_t b1 = bs->byte * 8 + (size_t)bs->bit;
    size_t nbits = b1 - b0;

    uint8_t hdr[4] = { (uint8_t)nC, (uint8_t)max_coeffs,
                       (uint8_t)(nbits & 0xFF), (uint8_t)(nbits >> 8) };
    fwrite(hdr, 1, 4, f);
    size_t nbytes = (nbits + 7) / 8;
    for (size_t i = 0; i < nbytes; i++) {
        uint8_t v = 0;
        for (int k = 0; k < 8; k++) {
            size_t bit = b0 + i * 8 + (size_t)k;
            if (bit < b1) {
                v = (uint8_t)((v << 1) |
                    ((bs->data[bit >> 3] >> (7 - (bit & 7))) & 1));
            } else {
                v = (uint8_t)(v << 1);
            }
        }
        fwrite(&v, 1, 1, f);
    }
    uint8_t tcb = (uint8_t)tc;
    fwrite(&tcb, 1, 1, f);
    fwrite(coefs, sizeof(int16_t), 16, f);
    return tc;
}

static int cavlc_residual_block_impl(bs_t *bs, int nC, int max_coeffs,
                                     int16_t coefs[16], uint32_t *err) {
    memset(coefs, 0, 16 * sizeof(coefs[0]));

    int tc = 0, t1 = 0;
    if (nC == -1) {
        if (match_coeff_token(bs, chroma_dc_coeff_token_len,
                              chroma_dc_coeff_token_bits, 5, &tc, &t1)) {
            *err = H264_ERR_BAD_STREAM;
            return -1;
        }
    } else {
        int cls = (nC < 2) ? 0 : (nC < 4) ? 1 : (nC < 8) ? 2 : 3;
        if (match_coeff_token(bs, coeff_token_len[cls],
                              coeff_token_bits[cls], 17, &tc, &t1)) {
            *err = H264_ERR_BAD_STREAM;
            return -1;
        }
    }
    if (bs->error) { *err = H264_ERR_TRUNC; return -1; }
    if (tc == 0) return 0;
    if (tc > max_coeffs || t1 > tc) { *err = H264_ERR_BAD_STREAM; return -1; }

    /* Levels, highest frequency first (clause 9.2.2). */
    int16_t level[16];
    int suffix_length = (tc > 10 && t1 < 3) ? 1 : 0;
    for (int i = 0; i < tc; i++) {
        if (i < t1) {
            level[i] = bs_u1(bs) ? -1 : 1;
            continue;
        }
        int prefix = 0;
        while (prefix < 32 && bs_u1(bs) == 0) {
            if (bs->error) { *err = H264_ERR_TRUNC; return -1; }
            prefix++;
        }
        if (prefix >= 32) { *err = H264_ERR_BAD_STREAM; return -1; }

        int level_code = (prefix < 15 ? prefix : 15) << suffix_length;
        if (suffix_length > 0 || prefix >= 14) {
            int suffix_size = suffix_length;
            if (prefix == 14 && suffix_length == 0) suffix_size = 4;
            else if (prefix >= 15) suffix_size = prefix - 3;
            level_code += (int)bs_u(bs, suffix_size);
        }
        if (prefix >= 15 && suffix_length == 0) level_code += 15;
        if (prefix >= 16) level_code += (1 << (prefix - 3)) - 4096;
        if (i == t1 && t1 < 3) level_code += 2;

        level[i] = (level_code % 2 == 0)
                       ? (int16_t)((level_code + 2) >> 1)
                       : (int16_t)(-((level_code + 1) >> 1));

        if (suffix_length == 0) suffix_length = 1;
        int abs_lvl = level[i] < 0 ? -level[i] : level[i];
        if (abs_lvl > (3 << (suffix_length - 1)) && suffix_length < 6) {
            suffix_length++;
        }
    }
    if (bs->error) { *err = H264_ERR_TRUNC; return -1; }

    /* total_zeros (clause 9.2.3). */
    int total_zeros = 0;
    if (tc < max_coeffs) {
        int v;
        if (nC == -1) {
            v = match_vlc(bs, chroma_dc_total_zeros_len[tc - 1],
                          chroma_dc_total_zeros_bits[tc - 1], 4);
        } else {
            v = match_vlc(bs, total_zeros_len[tc - 1],
                          total_zeros_bits[tc - 1], 16);
        }
        if (v < 0) { *err = H264_ERR_BAD_STREAM; return -1; }
        total_zeros = v;
        if (total_zeros > max_coeffs - tc) {
            *err = H264_ERR_BAD_STREAM;
            return -1;
        }
    }

    /* run_before (clause 9.2.3) + coefficient placement (9.2.4). */
    int zeros_left = total_zeros;
    int pos = tc + total_zeros - 1;
    for (int i = 0; i < tc; i++) {
        int run;
        if (i == tc - 1) {
            run = zeros_left;
        } else if (zeros_left > 0) {
            int row = (zeros_left < 7 ? zeros_left : 7) - 1;
            run = match_vlc(bs, run_len[row], run_bits[row], 16);
            if (run < 0 || run > zeros_left) {
                *err = H264_ERR_BAD_STREAM;
                return -1;
            }
        } else {
            run = 0;
        }
        if (pos < 0 || pos >= max_coeffs) { *err = H264_ERR_BAD_STREAM; return -1; }
        coefs[pos] = level[i];
        if (i < tc - 1) {
            pos -= 1 + run;
            zeros_left -= run;
        }
    }
    if (bs->error) { *err = H264_ERR_TRUNC; return -1; }
    return tc;
}
