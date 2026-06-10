#ifndef H264_CAVLC_H
#define H264_CAVLC_H

#include "bitstream.h"

/* Decode one CAVLC residual block (clause 9.2).
 *
 * nC:         neighbor coefficient predictor; -1 selects the 4:2:0 chroma
 *             DC table.
 * max_coeffs: 16 (luma 4x4 / Intra16x16 DC), 15 (AC blocks), 4 (chroma DC).
 * coefs:      output, scan order (caller applies zigzag), zero-filled.
 *
 * Returns total_coeff (>= 0) on success, -1 with *err set on failure. */
int cavlc_residual_block(bs_t *bs, int nC, int max_coeffs,
                         int16_t coefs[16], uint32_t *err);

/* me(v) mapped coded_block_pattern for intra MBs (Table 9-4). Returns -1
 * for out-of-range codeNum. */
int cavlc_intra_cbp(uint32_t code_num);

#endif
