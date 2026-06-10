/* golden_compare — decode .264 with the C model and byte-compare against
 * the sibling .yuv golden (ffmpeg yuv420p output, written at vector-gen
 * time). Mirrors jpeg_by_claude_code's golden_compare semantics:
 *   golden_compare v1.264 v2.264 ...          PASS iff bit-exact
 *   golden_compare --expect-fail bad.264 ...  PASS iff decode rejects
 * Exit 0 when all pass, 3 otherwise. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "decoder.h"

static uint8_t *read_file(const char *p, size_t *s) {
    FILE *f = fopen(p, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) { fclose(f); return NULL; }
    size_t un = (size_t)n;
    uint8_t *b = (uint8_t *)malloc(un ? un : 1);
    if (fread(b, 1, un, f) != un) { free(b); fclose(f); return NULL; }
    fclose(f);
    *s = un;
    return b;
}

static int yuv_path(const char *p264, char *out, size_t cap) {
    size_t n = strlen(p264);
    if (n + 1 > cap || n < 4) return -1;
    memcpy(out, p264, n + 1);
    memcpy(out + n - 4, ".yuv", 5);
    return 0;
}

int main(int argc, char **argv) {
    int expect_fail = 0;
    int first = 1;
    if (argc >= 2 && strcmp(argv[1], "--expect-fail") == 0) {
        expect_fail = 1;
        first = 2;
    }
    if (argc < first + 1) {
        fprintf(stderr, "usage: %s [--expect-fail] <v1.264> [v2.264 ...]\n", argv[0]);
        return 1;
    }
    int total = 0, pass = 0, fail = 0, skip = 0;
    int worst_y = 0, worst_c = 0;

    for (int a = first; a < argc; a++) {
        total++;
        size_t sz;
        uint8_t *buf = read_file(argv[a], &sz);
        if (!buf) { fprintf(stderr, "[SKIP] %s: read fail\n", argv[a]); skip++; continue; }

        h264_decoded_t ours;
        int rc = h264_decode(buf, sz, &ours);

        if (expect_fail) {
            if (rc != 0) {
                printf("[PASS] %s rejected err=0x%X\n", argv[a], ours.err);
                pass++;
            } else {
                printf("[FAIL] %s decoded %ux%u — corrupted input must be rejected\n",
                       argv[a], ours.width, ours.height);
                fail++;
            }
            h264_free(&ours);
            free(buf);
            continue;
        }

        if (rc != 0) {
            fprintf(stderr, "[FAIL] %s: our decode err=0x%X\n", argv[a], ours.err);
            fail++;
            h264_free(&ours);
            free(buf);
            continue;
        }

        char gp[1024];
        size_t gsz;
        uint8_t *gold = NULL;
        if (yuv_path(argv[a], gp, sizeof(gp)) == 0) gold = read_file(gp, &gsz);
        if (!gold) {
            fprintf(stderr, "[SKIP] %s: missing golden %s\n", argv[a], gp);
            skip++;
            h264_free(&ours);
            free(buf);
            continue;
        }

        size_t W = ours.width, H = ours.height;
        size_t ysz = W * H, csz = (W >> 1) * (H >> 1);
        size_t fsz = ysz + 2 * csz;
        if (gsz != fsz * ours.nframes) {
            fprintf(stderr,
                    "[FAIL] %s: golden size %zu != %zu (W=%zu H=%zu n=%u)\n",
                    argv[a], gsz, fsz * ours.nframes, W, H, ours.nframes);
            fail++;
            free(gold);
            h264_free(&ours);
            free(buf);
            continue;
        }

        int dy = 0, dc = 0;
        for (uint32_t fr = 0; fr < ours.nframes; fr++) {
            const uint8_t *gf = gold + (size_t)fr * fsz;
            for (size_t i = 0; i < ysz; i++) {
                int d = (int)ours.y_plane[fr * ysz + i] - (int)gf[i];
                if (d < 0) d = -d;
                if (d > dy) dy = d;
            }
            for (size_t i = 0; i < csz; i++) {
                int d1 = (int)ours.cb_plane[fr * csz + i] - (int)gf[ysz + i];
                int d2 = (int)ours.cr_plane[fr * csz + i] - (int)gf[ysz + csz + i];
                if (d1 < 0) d1 = -d1;
                if (d2 < 0) d2 = -d2;
                if (d1 > dc) dc = d1;
                if (d2 > dc) dc = d2;
            }
        }
        if (dy == 0 && dc == 0) {
            printf("[PASS] %s %zux%zu x%u exact\n", argv[a], W, H, ours.nframes);
            pass++;
        } else {
            printf("[FAIL] %s %zux%zu x%u maxDiff Y=%d C=%d\n",
                   argv[a], W, H, ours.nframes, dy, dc);
            fail++;
        }
        if (dy > worst_y) worst_y = dy;
        if (dc > worst_c) worst_c = dc;
        free(gold);
        h264_free(&ours);
        free(buf);
    }
    printf("\n=== SUMMARY ===\n");
    printf("Total: %d  Pass: %d  Fail: %d  Skip: %d\n", total, pass, fail, skip);
    printf("Worst diff: Y=%d  C=%d\n", worst_y, worst_c);
    return (fail == 0 && skip == 0) ? 0 : 3;
}
