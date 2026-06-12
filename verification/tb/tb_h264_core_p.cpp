// P-R3e multi-frame differential on the synthesis top: h264_core
// decodes an IPPP stream frame by frame; the bench plays the system
// side — it holds each decoded frame and feeds it back as the MC
// reference for the next one (the writeback loop), answering row
// reads with clamp semantics. Every output frame is compared against
// the C model's decode of the whole stream.
//   usage: Vh264_core_p <stream.264>
#include <cstdio>
#include <cstring>
#include <vector>
#include <algorithm>

#include "Vh264_core.h"
#include "verilated.h"

extern "C" {
#include "bitstream.h"
#include "nal.h"
#include "params.h"
#include "slice.h"
#include "decoder.h"
}

namespace {
std::vector<uint8_t> rd(const char *p) {
    std::vector<uint8_t> b;
    FILE *f = fopen(p, "rb");
    if (!f) return b;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    b.resize((size_t)n);
    if (fread(b.data(), 1, b.size(), f) != b.size()) b.clear();
    fclose(f);
    return b;
}
int clampi(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}
struct SliceEnt {
    std::vector<uint8_t> rbsp;
    size_t sd_byte;
    int sd_bit;
    slice_hdr_t sh;
};
}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 2) {
        printf("usage: %s <stream.264>\n", argv[0]);
        return 1;
    }
    auto stream = rd(argv[1]);
    if (stream.empty()) { printf("[SKIP] inputs\n"); return 1; }

    // collect every slice; the whole stream must be inside the RTL
    // subset (CAVLC baseline, I/P, one slice per frame, nref 1)
    sps_t sps;
    pps_t pps;
    memset(&sps, 0, sizeof(sps));
    memset(&pps, 0, sizeof(pps));
    nal_t n;
    size_t pos = 0;
    uint32_t errc = 0;
    std::vector<SliceEnt> ents;
    while (nal_next(stream.data(), stream.size(), &pos, &n) == 0) {
        bs_t bs;
        bs_init(&bs, n.rbsp, n.size);
        if (n.type == 7) {
            if (parse_sps(&bs, &sps, &errc)) return 1;
        } else if (n.type == 8) {
            if (parse_pps(&bs, &pps, &sps, &errc)) return 1;
        } else if (n.type == 5 || n.type == 1) {
            SliceEnt e;
            if (parse_slice_header(&bs, &sps, &pps, n.type, n.ref_idc,
                                   &e.sh, &errc)) {
                printf("[SKIP] slice header\n");
                nal_free(&n);
                return 1;
            }
            if (pps.entropy_coding_mode || e.sh.is_b ||
                pps.transform_8x8 || e.sh.first_mb != 0 ||
                (e.sh.is_p && (e.sh.num_ref_l0 != 1 ||
                               pps.weighted_pred))) {
                printf("[SKIP] out of subset\n");
                nal_free(&n);
                return 1;
            }
            e.rbsp.assign(n.rbsp, n.rbsp + n.size);
            for (int pi = 0; pi < 8; pi++) e.rbsp.push_back(0);
            e.sd_byte = bs.byte;
            e.sd_bit = bs.bit;
            ents.push_back(std::move(e));
        }
        nal_free(&n);
    }
    if (ents.empty()) { printf("[SKIP] no slices\n"); return 1; }

    // golden: the C model decodes the whole stream
    h264_decoded_t gd;
    if (h264_decode(stream.data(), stream.size(), &gd) || !gd.nframes) {
        printf("[SKIP] golden decode err=0x%x\n", gd.err);
        return 1;
    }
    if (gd.nframes != ents.size()) {
        printf("[SKIP] frame count %u vs %zu slices\n", gd.nframes,
               ents.size());
        h264_free(&gd);
        return 1;
    }

    int W = gd.width, H = gd.height;
    int mb_w = (int)sps.mb_width;
    int FW = mb_w * 16;
    int FH = (int)sps.mb_height * 16;
    int CWp = FW / 2, CHp = FH / 2;
    std::vector<uint8_t> fy(FW * FH), fu(CWp * CHp), fv(CWp * CHp);
    std::vector<uint8_t> ry(FW * FH), ru(CWp * CHp), rv(CWp * CHp);

    Vh264_core top;
    int fails = 0;
    long total_cycles = 0;

    for (size_t f = 0; f < ents.size() && fails == 0; f++) {
        const SliceEnt &e = ents[f];
        std::fill(fy.begin(), fy.end(), 0);
        std::fill(fu.begin(), fu.end(), 0);
        std::fill(fv.begin(), fv.end(), 0);

        auto collect = [&] {
            if (!top.out_valid) return;
            int x = top.out_mbx, y = top.out_mby, r = top.out_row;
            if (top.out_plane == 0) {
                for (int i = 0; i < 16; i++)
                    fy[(y * 16 + r) * FW + x * 16 + i] = (uint8_t)
                        ((top.out_data[i / 4] >> ((i % 4) * 8)) & 0xFF);
            } else {
                auto &pl = (top.out_plane == 1) ? fu : fv;
                for (int i = 0; i < 8; i++)
                    pl[(y * 8 + r) * CWp + x * 8 + i] = (uint8_t)
                        ((top.out_data[i / 4] >> ((i % 4) * 8)) & 0xFF);
            }
        };
        auto tick = [&] {
            // reference row reads against the previous decoded frame
            top.mc_rsp_valid = 0;
            if (top.mc_req_valid) {
                int rx = (int16_t)((uint16_t)top.mc_req_x << 3) >> 3;
                int ry2 = (int16_t)((uint16_t)top.mc_req_y << 4) >> 4;
                int w = top.mc_req_w;
                const uint8_t *pl =
                    (top.mc_req_plane == 0) ? ry.data()
                    : (top.mc_req_plane == 1) ? ru.data() : rv.data();
                int pw = top.mc_req_plane ? CWp : FW;
                int ph = top.mc_req_plane ? CHp : FH;
                uint8_t px[9];
                for (int i = 0; i < w; i++)
                    px[i] = pl[(size_t)clampi(ry2, 0, ph - 1) * pw +
                               clampi(rx + i, 0, pw - 1)];
                for (int i = w; i < 9; i++) px[i] = 0;
                uint64_t hi = 0;
                for (int i = 0; i < 8; i++) hi = (hi << 8) | px[i];
                uint8_t lo8 = px[8];
                top.mc_rsp_data[0] =
                    (uint32_t)((((uint64_t)lo8) | (hi << 8)) & 0xFFFFFFFF);
                top.mc_rsp_data[1] = (uint32_t)(((hi << 8) | lo8) >> 32);
                top.mc_rsp_data[2] = (uint32_t)(hi >> 56);
                top.mc_rsp_valid = 1;
            }
            top.clk = 0;
            top.eval();
            top.clk = 1;
            top.eval();
            collect();
        };

        // hard reset between frames (line buffers restart per slice;
        // the only cross-frame state is the bench-side reference)
        top.rst_n = 0;
        top.in_valid = 0;
        top.start = 0;
        top.align_valid = 0;
        top.mc_rsp_valid = 0;
        tick();
        top.rst_n = 1;
        tick();
        top.cfg_mb_w = (uint8_t)sps.mb_width;
        top.cfg_mb_h = (uint8_t)sps.mb_height;
        top.cfg_qp = (uint8_t)e.sh.slice_qp;
        top.cfg_cqp_off = (uint8_t)(pps.chroma_qp_offset & 0x3F);
        top.cfg_a_off = (uint8_t)(e.sh.alpha_c0_offset & 0x3F);
        top.cfg_b_off = (uint8_t)(e.sh.beta_offset & 0x3F);
        top.cfg_deblock = (e.sh.disable_deblock != 1);
        top.cfg_is_p = e.sh.is_p ? 1 : 0;

        size_t fi = e.sd_byte;
        auto pump = [&] {
            top.in_valid = 0;
            if (fi < e.rbsp.size() && top.in_ready) {
                int nb = (int)std::min<size_t>(4, e.rbsp.size() - fi);
                uint32_t w = 0;
                for (int k = 0; k < nb; k++)
                    w |= (uint32_t)e.rbsp[fi + k] << (24 - k * 8);
                top.in_valid = 1;
                top.in_word = w;
                top.in_bytes = (uint8_t)nb;
            }
        };
        for (int i = 0; i < 16; i++) {
            pump();
            tick();
            if (top.in_valid) fi += top.in_bytes;
            top.in_valid = 0;
        }
        if (e.sd_bit) {
            top.align_valid = 1;
            top.align_bits = (uint8_t)e.sd_bit;
            pump();
            tick();
            if (top.in_valid) fi += top.in_bytes;
            top.align_valid = 0;
            top.in_valid = 0;
            tick();
        }
        top.start = 1;
        tick();
        top.start = 0;

        long guard = 0;
        while (!top.frame_done && !top.err && guard++ < 30000000) {
            pump();
            tick();
            if (top.in_valid) { fi += top.in_bytes; top.in_valid = 0; }
        }
        total_cycles += guard;
        if (getenv("FRAME_CYC"))
            printf("frame %zu (%s): %ld cycles\n", f,
                   e.sh.is_p ? "P" : "I", guard);
        if (top.err || !top.frame_done) {
            printf("[FAIL] frame %zu %s after %ld cycles\n", f,
                   top.err ? "err" : "timeout", guard);
            fails++;
            break;
        }

        // compare the cropped region against the golden frame f
        const uint8_t *gy = gd.y_plane + (size_t)f * W * H;
        const uint8_t *gu = gd.cb_plane + (size_t)f * (W / 2) * (H / 2);
        const uint8_t *gv = gd.cr_plane + (size_t)f * (W / 2) * (H / 2);
        for (int y = 0; y < H && fails < 5; y++)
            for (int x = 0; x < W && fails < 5; x++)
                if (fy[y * FW + x] != gy[y * W + x]) {
                    printf("[FAIL] f%zu Y(%d,%d) rtl=%d c=%d\n", f, x, y,
                           fy[y * FW + x], gy[y * W + x]);
                    fails++;
                }
        for (int y = 0; y < H / 2 && fails < 5; y++)
            for (int x = 0; x < W / 2 && fails < 5; x++) {
                if (fu[y * CWp + x] != gu[y * (W / 2) + x]) {
                    printf("[FAIL] f%zu U(%d,%d) rtl=%d c=%d\n", f, x, y,
                           fu[y * CWp + x], gu[y * (W / 2) + x]);
                    fails++;
                }
                if (fv[y * CWp + x] != gv[y * (W / 2) + x]) {
                    printf("[FAIL] f%zu V(%d,%d) rtl=%d c=%d\n", f, x, y,
                           fv[y * CWp + x], gv[y * (W / 2) + x]);
                    fails++;
                }
            }

        // writeback: this frame becomes the next frame's reference
        ry = fy;
        ru = fu;
        rv = fv;
    }

    size_t nf = ents.size();
    h264_free(&gd);
    if (!fails) {
        printf("[PASS] h264_core P: %zu frames %dx%d bit-exact "
               "(writeback loop, %ld cycles)\n", nf, W, H, total_cycles);
        return 0;
    }
    return 1;
}
