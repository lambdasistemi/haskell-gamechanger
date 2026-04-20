/*
 * Thin shim around liblzma's legacy `.lzma` alone encoder.
 *
 * The Hackage `lzma` package only exposes the modern `.xz` format.
 * The GameChanger wallet speaks `.lzma` alone (13-byte header + raw
 * LZMA1 stream). This shim calls `lzma_alone_encoder` directly,
 * which produces the exact byte layout the wallet accepts.
 *
 * Linked against the same liblzma the `lzma` package pulls in — no
 * new system dependency.
 */
#include <lzma.h>
#include <stddef.h>
#include <stdint.h>

/*
 * Compress `src` (length `src_sz`) into `dst` using the legacy `.lzma`
 * alone encoder with preset level 6 extreme (dict size 32 MiB = the
 * observed wallet value, lc=3 lp=0 pb=2 — liblzma defaults).
 *
 * On entry `*dst_sz` holds the capacity of `dst`. On success it is
 * overwritten with the actual compressed size.
 *
 * Returns 0 on success, a negative number on failure:
 *   -1  preset or encoder initialisation failed
 *   -2  compression step failed
 *   -3  output buffer too small
 */
int gc_lzma_alone_compress(
    const uint8_t *src, size_t src_sz,
    uint8_t *dst, size_t *dst_sz)
{
    lzma_options_lzma opt;
    if (lzma_lzma_preset(&opt, LZMA_PRESET_DEFAULT)) {
        return -1;
    }
    opt.dict_size = 1u << 25; /* 32 MiB — matches observed wallet bytes */

    lzma_stream strm = LZMA_STREAM_INIT;
    if (lzma_alone_encoder(&strm, &opt) != LZMA_OK) {
        return -1;
    }

    strm.next_in  = src;
    strm.avail_in = src_sz;
    strm.next_out = dst;
    strm.avail_out = *dst_sz;

    lzma_ret ret = lzma_code(&strm, LZMA_FINISH);
    if (ret != LZMA_STREAM_END) {
        lzma_end(&strm);
        return (ret == LZMA_BUF_ERROR) ? -3 : -2;
    }

    *dst_sz = strm.total_out;
    lzma_end(&strm);
    return 0;
}

/*
 * Upper bound on compressed size for a buffer of `src_sz` bytes.
 * liblzma's worst-case expansion plus a safety margin for the
 * 13-byte `.lzma` header.
 */
size_t gc_lzma_alone_compress_bound(size_t src_sz)
{
    return lzma_stream_buffer_bound(src_sz) + 64;
}
