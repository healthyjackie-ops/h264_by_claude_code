// R3b full-chain differential: h264_top vs the C model's final .yuv.
// .264 in, frame out — headers parsed with linked C objects, slice RBSP
// streamed into the RTL, crop window compared at the end.
//   usage: Vh264_top <stream.264> <golden.yuv>
#include <cstdio>
#include <cstring>
#include <vector>

#include "Vh264_top.h"
#include "verilated.h"

extern "C" {
#include "bitstream.h"
#include "nal.h"
#include "params.h"
#include "slice.h"
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
}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) {
        printf("usage: %s <stream.264> <golden.yuv>\n", argv[0]);
        return 1;
    }
    auto stream = rd(argv[1]);
    auto gold = rd(argv[2]);
    if (stream.empty() || gold.empty()) {
        printf("[SKIP] inputs\n");
        return 1;
    }

    sps_t sps;
    pps_t pps;
    slice_hdr_t sh;
    memset(&sps, 0, sizeof(sps));
    memset(&pps, 0, sizeof(pps));
    nal_t n;
    size_t pos = 0;
    uint32_t errc = 0;
    std::vector<uint8_t> rbsp;
    size_t sd_byte = 0;
    int sd_bit = 0;
    bool found = false;
    while (nal_next(stream.data(), stream.size(), &pos, &n) == 0) {
        bs_t bs;
        bs_init(&bs, n.rbsp, n.size);
        if (n.type == 7) {
            if (parse_sps(&bs, &sps, &errc)) return 1;
        } else if (n.type == 8) {
            if (parse_pps(&bs, &pps, &sps, &errc)) return 1;
        } else if (n.type == 5 || n.type == 1) {
            if (parse_slice_header(&bs, &sps, &pps, n.type, n.ref_idc,
                                   &sh, &errc)) return 1;
            if (pps.entropy_coding_mode || sh.is_p || sh.is_b) {
                printf("[SKIP] out of subset\n");
                return 1;
            }
            rbsp.assign(n.rbsp, n.rbsp + n.size);
            for (int pi = 0; pi < 8; pi++) rbsp.push_back(0);
            sd_byte = bs.byte;
            sd_bit = bs.bit;
            found = true;
            nal_free(&n);
            break;
        }
        nal_free(&n);
    }
    if (!found) { printf("[SKIP] no slice\n"); return 1; }

    int W = (int)(sps.mb_width * 16 - 2 * (sps.crop_l + sps.crop_r));
    int H = (int)(sps.mb_height * 16 - 2 * (sps.crop_t + sps.crop_b));
    int deblock = (sh.disable_deblock != 1);
    static const int MAXW = 320;

    Vh264_top top;
    auto tick = [&] {
        top.clk = 0;
        top.eval();
        top.clk = 1;
        top.eval();
    };
    top.rst_n = 0;
    top.in_valid = 0;
    top.start = 0;
    top.align_valid = 0;
    tick();
    top.rst_n = 1;
    tick();

    top.cfg_mb_w = (uint8_t)sps.mb_width;
    top.cfg_mb_h = (uint8_t)sps.mb_height;
    top.cfg_qp = (uint8_t)sh.slice_qp;
    top.cfg_cqp_off = (uint8_t)(pps.chroma_qp_offset & 0x3F);
    top.cfg_a_off = (uint8_t)(sh.alpha_c0_offset & 0x3F);
    top.cfg_b_off = (uint8_t)(sh.beta_offset & 0x3F);
    top.cfg_deblock = deblock;

    size_t fi = sd_byte;
    auto pump = [&] {
        top.in_valid = 0;
        if (fi < rbsp.size() && top.in_ready) {
            int nb = (int)std::min<size_t>(4, rbsp.size() - fi);
            uint32_t w = 0;
            for (int k = 0; k < nb; k++)
                w |= (uint32_t)rbsp[fi + k] << (24 - k * 8);
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
    if (sd_bit) {
        top.align_valid = 1;
        top.align_bits = (uint8_t)sd_bit;
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
    if (top.err || !top.frame_done) {
        printf("[FAIL] %s after %ld cycles\n",
               top.err ? "err" : "timeout", guard);
        return 1;
    }

    auto px = [&](int plane, int addr) -> uint8_t {
        top.rd_plane = (uint8_t)plane;
        top.rd_addr = (uint32_t)addr;
        top.eval();
        return top.rd_data;
    };

    const uint8_t *gy = gold.data();
    const uint8_t *gu = gy + W * H;
    const uint8_t *gv = gu + (W / 2) * (H / 2);
    int fails = 0;
    for (int y = 0; y < H && fails < 5; y++)
        for (int x = 0; x < W && fails < 5; x++)
            if (px(0, y * MAXW + x) != gy[y * W + x]) {
                printf("[FAIL] Y(%d,%d) rtl=%d c=%d\n", x, y,
                       px(0, y * MAXW + x), gy[y * W + x]);
                fails++;
            }
    for (int y = 0; y < H / 2 && fails < 5; y++)
        for (int x = 0; x < W / 2 && fails < 5; x++) {
            if (px(1, y * (MAXW / 2) + x) != gu[y * (W / 2) + x]) {
                printf("[FAIL] U(%d,%d)\n", x, y);
                fails++;
            }
            if (px(2, y * (MAXW / 2) + x) != gv[y * (W / 2) + x]) {
                printf("[FAIL] V(%d,%d)\n", x, y);
                fails++;
            }
        }

    if (!fails) {
        printf("[PASS] h264_top: %dx%d frame bit-exact (.264 -> yuv, "
               "%ld cycles)\n", W, H, guard);
        return 0;
    }
    return 1;
}
