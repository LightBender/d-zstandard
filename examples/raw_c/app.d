/**
 * Using the raw C API directly through the `etc.c.zstd` bindings, without the
 * D-native wrapper. This mirrors how you would call zstd from C.
 *
 * Build & run: dub run :raw-c
 */
module examples.raw_c.app;

import std.stdio;
import std.string : fromStringz;
import etc.c.zstd.zstd;

void main()
{
    writeln("zstd version: ", fromStringz(ZSTD_versionString()));

    ubyte[] src = cast(ubyte[]) "The raw C API, called directly from D.".dup;

    // Compress.
    const bound = ZSTD_compressBound(src.length);
    auto dst = new ubyte[bound];
    const csize = ZSTD_compress(dst.ptr, dst.length, src.ptr, src.length, 3);
    if (ZSTD_isError(csize))
    {
        stderr.writeln("compress error: ", fromStringz(ZSTD_getErrorName(csize)));
        return;
    }

    // Decompress, using the frame's stored content size.
    const rsize = ZSTD_getFrameContentSize(dst.ptr, csize);
    auto out_ = new ubyte[cast(size_t) rsize];
    const dsize = ZSTD_decompress(out_.ptr, out_.length, dst.ptr, csize);
    if (ZSTD_isError(dsize))
    {
        stderr.writeln("decompress error: ", fromStringz(ZSTD_getErrorName(dsize)));
        return;
    }

    assert(out_[0 .. dsize] == src);
    writefln("compressed %s -> %s bytes; round-trip ok", src.length, csize);
}
