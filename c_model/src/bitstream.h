#ifndef H264_BITSTREAM_H
#define H264_BITSTREAM_H

#include <stddef.h>
#include <stdint.h>

/* Bit reader over an RBSP buffer (emulation-prevention bytes already
 * stripped by the NAL layer). Reads past the end set the error flag and
 * return 0 — callers check bs->error at syntax-element boundaries. */
typedef struct {
    const uint8_t *data;
    size_t size;
    size_t byte;   /* current byte offset */
    int bit;       /* bits consumed in current byte, 0..7 */
    int error;     /* sticky overread flag */
} bs_t;

void bs_init(bs_t *bs, const uint8_t *data, size_t size);

uint32_t bs_u1(bs_t *bs);
uint32_t bs_u(bs_t *bs, int n);          /* n in 0..32 */
uint32_t bs_ue(bs_t *bs);                /* Exp-Golomb unsigned */
int32_t  bs_se(bs_t *bs);                /* Exp-Golomb signed */
uint32_t bs_peek(bs_t *bs, int n);       /* peek without consuming (0-pad past end) */
void     bs_skip(bs_t *bs, int n);
void     bs_byte_align(bs_t *bs);
size_t   bs_bits_left(const bs_t *bs);

/* more_rbsp_data(): true iff there are bits beyond the rbsp_stop_one_bit. */
int bs_more_rbsp_data(const bs_t *bs);

#endif
