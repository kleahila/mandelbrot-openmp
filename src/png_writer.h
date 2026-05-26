
#ifndef PNG_WRITER_H
#define PNG_WRITER_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* ── CRC32 ──────────────────────────────────────────────────────────── */

static uint32_t png__crc_table[256];
static int png__crc_ready = 0;

static void png__make_crc_table(void)
{
    for (int n = 0; n < 256; n++)
    {
        uint32_t c = (uint32_t)n;
        for (int k = 0; k < 8; k++)
            c = (c & 1) ? 0xedb88320u ^ (c >> 1) : c >> 1;
        png__crc_table[n] = c;
    }
    png__crc_ready = 1;
}

static uint32_t png__crc32(const unsigned char *buf, int len)
{
    if (!png__crc_ready)
        png__make_crc_table();
    uint32_t c = 0xffffffffu;
    for (int i = 0; i < len; i++)
        c = png__crc_table[(c ^ buf[i]) & 0xff] ^ (c >> 8);
    return c ^ 0xffffffffu;
}

/* ── Adler32 ────────────────────────────────────────────────────────── */

static uint32_t png__adler32(const unsigned char *buf, int len)
{
    uint32_t s1 = 1, s2 = 0;
    for (int i = 0; i < len; i++)
    {
        s1 = (s1 + buf[i]) % 65521u;
        s2 = (s2 + s1) % 65521u;
    }
    return (s2 << 16) | s1;
}

/* ── Helpers ────────────────────────────────────────────────────────── */

static void png__write_u32be(FILE *fp, uint32_t v)
{
    fputc((v >> 24) & 0xff, fp);
    fputc((v >> 16) & 0xff, fp);
    fputc((v >> 8) & 0xff, fp);
    fputc(v & 0xff, fp);
}

static void png__write_chunk(FILE *fp, const char type[4],
                             const unsigned char *data, uint32_t len)
{
    png__write_u32be(fp, len);
    fwrite(type, 1, 4, fp);
    if (data && len)
        fwrite(data, 1, len, fp);

    /* CRC covers type + data */
    unsigned char crc_buf[4];
    memcpy(crc_buf, type, 4);
    uint32_t c = png__crc32(crc_buf, 4);
    if (!png__crc_ready)
        png__make_crc_table();
    c ^= 0xffffffffu;
    if (data && len)
    {
        for (uint32_t i = 0; i < len; i++)
            c = png__crc_table[(c ^ data[i]) & 0xff] ^ (c >> 8);
    }
    c ^= 0xffffffffu;
    png__write_u32be(fp, c);
}

/* ── Main API ───────────────────────────────────────────────────────── */

/*
 * write_png - Save RGB image buffer as a PNG file.
 *
 * filename : output path (e.g. "output.png")
 * width    : image width  in pixels
 * height   : image height in pixels
 * rgb      : packed RGB bytes, row-major, 3 bytes per pixel
 *
 * Returns 0 on success, -1 on error.
 */
static int write_png(const char *filename, int width, int height,
                     const unsigned char *rgb)
{
    /* Build raw filtered data: one filter-type byte (0 = None) per row */
    int row_stride = width * 3;
    int row_bytes = 1 + row_stride; /* filter byte + RGB */
    int raw_len = height * row_bytes;

    unsigned char *raw = (unsigned char *)malloc(raw_len);
    if (!raw)
        return -1;

    for (int y = 0; y < height; y++)
    {
        raw[y * row_bytes] = 0; /* filter: None */
        memcpy(&raw[y * row_bytes + 1],
               &rgb[y * row_stride], row_stride);
    }

    /* Adler32 of raw data (needed for zlib footer) */
    uint32_t adler = png__adler32(raw, raw_len);

    /* Pack raw data into deflate "stored" blocks (max 65535 bytes each) */
    int num_blocks = (raw_len + 65534) / 65535;
    int deflate_len = raw_len + num_blocks * 5;

    unsigned char *deflate_data = (unsigned char *)malloc(deflate_len);
    if (!deflate_data)
    {
        free(raw);
        return -1;
    }

    int dpos = 0, rpos = 0;
    for (int b = 0; b < num_blocks; b++)
    {
        int blen = raw_len - rpos;
        if (blen > 65535)
            blen = 65535;
        int is_last = (rpos + blen >= raw_len) ? 1 : 0;

        deflate_data[dpos++] = (unsigned char)is_last; /* BFINAL | BTYPE=00 */
        deflate_data[dpos++] = (unsigned char)(blen & 0xff);
        deflate_data[dpos++] = (unsigned char)((blen >> 8) & 0xff);
        deflate_data[dpos++] = (unsigned char)((~blen) & 0xff);
        deflate_data[dpos++] = (unsigned char)((~blen >> 8) & 0xff);
        memcpy(&deflate_data[dpos], &raw[rpos], blen);
        dpos += blen;
        rpos += blen;
    }
    free(raw);

    /* Wrap in zlib stream: 2-byte header + deflate blocks + 4-byte adler32 */
    int zlib_len = 2 + deflate_len + 4;
    unsigned char *zlib_data = (unsigned char *)malloc(zlib_len);
    if (!zlib_data)
    {
        free(deflate_data);
        return -1;
    }

    int zpos = 0;
    zlib_data[zpos++] = 0x78; /* CMF: deflate, window size = 32768 */
    zlib_data[zpos++] = 0x01; /* FLG: no dict, check bits           */
    memcpy(&zlib_data[zpos], deflate_data, deflate_len);
    zpos += deflate_len;
    free(deflate_data);
    zlib_data[zpos++] = (unsigned char)((adler >> 24) & 0xff);
    zlib_data[zpos++] = (unsigned char)((adler >> 16) & 0xff);
    zlib_data[zpos++] = (unsigned char)((adler >> 8) & 0xff);
    zlib_data[zpos++] = (unsigned char)(adler & 0xff);

    /* Write PNG file */
    FILE *fp = fopen(filename, "wb");
    if (!fp)
    {
        free(zlib_data);
        return -1;
    }

    /* Signature */
    const unsigned char sig[8] = {137, 80, 78, 71, 13, 10, 26, 10};
    fwrite(sig, 1, 8, fp);

    /* IHDR chunk */
    unsigned char ihdr[13];
    ihdr[0] = (unsigned char)((width >> 24) & 0xff);
    ihdr[1] = (unsigned char)((width >> 16) & 0xff);
    ihdr[2] = (unsigned char)((width >> 8) & 0xff);
    ihdr[3] = (unsigned char)(width & 0xff);
    ihdr[4] = (unsigned char)((height >> 24) & 0xff);
    ihdr[5] = (unsigned char)((height >> 16) & 0xff);
    ihdr[6] = (unsigned char)((height >> 8) & 0xff);
    ihdr[7] = (unsigned char)(height & 0xff);
    ihdr[8] = 8;  /* bit depth per channel */
    ihdr[9] = 2;  /* color type: RGB truecolor */
    ihdr[10] = 0; /* compression method */
    ihdr[11] = 0; /* filter method */
    ihdr[12] = 0; /* interlace: none */
    png__write_chunk(fp, "IHDR", ihdr, 13);

    /* IDAT chunk (zlib stream) */
    png__write_chunk(fp, "IDAT", zlib_data, (uint32_t)zlib_len);
    free(zlib_data);

    /* IEND chunk */
    png__write_chunk(fp, "IEND", NULL, 0);

    fclose(fp);
    return 0;
}

#endif /* PNG_WRITER_H */
