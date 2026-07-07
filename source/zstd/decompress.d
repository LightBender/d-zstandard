/**
 * D-native decompression API for Zstandard.
 *
 * Offers a simple one-shot `decompress` function plus a reusable `Decompressor`
 * context for sticky dictionaries and manual streaming.
 *
 * For untrusted input, note that a frame header can claim an arbitrary
 * decompressed size. To avoid allocating memory based purely on an unverified
 * header, this module only pre-allocates directly when the claimed size is below
 * `directAllocThreshold`; larger (or unknown) sizes are decoded incrementally
 * through the streaming API, so memory grows only as real data is produced.
 *
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module zstd.decompress;

import etc.c.zstd.zstd;
import zstd.result;

/// Upper bound (bytes) for trusting a frame's declared content size enough to
/// pre-allocate the output buffer in a single step. Above this, streaming is used.
enum size_t directAllocThreshold = 64 * 1024 * 1024;

/**
 * Decompresses `src` (one or more concatenated frames) into a newly allocated
 * buffer.
 *
 * Uses the frame's declared content size for a fast single allocation when it is
 * known and within `directAllocThreshold`; otherwise decodes incrementally.
 *
 * Returns: a `Result` holding the decompressed bytes, or a decoded error.
 */
Result!(ubyte[]) decompress(const(ubyte)[] src) @trusted
{
    const contentSize = ZSTD_getFrameContentSize(src.ptr, src.length);
    if (contentSize != ZSTD_CONTENTSIZE_UNKNOWN
            && contentSize != ZSTD_CONTENTSIZE_ERROR
            && contentSize <= directAllocThreshold)
    {
        auto dst = new ubyte[cast(size_t) contentSize];
        const written = ZSTD_decompress(dst.ptr, dst.length, src.ptr, src.length);
        if (isZstdError(written))
            return Result!(ubyte[]).err(written);
        return Result!(ubyte[]).ok(dst[0 .. written]);
    }
    return decompressStreaming(src);
}

/// Incrementally decompresses `src` using a fresh streaming context, growing the
/// output buffer as needed.
private Result!(ubyte[]) decompressStreaming(const(ubyte)[] src) @trusted
{
    auto zds = ZSTD_createDStream();
    if (zds is null)
        return Result!(ubyte[]).err(ZstdError(ZSTD_ErrorCode.ZSTD_error_memory_allocation,
                "failed to allocate ZSTD_DStream"));
    scope (exit)
        ZSTD_freeDStream(zds);
    ZSTD_initDStream(zds);

    auto output = new ubyte[ZSTD_DStreamOutSize()];
    size_t produced = 0;
    auto input = ZSTD_inBuffer(src.ptr, src.length, 0);

    while (input.pos < input.size)
    {
        if (produced == output.length)
            output.length = output.length * 2;
        auto outBuf = ZSTD_outBuffer(output.ptr, output.length, produced);
        const ret = ZSTD_decompressStream(zds, &outBuf, &input);
        if (isZstdError(ret))
            return Result!(ubyte[]).err(ret);
        produced = outBuf.pos;
    }
    return Result!(ubyte[]).ok(output[0 .. produced]);
}

/**
 * A reusable decompression context (wraps `ZSTD_DCtx`).
 *
 * Allocate once with `createDecompressor` and reuse across many decompressions.
 * A dictionary loaded on the context is sticky and applies to subsequent frames.
 *
 * The context owns its native handle and is non-copyable; move it or access it
 * in place through the owning `Result`.
 */
struct Decompressor
{
    private ZSTD_DCtx* _ctx;

    @disable this(this);

    ~this() @trusted nothrow @nogc
    {
        if (_ctx !is null)
        {
            ZSTD_freeDCtx(_ctx);
            _ctx = null;
        }
    }

    /// The underlying native handle (may be `null` after a move).
    inout(ZSTD_DCtx)* handle() inout @nogc nothrow pure @safe
    {
        return _ctx;
    }

    /// Sets a sticky decompression parameter.
    Result!void setParameter(ZSTD_dParameter param, int value) @trusted
    {
        const ret = ZSTD_DCtx_setParameter(_ctx, param, value);
        if (isZstdError(ret))
            return Result!void.err(ret);
        return Result!void.ok();
    }

    /// Loads a sticky dictionary (copied internally). Pass an empty slice to clear.
    Result!void loadDictionary(const(ubyte)[] dict) @trusted
    {
        const ret = ZSTD_DCtx_loadDictionary(_ctx, dict.ptr, dict.length);
        if (isZstdError(ret))
            return Result!void.err(ret);
        return Result!void.ok();
    }

    /// Resets the session and/or parameters of the context.
    Result!void reset(ZSTD_ResetDirective directive = ZSTD_ResetDirective.ZSTD_reset_session_and_parameters) @trusted
    {
        const ret = ZSTD_DCtx_reset(_ctx, directive);
        if (isZstdError(ret))
            return Result!void.err(ret);
        return Result!void.ok();
    }

    /**
     * Decompresses `src` into a newly allocated buffer, honouring any sticky
     * dictionary set on this context.
     */
    Result!(ubyte[]) decompress(const(ubyte)[] src) @trusted
    {
        const contentSize = ZSTD_getFrameContentSize(src.ptr, src.length);
        if (contentSize != ZSTD_CONTENTSIZE_UNKNOWN
                && contentSize != ZSTD_CONTENTSIZE_ERROR
                && contentSize <= directAllocThreshold)
        {
            auto dst = new ubyte[cast(size_t) contentSize];
            const written = ZSTD_decompressDCtx(_ctx, dst.ptr, dst.length, src.ptr, src.length);
            if (isZstdError(written))
                return Result!(ubyte[]).err(written);
            return Result!(ubyte[]).ok(dst[0 .. written]);
        }

        auto output = new ubyte[ZSTD_DStreamOutSize()];
        size_t produced = 0;
        auto input = ZSTD_inBuffer(src.ptr, src.length, 0);
        while (input.pos < input.size)
        {
            if (produced == output.length)
                output.length = output.length * 2;
            auto outBuf = ZSTD_outBuffer(output.ptr, output.length, produced);
            const ret = ZSTD_decompressStream(_ctx, &outBuf, &input);
            if (isZstdError(ret))
                return Result!(ubyte[]).err(ret);
            produced = outBuf.pos;
        }
        return Result!(ubyte[]).ok(output[0 .. produced]);
    }

    /**
     * Low-level streaming decompression step.
     *
     * Advances `input.pos` and `output.pos` as data is consumed and produced.
     * Returns: a `Result` whose value is 0 when a frame is fully decoded and
     *          flushed, or a hint for the next input size otherwise.
     */
    Result!size_t decompressStream(ref ZSTD_inBuffer input, ref ZSTD_outBuffer output) @trusted
    {
        const ret = ZSTD_decompressStream(_ctx, &output, &input);
        if (isZstdError(ret))
            return Result!size_t.err(ret);
        return Result!size_t.ok(ret);
    }
}

/**
 * Creates a new decompression context.
 *
 * Returns: a `Result` holding a ready-to-use `Decompressor`, or a decoded error
 *          if the native context could not be allocated.
 */
Result!Decompressor createDecompressor() @trusted
{
    import core.lifetime : move;

    auto ctx = ZSTD_createDCtx();
    if (ctx is null)
        return Result!Decompressor.err(ZstdError(ZSTD_ErrorCode.ZSTD_error_memory_allocation,
                "failed to allocate ZSTD_DCtx"));
    Decompressor d;
    d._ctx = ctx;
    return Result!Decompressor.ok(move(d));
}

@safe unittest
{
    import zstd.compress : compress;

    // A Decompressor round-trips one-shot compressed data.
    ubyte[] data = cast(ubyte[]) "context decompression round-trip test".dup;
    auto compressed = compress(data, 5);
    assert(compressed.isOk);

    auto dr = createDecompressor();
    assert(dr.isOk);
    assert(dr.value.handle !is null);

    auto restored = dr.value.decompress(compressed.value);
    assert(restored.isOk);
    assert(restored.value == data);
}

@safe unittest
{
    import zstd.compress : compress;

    // A single Decompressor can be reused across multiple independent frames.
    auto dr = createDecompressor();
    assert(dr.isOk);

    foreach (word; ["alpha", "beta", "gamma"])
    {
        ubyte[] data = cast(ubyte[]) word.dup;
        auto compressed = compress(data);
        assert(compressed.isOk);
        auto restored = dr.value.decompress(compressed.value);
        assert(restored.isOk);
        assert(restored.value == data);
    }
}

unittest
{
    import zstd.compress : createCompressor;
    import etc.c.zstd.zstd : ZSTD_inBuffer, ZSTD_outBuffer, ZSTD_EndDirective,
        ZSTD_CStreamOutSize, ZSTD_DStreamOutSize;

    // Manual streaming decompression via decompressStream, fed from a streaming
    // compression, exercises both low-level streaming primitives.
    ubyte[] data;
    foreach (i; 0 .. 8000)
        data ~= cast(ubyte)('0' + (i % 10));

    auto cr = createCompressor();
    assert(cr.isOk);
    ubyte[] compressed;
    auto cOut = new ubyte[ZSTD_CStreamOutSize()];
    auto cIn = ZSTD_inBuffer(data.ptr, data.length, 0);
    for (;;)
    {
        auto o = ZSTD_outBuffer(cOut.ptr, cOut.length, 0);
        auto step = cr.value.compressStream(cIn, o, ZSTD_EndDirective.ZSTD_e_end);
        assert(step.isOk);
        compressed ~= cOut[0 .. o.pos];
        if (step.value == 0)
            break;
    }

    auto dr = createDecompressor();
    assert(dr.isOk);
    ubyte[] restored;
    auto dOut = new ubyte[ZSTD_DStreamOutSize()];
    auto dIn = ZSTD_inBuffer(compressed.ptr, compressed.length, 0);
    while (dIn.pos < dIn.size)
    {
        auto o = ZSTD_outBuffer(dOut.ptr, dOut.length, 0);
        auto step = dr.value.decompressStream(dIn, o);
        assert(step.isOk);
        restored ~= dOut[0 .. o.pos];
    }
    assert(restored == data);
}

@safe unittest
{
    // Decompressing invalid input through the context returns an error, not a crash.
    auto dr = createDecompressor();
    assert(dr.isOk);
    ubyte[] garbage = [9, 9, 9, 9, 9, 9, 9, 9];
    auto result = dr.value.decompress(garbage);
    assert(result.isErr);
    assert(result.message.length > 0);
}
