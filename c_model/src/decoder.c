#include "decoder.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bitstream.h"
#include "nal.h"
#include "params.h"
#include "slice.h"

static int trace_enabled(void) {
    static int v = -1;
    if (v < 0) v = (getenv("H264_TRACE") != NULL) ? 1 : 0;
    return v;
}

/* Decode the first IDR I-frame: scan NALs, latch SPS/PPS, then hand the
 * slice RBSP to the picture decoder. The failure-path contract is final
 * from day one: on error the wrapper releases any planes, only err
 * survives, callers need not call h264_free after a failed decode. */
static int h264_decode_impl(const uint8_t *data, size_t size,
                            h264_decoded_t *out) {
    memset(out, 0, sizeof(*out));
    sps_t sps;
    pps_t pps;
    memset(&sps, 0, sizeof(sps));
    memset(&pps, 0, sizeof(pps));

    size_t pos = 0;
    nal_t n;
    int saw_nal = 0;
    while (nal_next(data, size, &pos, &n) == 0) {
        saw_nal = 1;
        bs_t bs;
        bs_init(&bs, n.rbsp, n.size);
        if (n.type == NAL_SPS) {
            if (parse_sps(&bs, &sps, &out->err)) { nal_free(&n); return -1; }
            if (trace_enabled()) {
                fprintf(stderr,
                        "[SPS] profile=%u level=%u %ux%u MBs poc_type=%u "
                        "crop l=%u r=%u t=%u b=%u\n",
                        sps.profile_idc, sps.level_idc,
                        sps.mb_width, sps.mb_height, sps.poc_type,
                        sps.crop_l, sps.crop_r, sps.crop_t, sps.crop_b);
            }
        } else if (n.type == NAL_PPS) {
            if (parse_pps(&bs, &pps, &out->err)) { nal_free(&n); return -1; }
            if (trace_enabled()) {
                fprintf(stderr,
                        "[PPS] entropy=%d init_qp=%d cqp_off=%d dbf_ctrl=%d\n",
                        pps.entropy_coding_mode, pps.pic_init_qp,
                        pps.chroma_qp_offset, pps.deblock_control_present);
            }
        } else if (n.type == NAL_SLICE_IDR || n.type == NAL_SLICE_NON_IDR) {
            if (!sps.valid) { out->err = H264_ERR_NO_SPS; nal_free(&n); return -1; }
            if (!pps.valid) { out->err = H264_ERR_NO_PPS; nal_free(&n); return -1; }
            slice_hdr_t sh;
            if (parse_slice_header(&bs, &sps, &pps, n.type, n.ref_idc,
                                   &sh, &out->err)) {
                nal_free(&n);
                return -1;
            }
            if (sh.first_mb != 0) {                /* single-slice scope */
                out->err = H264_ERR_UNSUP;
                nal_free(&n);
                return -1;
            }
            if (trace_enabled()) {
                fprintf(stderr,
                        "[SLICE] type=%u qp=%d disable_deblock=%d a_off=%d b_off=%d\n",
                        sh.slice_type, sh.slice_qp, sh.disable_deblock,
                        sh.alpha_c0_offset, sh.beta_offset);
            }
            /* Phase 3/4: slice_data (CAVLC + reconstruction) lands here. */
            out->err = H264_ERR_UNSUP;
            nal_free(&n);
            return -1;
        }
        /* SEI / AUD / filler: skipped. */
        nal_free(&n);
    }
    out->err = saw_nal ? H264_ERR_NO_SLICE : H264_ERR_NO_NAL;
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
