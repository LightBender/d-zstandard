/**
 * The D-native Zstandard wrapper package.
 *
 * Importing `zstd` brings in the high-level, D-native API together with its
 * `Result` type and helpers:
 *
 * $(UL
 *   $(LI `zstd.result` — the `Result` type and `ZstdError` record,)
 *   $(LI `zstd.core` — version and compression-level helpers,)
 *   $(LI `zstd.compress` — one-shot `compress` and the `Compressor` context,)
 *   $(LI `zstd.decompress` — one-shot `decompress` and the `Decompressor` context, and)
 *   $(LI `zstd.dictionary` — dictionary training and digested dictionary handles.)
 * )
 *
 * The raw C API remains available separately through `etc.c.zstd`.
 *
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module zstd;

public import zstd.result;
public import zstd.core;
public import zstd.compress;
public import zstd.decompress;
public import zstd.dictionary;

@safe unittest
{
    // Round-trip: one-shot compress then decompress returns the original data.
    ubyte[] original = cast(ubyte[]) "The quick brown fox jumps over the lazy dog. ".dup;
    foreach (_; 0 .. 8)
        original ~= original;

    auto compressed = compress(original, 9);
    assert(compressed.isOk);
    assert(compressed.value.length < original.length);

    auto restored = decompress(compressed.value);
    assert(restored.isOk);
    assert(restored.value == original);
}

@safe unittest
{
    // Reusable contexts round-trip.
    ubyte[] data = cast(ubyte[]) "repeat repeat repeat repeat repeat".dup;

    auto cr = createCompressor();
    assert(cr.isOk);
    assert(cr.value.setCompressionLevel(3).isOk);
    auto compressed = cr.value.compress(data);
    assert(compressed.isOk);

    auto dr = createDecompressor();
    assert(dr.isOk);
    auto restored = dr.value.decompress(compressed.value);
    assert(restored.isOk);
    assert(restored.value == data);
}

@safe unittest
{
    // Decompressing garbage yields an error, not a crash.
    ubyte[] garbage = [0, 1, 2, 3, 4, 5, 6, 7];
    auto result = decompress(garbage);
    assert(result.isErr);
    assert(result.message.length > 0);
}
