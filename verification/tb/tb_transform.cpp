// R2a differential test: transform_dec.sv vs c_model transform.o on
// random coefficients across the full qp range. Combinational module —
// drive inputs, eval, compare all four paths.
#include <cstdio>
#include <cstring>
#include <random>

#include "Vtransform_top.h"
#include "verilated.h"

extern "C" {
#include "transform.h"
}

namespace {

void set_flat(uint32_t *flat, int idx, int width_bits, uint64_t v) {
    // helper for packed ports (Verilator exposes wide ports as word arrays)
    int lo = idx * width_bits;
    for (int b = 0; b < width_bits; b++) {
        int bit = lo + b;
        if ((v >> b) & 1) flat[bit >> 5] |= (1u << (bit & 31));
        else flat[bit >> 5] &= ~(1u << (bit & 31));
    }
}

uint64_t get_flat(const uint32_t *flat, int idx, int width_bits) {
    int lo = idx * width_bits;
    uint64_t v = 0;
    for (int b = 0; b < width_bits; b++) {
        int bit = lo + b;
        if ((flat[bit >> 5] >> (bit & 31)) & 1) v |= (1ull << b);
    }
    return v;
}

}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::mt19937 rng(20260611);
    Vtransform_top top;

    int fails = 0;
    const uint8_t flat_w[16] = {16, 16, 16, 16, 16, 16, 16, 16,
                                16, 16, 16, 16, 16, 16, 16, 16};
    for (int trial = 0; trial < 20000 && fails == 0; trial++) {
        int16_t c[16];
        uint8_t pred[16];
        // mix magnitudes: small everyday levels and extremes
        for (int i = 0; i < 16; i++) {
            int mag = (int)(rng() % 3);
            c[i] = (int16_t)((mag == 0) ? (int)(rng() % 7) - 3
                            : (mag == 1) ? (int)(rng() % 201) - 100
                                         : (int)(rng() % 4001) - 2000);
            pred[i] = (uint8_t)(rng() & 0xFF);
        }
        int qp = (int)(rng() % 52);

        for (int i = 0; i < 16; i++) {
            set_flat(top.c_flat.data(), i, 16, (uint16_t)c[i]);
            set_flat(top.pred_flat.data(), i, 8, pred[i]);
        }
        top.qp = (uint8_t)qp;
        top.eval();

        // C references
        int32_t dq[16], ldc[16], cdc[4];
        h264_dequant4x4(c, qp, flat_w, dq);
        h264_luma_dc_dequant(c, qp, 16, ldc);
        int16_t c4[4] = {c[0], c[1], c[2], c[3]};
        h264_chroma_dc_dequant(c4, qp <= 51 ? qp : 51, 16, cdc);
        uint8_t rec[16];
        memcpy(rec, pred, 16);
        // C idct works on a strided dst; 4x4 contiguous = stride 4
        h264_idct4x4_add(rec, 4, dq);

        for (int i = 0; i < 16 && fails == 0; i++) {
            int32_t r = (int32_t)get_flat(top.dq_flat.data(), i, 32);
            if (r != dq[i]) {
                printf("[FAIL] t%d dq[%d] rtl=%d c=%d (qp=%d c=%d)\n",
                       trial, i, r, dq[i], qp, c[i]);
                fails++;
            }
            int32_t l = (int32_t)get_flat(top.ldc_flat.data(), i, 32);
            if (l != ldc[i]) {
                printf("[FAIL] t%d ldc[%d] rtl=%d c=%d (qp=%d)\n",
                       trial, i, l, ldc[i], qp);
                fails++;
            }
            uint8_t o = (uint8_t)get_flat(top.idct_flat.data(), i, 8);
            if (o != rec[i]) {
                printf("[FAIL] t%d idct[%d] rtl=%d c=%d (qp=%d)\n",
                       trial, i, o, rec[i], qp);
                fails++;
            }
        }
        for (int i = 0; i < 4 && fails == 0; i++) {
            int32_t r = (int32_t)get_flat(top.cdc_flat.data(), i, 32);
            if (r != cdc[i]) {
                printf("[FAIL] t%d cdc[%d] rtl=%d c=%d (qp=%d)\n",
                       trial, i, r, cdc[i], qp);
                fails++;
            }
        }
    }

    if (fails == 0) {
        printf("[PASS] transform_dec: 20000 random vectors x 4 paths "
               "bit-exact vs C model\n");
        return 0;
    }
    return 1;
}
