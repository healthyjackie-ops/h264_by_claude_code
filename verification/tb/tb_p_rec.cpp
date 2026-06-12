// P-R3d differential: p_rec_top (parse + mv_pred + MC + reconstruct)
// vs the C model's P reconstruction layer.
//   usage: Vp_rec_top <stream.264> <prec.dump> <ref.dump>
// prec.dump = H264_RTL_DUMP_PREC (384B/MB pixels at mb_done)
// ref.dump  = H264_RTL_DUMP_REF (first gated P slice's list0[0] planes)
// The bench owns the reference frame and answers row reads with clamp
// semantics, one response per cycle (the silicon DDR contract).
#include <cstdio>
#include <cstring>
#include <vector>
#include <algorithm>

#include "Vp_rec_top.h"
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
int clampi(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}
}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) {
        printf("usage: %s <stream.264> <prec.dump> <ref.dump>\n", argv[0]);
        return 1;
    }
    auto stream = rd(argv[1]);
    auto db = rd(argv[2]);
    auto rf = rd(argv[3]);
    if (stream.empty() || db.size() % 384 || rf.size() < 4) {
        printf("[SKIP] inputs (%zu prec bytes, %zu ref)\n", db.size(),
               rf.size());
        return 1;
    }
    size_t nrec = db.size() / 384;

    // reference planes
    int rw = rf[0] | (rf[1] << 8);     // mb_w
    int rh = rf[2] | (rf[3] << 8);     // mb_h
    int LW = rw * 16, LH = rh * 16, CW = rw * 8, CH = rh * 8;
    if (rf.size() != (size_t)4 + (size_t)LW * LH + 2u * CW * CH) {
        printf("[SKIP] ref size mismatch\n");
        return 1;
    }
    const uint8_t *refY = rf.data() + 4;
    const uint8_t *refU = refY + (size_t)LW * LH;
    const uint8_t *refV = refU + (size_t)CW * CH;

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
        if (n.type == 7) parse_sps(&bs, &sps, &errc);
        else if (n.type == 8) parse_pps(&bs, &pps, &sps, &errc);
        else if (n.type == 1 || n.type == 5) {
            if (parse_slice_header(&bs, &sps, &pps, n.type, n.ref_idc,
                                   &sh, &errc)) {
                nal_free(&n);
                continue;
            }
            if (sh.is_p && !pps.entropy_coding_mode &&
                sh.num_ref_l0 == 1 && !pps.transform_8x8 &&
                !pps.weighted_pred) {
                rbsp.assign(n.rbsp, n.rbsp + n.size);
                for (int pi = 0; pi < 8; pi++) rbsp.push_back(0);
                sd_byte = bs.byte;
                sd_bit = bs.bit;
                found = true;
                nal_free(&n);
                break;
            }
        }
        nal_free(&n);
    }
    if (!found) { printf("[SKIP] no P slice\n"); return 1; }
    if ((int)sps.mb_width != rw || (int)sps.mb_height != rh) {
        printf("[SKIP] ref dims mismatch stream\n");
        return 1;
    }

    size_t nmb = (size_t)sps.mb_width * sps.mb_height;
    if (nrec < nmb) { printf("[SKIP] dump too small\n"); return 1; }

    Vp_rec_top top;
    auto tick = [&] {
        // answer a pending row read before the edge
        top.mc_rsp_valid = 0;
        if (top.mc_req_valid) {
            int rx = (int16_t)((uint16_t)top.mc_req_x << 3) >> 3;
            int ry = (int16_t)((uint16_t)top.mc_req_y << 4) >> 4;
            int w = top.mc_req_w;
            const uint8_t *pl =
                (top.mc_req_plane == 0) ? refY
                : (top.mc_req_plane == 1) ? refU : refV;
            int pw = top.mc_req_plane ? CW : LW;
            int ph = top.mc_req_plane ? CH : LH;
            uint8_t px[9];
            for (int i = 0; i < w; i++)
                px[i] = pl[(size_t)clampi(ry, 0, ph - 1) * pw +
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
    };
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
    top.cfg_qp = (uint8_t)sh.slice_qp;
    top.cfg_cqp_off = (uint8_t)((int8_t)pps.chroma_qp_offset & 0x3F);
    top.cfg_is_p = 1;

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

    size_t gi = 0;
    int fails = 0;
    long guard = 0;
    int prev_valid = 0;
    while (gi < nmb && !top.err && guard++ < 30000000) {
        pump();
        tick();
        if (top.in_valid) { fi += top.in_bytes; top.in_valid = 0; }
        if (top.rec_valid && !prev_valid) {
            const uint8_t *g = db.data() + gi * 384;
            int mbe = 0;
            for (int i = 0; i < 256 && mbe < 3; i++)
                if (top.rec_y[i] != g[i]) {
                    printf("[FAIL] MB %zu (%d,%d) Y[%d,%d] rtl=%d c=%d\n",
                           gi, (int)top.rec_x, (int)top.rec_yc,
                           i % 16, i / 16, (int)top.rec_y[i], g[i]);
                    mbe++;
                }
            for (int i = 0; i < 64 && mbe < 3; i++)
                if (top.rec_u[i] != g[256 + i]) {
                    printf("[FAIL] MB %zu U[%d,%d] rtl=%d c=%d\n", gi,
                           i % 8, i / 8, (int)top.rec_u[i], g[256 + i]);
                    mbe++;
                }
            for (int i = 0; i < 64 && mbe < 3; i++)
                if (top.rec_v[i] != g[320 + i]) {
                    printf("[FAIL] MB %zu V[%d,%d] rtl=%d c=%d\n", gi,
                           i % 8, i / 8, (int)top.rec_v[i], g[320 + i]);
                    mbe++;
                }
            fails += mbe;
            gi++;
            if (fails >= 9) break;
        }
        prev_valid = top.rec_valid;
    }

    if (top.err) { printf("[FAIL] err at MB %zu\n", gi); return 1; }
    if (gi != nmb) {
        printf("[FAIL] MB count %zu/%zu (guard=%ld)\n", gi, nmb, guard);
        return 1;
    }
    if (!fails) {
        printf("[PASS] P recon: %zu MBs pixel bit-exact vs dump\n", gi);
        return 0;
    }
    return 1;
}
