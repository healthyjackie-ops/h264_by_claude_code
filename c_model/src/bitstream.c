#include "bitstream.h"

void bs_init(bs_t *bs, const uint8_t *data, size_t size) {
    bs->data = data;
    bs->size = size;
    bs->byte = 0;
    bs->bit = 0;
    bs->error = 0;
}

uint32_t bs_u1(bs_t *bs) {
    if (bs->byte >= bs->size) {
        bs->error = 1;
        return 0;
    }
    uint32_t b = (uint32_t)(bs->data[bs->byte] >> (7 - bs->bit)) & 1u;
    if (++bs->bit == 8) {
        bs->bit = 0;
        bs->byte++;
    }
    return b;
}

uint32_t bs_u(bs_t *bs, int n) {
    uint32_t v = 0;
    for (int i = 0; i < n; i++) {
        v = (v << 1) | bs_u1(bs);
    }
    return v;
}

uint32_t bs_ue(bs_t *bs) {
    int zeros = 0;
    while (zeros < 32 && bs_u1(bs) == 0) {
        if (bs->error) return 0;
        zeros++;
    }
    if (zeros >= 32) {
        bs->error = 1;
        return 0;
    }
    uint32_t suffix = bs_u(bs, zeros);
    return ((1u << zeros) - 1u) + suffix;
}

int32_t bs_se(bs_t *bs) {
    uint32_t k = bs_ue(bs);
    int32_t v = (int32_t)((k + 1u) >> 1);
    return (k & 1u) ? v : -v;
}

uint32_t bs_peek(bs_t *bs, int n) {
    bs_t save = *bs;
    uint32_t v = 0;
    for (int i = 0; i < n; i++) {
        uint32_t b = 0;
        if (save.byte < save.size) {
            b = (uint32_t)(save.data[save.byte] >> (7 - save.bit)) & 1u;
            if (++save.bit == 8) {
                save.bit = 0;
                save.byte++;
            }
        }
        v = (v << 1) | b;
    }
    return v;
}

void bs_skip(bs_t *bs, int n) {
    for (int i = 0; i < n; i++) (void)bs_u1(bs);
}

void bs_byte_align(bs_t *bs) {
    if (bs->bit != 0) {
        bs->bit = 0;
        bs->byte++;
    }
}

size_t bs_bits_left(const bs_t *bs) {
    if (bs->byte >= bs->size) return 0;
    return (bs->size - bs->byte) * 8u - (size_t)bs->bit;
}

int bs_more_rbsp_data(const bs_t *bs) {
    size_t left = bs_bits_left(bs);
    if (left == 0) return 0;
    /* Scan back from the last byte for the rbsp_stop_one_bit: the final
     * '1' bit in the buffer. Data remains iff the current position is
     * strictly before that bit. */
    size_t last = bs->size;
    while (last > 0 && bs->data[last - 1] == 0) last--;
    if (last == 0) return 0;
    uint8_t b = bs->data[last - 1];
    int stop_bit = 0;                 /* bit index (0 = MSB) of the stop bit */
    for (int i = 0; i <= 7; i++) {    /* stop bit = least significant set bit */
        if (b & (1u << i)) {
            stop_bit = 7 - i;
            break;
        }
    }
    size_t stop_pos = (last - 1) * 8u + (size_t)stop_bit;
    size_t cur_pos = bs->byte * 8u + (size_t)bs->bit;
    return cur_pos < stop_pos;
}
