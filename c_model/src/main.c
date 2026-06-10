#include "decoder.h"

#include <stdio.h>
#include <stdlib.h>

static uint8_t *read_file(const char *path, size_t *size) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) { fclose(f); return NULL; }
    size_t un = (size_t)n;
    uint8_t *buf = (uint8_t *)malloc(un ? un : 1);
    if (fread(buf, 1, un, f) != un) { free(buf); fclose(f); return NULL; }
    fclose(f);
    *size = un;
    return buf;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <in.264> [out.yuv]\n", argv[0]);
        return 1;
    }
    size_t size;
    uint8_t *data = read_file(argv[1], &size);
    if (!data) { perror("read"); return 1; }

    h264_decoded_t dec;
    int rc = h264_decode(data, size, &dec);
    if (rc != 0) {
        fprintf(stderr, "decode error: 0x%X\n", dec.err);
        h264_free(&dec);
        free(data);
        return 2;
    }
    fprintf(stderr, "decoded %ux%u x%u frames\n", dec.width, dec.height,
            dec.nframes);

    if (argc >= 3) {
        FILE *f = fopen(argv[2], "wb");
        if (f) {
            size_t ys = (size_t)dec.width * dec.height;
            size_t cs = ((size_t)dec.width >> 1) * ((size_t)dec.height >> 1);
            for (uint32_t fr = 0; fr < dec.nframes; fr++) {
                fwrite(dec.y_plane + fr * ys, 1, ys, f);
                fwrite(dec.cb_plane + fr * cs, 1, cs, f);
                fwrite(dec.cr_plane + fr * cs, 1, cs, f);
            }
            fclose(f);
        }
    }
    h264_free(&dec);
    free(data);
    return 0;
}
