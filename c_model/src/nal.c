#include "nal.h"

#include <stdlib.h>

/* Find the byte offset just past the next 00 00 01 start code at or after
 * `from`, or `size` if none. `sc_start` receives the offset where the start
 * code itself begins (including a preceding zero of a 4-byte code). */
static size_t find_start_code(const uint8_t *d, size_t size, size_t from,
                              size_t *sc_start) {
    for (size_t i = from; i + 2 < size; i++) {
        if (d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 1) {
            if (sc_start) {
                size_t s = i;
                if (s > 0 && d[s - 1] == 0) s--;   /* 00 00 00 01 form */
                *sc_start = s;
            }
            return i + 3;
        }
    }
    if (sc_start) *sc_start = size;
    return size;
}

int nal_next(const uint8_t *data, size_t size, size_t *pos, nal_t *out) {
    size_t payload = find_start_code(data, size, *pos, NULL);
    if (payload >= size) return -1;

    size_t next_sc;
    (void)find_start_code(data, size, payload, &next_sc);
    size_t end = next_sc;
    /* Trailing zero bytes before the next start code belong to no NAL. */
    while (end > payload && data[end - 1] == 0) end--;
    if (end <= payload) {
        *pos = next_sc;
        return -1;
    }

    uint8_t hdr = data[payload];
    out->type = hdr & 0x1F;
    out->ref_idc = (hdr >> 5) & 3;

    size_t raw = end - payload - 1;
    uint8_t *rbsp = (uint8_t *)malloc(raw ? raw : 1);
    if (!rbsp) return -1;
    size_t n = 0;
    int zeros = 0;
    for (size_t i = payload + 1; i < end; i++) {
        uint8_t b = data[i];
        if (zeros >= 2 && b == 0x03 && i + 1 < end && data[i + 1] <= 0x03) {
            zeros = 0;                 /* emulation prevention byte: drop */
            continue;
        }
        rbsp[n++] = b;
        zeros = (b == 0) ? zeros + 1 : 0;
    }
    out->rbsp = rbsp;
    out->size = n;
    *pos = next_sc;
    return 0;
}

void nal_free(nal_t *n) {
    free(n->rbsp);
    n->rbsp = NULL;
    n->size = 0;
}
