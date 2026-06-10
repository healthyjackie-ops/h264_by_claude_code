#ifndef H264_CABAC_H
#define H264_CABAC_H

#include <stddef.h>
#include <stdint.h>

/* CABAC arithmetic decoding engine (clause 9.3.3.2) plus the I-slice
 * context models 0..276 (all an intra CAVLC->CABAC port needs: mb_type,
 * qp_delta, chroma pred, intra pred, CBP, coded_block_flag, significance
 * maps, levels, and the terminate context). */

#define H264_CABAC_NCTX 277

typedef struct {
    const uint8_t *data;
    size_t size;
    size_t pos;          /* next byte to read */
    int bit;             /* bits consumed in current byte */
    uint32_t range;      /* 9-bit coding range */
    uint32_t value;      /* 9-bit offset register */
    int overread;        /* bits consumed past the end */
    int error;
    uint8_t pstate[H264_CABAC_NCTX];
    uint8_t mps[H264_CABAC_NCTX];
} cabac_t;

/* Initialize contexts for an I slice at SliceQPy and prime the engine on
 * byte-aligned RBSP data starting at `pos`. */
void cabac_init(cabac_t *c, const uint8_t *data, size_t size, size_t pos,
                int slice_qp);

int cabac_decision(cabac_t *c, int ctx);   /* returns the decoded bin */
int cabac_bypass(cabac_t *c);
int cabac_terminate(cabac_t *c);           /* 1 = end_of_slice / PCM escape */

/* Current byte position (for I_PCM alignment handoff). */
size_t cabac_byte_pos(const cabac_t *c);

#endif
