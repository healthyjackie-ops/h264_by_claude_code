#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "../src/bitstream.h"
#include "../src/nal.h"

static void test_u(void) {
    const uint8_t d[] = { 0xA5, 0x3C };           /* 1010 0101 0011 1100 */
    bs_t bs;
    bs_init(&bs, d, sizeof(d));
    assert(bs_u1(&bs) == 1);
    assert(bs_u(&bs, 3) == 2);                    /* 010 */
    assert(bs_u(&bs, 4) == 5);                    /* 0101 */
    assert(bs_u(&bs, 8) == 0x3C);
    assert(!bs.error);
    (void)bs_u1(&bs);
    assert(bs.error);                             /* overread flagged */
    printf("  test_u PASS\n");
}

static void test_ue_se(void) {
    /* ue codes back-to-back: 0:'1' 1:'010' 2:'011' 3:'00100' 6:'00111'
     * → 1 010 011 00100 00111 (17 bits) + pad 0s */
    const uint8_t d[] = { 0xA6, 0x43, 0x80 };     /* 10100110 01000011 1 */
    bs_t bs;
    bs_init(&bs, d, sizeof(d));
    assert(bs_ue(&bs) == 0);
    assert(bs_ue(&bs) == 1);
    assert(bs_ue(&bs) == 2);
    assert(bs_ue(&bs) == 3);
    assert(bs_ue(&bs) == 6);
    assert(!bs.error);

    /* se mapping: codeNum 0→0, 1→1, 2→−1, 3→2, 4→−2 */
    bs_init(&bs, d, sizeof(d));
    assert(bs_se(&bs) == 0);
    assert(bs_se(&bs) == 1);
    assert(bs_se(&bs) == -1);
    assert(bs_se(&bs) == 2);
    assert(bs_se(&bs) == -3);                     /* ue 6 → se −3 */
    printf("  test_ue_se PASS\n");
}

static void test_more_rbsp(void) {
    /* one byte 0x80: only the stop bit → no more data */
    const uint8_t d1[] = { 0x80 };
    bs_t bs;
    bs_init(&bs, d1, sizeof(d1));
    assert(bs_more_rbsp_data(&bs) == 0);
    /* 0xC0: bit '1' then stop bit → one data bit available */
    const uint8_t d2[] = { 0xC0 };
    bs_init(&bs, d2, sizeof(d2));
    assert(bs_more_rbsp_data(&bs) == 1);
    assert(bs_u1(&bs) == 1);
    assert(bs_more_rbsp_data(&bs) == 0);
    printf("  test_more_rbsp PASS\n");
}

static void test_nal_split(void) {
    /* Two NALs: 4-byte SC + SPS hdr 0x67, payload with EPB 00 00 03 01;
     * then 3-byte SC + IDR hdr 0x65. */
    const uint8_t d[] = {
        0x00, 0x00, 0x00, 0x01, 0x67, 0xAA, 0x00, 0x00, 0x03, 0x01, 0xBB,
        0x00, 0x00, 0x01, 0x65, 0x11, 0x22, 0x80
    };
    size_t pos = 0;
    nal_t n;
    assert(nal_next(d, sizeof(d), &pos, &n) == 0);
    assert(n.type == NAL_SPS && n.ref_idc == 3);
    assert(n.size == 5);                          /* AA 00 00 01 BB — EPB dropped */
    const uint8_t want[] = { 0xAA, 0x00, 0x00, 0x01, 0xBB };
    assert(memcmp(n.rbsp, want, 5) == 0);
    nal_free(&n);

    assert(nal_next(d, sizeof(d), &pos, &n) == 0);
    assert(n.type == NAL_SLICE_IDR);
    assert(n.size == 3 && n.rbsp[0] == 0x11 && n.rbsp[2] == 0x80);
    nal_free(&n);

    assert(nal_next(d, sizeof(d), &pos, &n) == -1);
    printf("  test_nal_split PASS\n");
}

int main(void) {
    printf("== test_bitstream ==\n");
    test_u();
    test_ue_se();
    test_more_rbsp();
    test_nal_split();
    return 0;
}
