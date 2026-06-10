#ifndef H264_DECODER_H
#define H264_DECODER_H

#include <stddef.h>
#include <stdint.h>

/* Error codes (sticky in h264_decoded_t.err). */
enum {
    H264_ERR_NO_NAL        = 0x01,  /* no start code / no usable NAL */
    H264_ERR_TRUNC         = 0x02,  /* bitstream overread / truncated */
    H264_ERR_UNSUP_PROFILE = 0x04,  /* profile/feature outside spec v0.1 */
    H264_ERR_UNSUP         = 0x08,  /* in-scope profile, unsupported tool */
    H264_ERR_BAD_STREAM    = 0x10,  /* syntax violation */
    H264_ERR_NO_SPS        = 0x20,
    H264_ERR_NO_PPS        = 0x40,
    H264_ERR_NO_SLICE      = 0x80,
    H264_ERR_INTERNAL      = 0x100  /* allocation failure */
};

typedef struct {
    uint16_t width;    /* cropped luma dims */
    uint16_t height;
    /* yuv420p planes, cropped: y = W*H, cb/cr = (W/2)*(H/2). */
    uint8_t *y_plane;
    uint8_t *cb_plane;
    uint8_t *cr_plane;
    uint32_t err;
} h264_decoded_t;

/* Decode the first IDR I-frame of an Annex-B byte stream. Returns 0 on
 * success. On failure all planes are released and only err survives. */
int h264_decode(const uint8_t *data, size_t size, h264_decoded_t *out);
void h264_free(h264_decoded_t *out);

#endif
