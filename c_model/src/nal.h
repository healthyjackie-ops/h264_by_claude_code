#ifndef H264_NAL_H
#define H264_NAL_H

#include <stddef.h>
#include <stdint.h>

enum {
    NAL_SLICE_NON_IDR = 1,
    NAL_SLICE_IDR     = 5,
    NAL_SEI           = 6,
    NAL_SPS           = 7,
    NAL_PPS           = 8,
    NAL_AUD           = 9,
    NAL_FILLER        = 12
};

typedef struct {
    int type;          /* nal_unit_type, 5 bits */
    int ref_idc;       /* nal_ref_idc, 2 bits */
    uint8_t *rbsp;     /* EPB-stripped payload (after the NAL header byte), malloc'd */
    size_t size;
} nal_t;

/* Extract the next NAL from an Annex-B byte stream starting at *pos.
 * Advances *pos past the consumed NAL. Returns 0 on success, -1 when no
 * further start code exists. Caller frees out->rbsp via nal_free(). */
int nal_next(const uint8_t *data, size_t size, size_t *pos, nal_t *out);
void nal_free(nal_t *n);

#endif
