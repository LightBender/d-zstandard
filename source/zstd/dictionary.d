/**
 * D-native dictionary support for Zstandard.
 *
 * Provides dictionary training (`trainDictionary`), digested dictionary handles
 * (`CompressionDictionary` / `DecompressionDictionary`) for efficient reuse, and
 * convenience one-shot dictionary compression/decompression helpers.
 *
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module zstd.dictionary;

import etc.c.zstd.zstd;
import etc.c.zstd.zdict;
import zstd.result;
import zstd.compress : Compressor, createCompressor;
import zstd.decompress : Decompressor, createDecompressor;

/**
 * Trains a dictionary from a set of samples.
 *
 * Params:
 *   samples      = the individual training samples.
 *   dictCapacity = the maximum size of the resulting dictionary (a good default
 *                  is around 100 KiB).
 * Returns: a `Result` holding the trained dictionary bytes, or a decoded error.
 *          Training fails if there are too few samples or they are unsuitable.
 */
Result!(ubyte[]) trainDictionary(const(ubyte[])[] samples, size_t dictCapacity) @trusted
{
    size_t total = 0;
    foreach (s; samples)
        total += s.length;

    auto flat = new ubyte[total];
    auto sizes = new size_t[samples.length];
    size_t offset = 0;
    foreach (i, s; samples)
    {
        flat[offset .. offset + s.length] = s[];
        sizes[i] = s.length;
        offset += s.length;
    }

    auto dict = new ubyte[dictCapacity];
    const written = ZDICT_trainFromBuffer(dict.ptr, dict.length,
            flat.ptr, sizes.ptr, cast(uint) samples.length);
    if (ZDICT_isError(written))
        return Result!(ubyte[]).err(written);
    return Result!(ubyte[]).ok(dict[0 .. written]);
}

/// Extracts the dictionary ID stored in a dictionary buffer (0 if not a valid
/// zstd dictionary).
uint dictionaryID(const(ubyte)[] dict) @trusted nothrow @nogc
{
    return ZDICT_getDictID(dict.ptr, dict.length);
}

/**
 * A digested dictionary prepared for compression (wraps `ZSTD_CDict`).
 *
 * Digesting a dictionary once and reusing the handle avoids repeating the costly
 * preparation on every compression. Non-copyable; owns its native handle.
 */
struct CompressionDictionary
{
    private ZSTD_CDict* _dict;

    @disable this(this);

    ~this() @trusted nothrow @nogc
    {
        if (_dict !is null)
        {
            ZSTD_freeCDict(_dict);
            _dict = null;
        }
    }

    /// The underlying native handle (may be `null` after a move).
    inout(ZSTD_CDict)* handle() inout @nogc nothrow pure @safe
    {
        return _dict;
    }

    /// The dictionary ID (0 if content-only or empty).
    uint id() const @trusted nothrow @nogc
    {
        return ZSTD_getDictID_fromCDict(_dict);
    }
}

/**
 * Digests a dictionary for compression at the given `level`.
 *
 * Digesting a dictionary once and reusing the returned handle avoids repeating
 * the costly preparation on every compression.
 *
 * Returns: a `Result` holding a `CompressionDictionary`, or a decoded error.
 */
Result!CompressionDictionary createCompressionDictionary(const(ubyte)[] dict,
        int level = ZSTD_CLEVEL_DEFAULT) @trusted
{
    import core.lifetime : move;

    auto cd = ZSTD_createCDict(dict.ptr, dict.length, level);
    if (cd is null)
        return Result!CompressionDictionary.err(ZstdError(
                ZSTD_ErrorCode.ZSTD_error_dictionaryCreation_failed,
                "failed to create ZSTD_CDict"));
    CompressionDictionary d;
    d._dict = cd;
    return Result!CompressionDictionary.ok(move(d));
}

/**
 * A digested dictionary prepared for decompression (wraps `ZSTD_DDict`).
 *
 * Non-copyable; owns its native handle.
 */
struct DecompressionDictionary
{
    private ZSTD_DDict* _dict;

    @disable this(this);

    ~this() @trusted nothrow @nogc
    {
        if (_dict !is null)
        {
            ZSTD_freeDDict(_dict);
            _dict = null;
        }
    }

    /// The underlying native handle (may be `null` after a move).
    inout(ZSTD_DDict)* handle() inout @nogc nothrow pure @safe
    {
        return _dict;
    }

    /// The dictionary ID (0 if content-only or empty).
    uint id() const @trusted nothrow @nogc
    {
        return ZSTD_getDictID_fromDDict(_dict);
    }
}

/**
 * Digests a dictionary for decompression.
 *
 * Returns: a `Result` holding a `DecompressionDictionary`, or a decoded error.
 */
Result!DecompressionDictionary createDecompressionDictionary(const(ubyte)[] dict) @trusted
{
    import core.lifetime : move;

    auto dd = ZSTD_createDDict(dict.ptr, dict.length);
    if (dd is null)
        return Result!DecompressionDictionary.err(ZstdError(
                ZSTD_ErrorCode.ZSTD_error_dictionaryCreation_failed,
                "failed to create ZSTD_DDict"));
    DecompressionDictionary d;
    d._dict = dd;
    return Result!DecompressionDictionary.ok(move(d));
}

/**
 * Compresses `src` using a digested compression dictionary.
 *
 * Convenience wrapper that allocates a temporary context. For repeated use with
 * the same dictionary, create a `Compressor`, call `ZSTD_CCtx_refCDict`, and
 * reuse it.
 */
Result!(ubyte[]) compressWithDictionary(const(ubyte)[] src,
        ref const CompressionDictionary dict) @trusted
{
    auto cr = createCompressor();
    if (cr.isErr)
        return Result!(ubyte[]).err(cr.error);
    const rc = ZSTD_CCtx_refCDict(cr.value.handle, dict.handle);
    if (isZstdError(rc))
        return Result!(ubyte[]).err(rc);
    return cr.value.compress(src);
}

/**
 * Decompresses `src` using a digested decompression dictionary.
 *
 * Convenience wrapper that allocates a temporary context.
 */
Result!(ubyte[]) decompressWithDictionary(const(ubyte)[] src,
        ref const DecompressionDictionary dict) @trusted
{
    auto dr = createDecompressor();
    if (dr.isErr)
        return Result!(ubyte[]).err(dr.error);
    const rc = ZSTD_DCtx_refDDict(dr.value.handle, dict.handle);
    if (isZstdError(rc))
        return Result!(ubyte[]).err(rc);
    return dr.value.decompress(src);
}

version (unittest)
{
    // Many small, similar samples suitable for dictionary training.
    private ubyte[][] trainingSamples() @safe
    {
        import std.format : format;

        ubyte[][] samples;
        foreach (i; 0 .. 2000)
            samples ~= cast(ubyte[]) format(`{"user":%s,"role":"member","active":true}`, i).dup;
        return samples;
    }
}

@safe unittest
{
    // Training produces a usable dictionary with a non-zero ID.
    auto trained = trainDictionary(trainingSamples(), 16 * 1024);
    assert(trained.isOk);
    assert(trained.value.length > 0);
    assert(dictionaryID(trained.value) != 0);
}

@safe unittest
{
    // Round-trip through digested dictionaries, and confirm the IDs line up.
    auto trained = trainDictionary(trainingSamples(), 16 * 1024);
    assert(trained.isOk);

    auto cdict = createCompressionDictionary(trained.value, 3);
    auto ddict = createDecompressionDictionary(trained.value);
    assert(cdict.isOk);
    assert(ddict.isOk);
    assert(cdict.value.id == dictionaryID(trained.value));
    assert(ddict.value.id == dictionaryID(trained.value));

    ubyte[] record = cast(ubyte[]) `{"user":424242,"role":"member","active":true}`.dup;
    auto compressed = compressWithDictionary(record, cdict.value);
    assert(compressed.isOk);

    auto restored = decompressWithDictionary(compressed.value, ddict.value);
    assert(restored.isOk);
    assert(restored.value == record);
}

@safe unittest
{
    import zstd.decompress : decompress;

    // Dictionary-compressed data cannot be decompressed without the dictionary.
    auto trained = trainDictionary(trainingSamples(), 16 * 1024);
    assert(trained.isOk);
    auto cdict = createCompressionDictionary(trained.value, 3);
    assert(cdict.isOk);

    ubyte[] record = cast(ubyte[]) `{"user":1,"role":"member","active":true}`.dup;
    auto compressed = compressWithDictionary(record, cdict.value);
    assert(compressed.isOk);

    auto restored = decompress(compressed.value); // no dictionary supplied
    assert(restored.isErr);
}

@safe unittest
{
    // Training fails cleanly when given too few samples.
    ubyte[][] tooFew = [cast(ubyte[]) "abc".dup, cast(ubyte[]) "def".dup];
    auto trained = trainDictionary(tooFew, 4 * 1024);
    assert(trained.isErr);
    assert(trained.message.length > 0);
}
