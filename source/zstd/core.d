/**
 * Shared helpers for the D-native Zstandard wrapper.
 *
 * Provides version queries, compression-level introspection, and the
 * compression bound calculation, all returning D-native types.
 *
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module zstd.core;

import etc.c.zstd.zstd;

/// Runtime library version as a packed integer (MAJOR*10000 + MINOR*100 + RELEASE).
uint versionNumber() @trusted nothrow @nogc
{
    return ZSTD_versionNumber();
}

/// Runtime library version as a string, e.g. `"1.5.7"`.
string versionString() @trusted nothrow
{
    import std.string : fromStringz;

    return fromStringz(ZSTD_versionString()).idup;
}

/**
 * Maximum compressed size in the worst-case single-pass scenario.
 *
 * Providing a destination buffer of at least this size guarantees that a
 * one-shot compression has enough room to succeed.
 */
size_t compressBound(size_t srcSize) @trusted nothrow @nogc
{
    return ZSTD_compressBound(srcSize);
}

/// Minimum (most negative) compression level supported by the library.
int minCompressionLevel() @trusted nothrow @nogc
{
    return ZSTD_minCLevel();
}

/// Maximum compression level supported by the library.
int maxCompressionLevel() @trusted nothrow @nogc
{
    return ZSTD_maxCLevel();
}

/// Default compression level (`ZSTD_CLEVEL_DEFAULT`).
int defaultCompressionLevel() @trusted nothrow @nogc
{
    return ZSTD_defaultCLevel();
}

@safe unittest
{
    assert(versionNumber() > 0);
    assert(versionString().length > 0);
    assert(compressBound(0) > 0);
    assert(maxCompressionLevel() >= defaultCompressionLevel());
    assert(defaultCompressionLevel() >= minCompressionLevel());
}
