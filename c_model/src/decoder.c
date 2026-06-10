#include "decoder.h"

#include <stdlib.h>
#include <string.h>

#include "nal.h"

/* Phase 1: NAL traversal only — the picture-decoding layers land in later
 * phases. The failure-path contract is final from day one: h264_decode
 * releases any planes on error (only err survives), callers need not call
 * h264_free after a failed decode. */
static int h264_decode_impl(const uint8_t *data, size_t size,
                            h264_decoded_t *out) {
    memset(out, 0, sizeof(*out));
    size_t pos = 0;
    nal_t n;
    int saw_nal = 0;
    while (nal_next(data, size, &pos, &n) == 0) {
        saw_nal = 1;
        nal_free(&n);
    }
    out->err = saw_nal ? H264_ERR_UNSUP : H264_ERR_NO_NAL;
    return -1;
}

int h264_decode(const uint8_t *data, size_t size, h264_decoded_t *out) {
    int rc = h264_decode_impl(data, size, out);
    if (rc != 0) {
        uint32_t err = out->err;
        h264_free(out);
        out->err = err;
    }
    return rc;
}

void h264_free(h264_decoded_t *out) {
    free(out->y_plane);
    free(out->cb_plane);
    free(out->cr_plane);
    memset(out, 0, sizeof(*out));
}
