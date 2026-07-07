/**
 * D-native compression API for Zstandard.
 *
 * Offers a simple one-shot `compress` function that allocates and returns a
 * compressed buffer, plus a reusable `Compressor` context for advanced
 * parameters, sticky dictionaries, and manual streaming.
 *
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module zstd.compress;

import etc.c.zstd.zstd;
import zstd.result;

/**
 * Compresses `src` into a newly allocated buffer as a single zstd frame.
 *
 * Params:
 *   src   = the raw bytes to compress.
 *   level = the compression level (defaults to `ZSTD_CLEVEL_DEFAULT`).
 * Returns: a `Result` holding the compressed bytes, or a decoded error.
 */
Result!(ubyte[]) compress(const(ubyte)[] src, int level = ZSTD_CLEVEL_DEFAULT) @trusted
{
    const bound = ZSTD_compressBound(src.length);
    auto dst = new ubyte[bound];
    const written = ZSTD_compress(dst.ptr, dst.length, src.ptr, src.length, level);
    if (isZstdError(written))
        return Result!(ubyte[]).err(written);
    return Result!(ubyte[]).ok(dst[0 .. written]);
}

/**
 * A reusable compression context (wraps `ZSTD_CCtx`).
 *
 * Allocate once with `createCompressor` and reuse across many compressions to
 * reduce per-call allocation. Parameters and dictionaries set on the context are
 * sticky and apply to subsequent `compress` / `compressStream` calls.
 *
 * The context owns its native handle and is non-copyable; move it or access it
 * in place through the owning `Result`.
 */
struct Compressor
{
    private ZSTD_CCtx* _ctx;

    @disable this(this);

    ~this() @trusted nothrow @nogc
    {
        if (_ctx !is null)
        {
            ZSTD_freeCCtx(_ctx);
            _ctx = null;
        }
    }

    /// The underlying native handle (may be `null` after a move).
    inout(ZSTD_CCtx)* handle() inout @nogc nothrow pure @safe
    {
        return _ctx;
    }

    /// Sets a sticky compression parameter.
    Result!void setParameter(ZSTD_cParameter param, int value) @trusted
    {
        const ret = ZSTD_CCtx_setParameter(_ctx, param, value);
        if (isZstdError(ret))
            return Result!void.err(ret);
        return Result!void.ok();
    }

    /// Convenience wrapper for setting the compression level.
    Result!void setCompressionLevel(int level) @trusted
    {
        return setParameter(ZSTD_cParameter.ZSTD_c_compressionLevel, level);
    }

    /// Declares the exact size of the next frame's input (written to the header).
    Result!void setPledgedSrcSize(ulong pledgedSrcSize) @trusted
    {
        const ret = ZSTD_CCtx_setPledgedSrcSize(_ctx, pledgedSrcSize);
        if (isZstdError(ret))
            return Result!void.err(ret);
        return Result!void.ok();
    }

    /// Loads a sticky dictionary (copied internally). Pass an empty slice to clear.
    Result!void loadDictionary(const(ubyte)[] dict) @trusted
    {
        const ret = ZSTD_CCtx_loadDictionary(_ctx, dict.ptr, dict.length);
        if (isZstdError(ret))
            return Result!void.err(ret);
        return Result!void.ok();
    }

    /// Resets the session and/or parameters of the context.
    Result!void reset(ZSTD_ResetDirective directive = ZSTD_ResetDirective.ZSTD_reset_session_and_parameters) @trusted
    {
        const ret = ZSTD_CCtx_reset(_ctx, directive);
        if (isZstdError(ret))
            return Result!void.err(ret);
        return Result!void.ok();
    }

    /**
     * Compresses `src` into a newly allocated buffer as a single frame, honouring
     * any sticky parameters or dictionary set on this context.
     */
    Result!(ubyte[]) compress(const(ubyte)[] src) @trusted
    {
        const bound = ZSTD_compressBound(src.length);
        auto dst = new ubyte[bound];
        const written = ZSTD_compress2(_ctx, dst.ptr, dst.length, src.ptr, src.length);
        if (isZstdError(written))
            return Result!(ubyte[]).err(written);
        return Result!(ubyte[]).ok(dst[0 .. written]);
    }

    /**
     * Low-level streaming compression step.
     *
     * Advances `input.pos` and `output.pos` as data is consumed and produced.
     * Params:
     *   input  = the input buffer view; `pos` is updated in place.
     *   output = the output buffer view; `pos` is updated in place.
     *   endOp  = whether to continue, flush, or end the frame.
     * Returns: a `Result` whose value is the minimum number of bytes still to be
     *          flushed from internal buffers (0 means fully flushed).
     */
    Result!size_t compressStream(ref ZSTD_inBuffer input, ref ZSTD_outBuffer output,
            ZSTD_EndDirective endOp) @trusted
    {
        const ret = ZSTD_compressStream2(_ctx, &output, &input, endOp);
        if (isZstdError(ret))
            return Result!size_t.err(ret);
        return Result!size_t.ok(ret);
    }
}

/**
 * Creates a new compression context.
 *
 * Returns: a `Result` holding a ready-to-use `Compressor`, or a decoded error if
 *          the native context could not be allocated.
 */
Result!Compressor createCompressor() @trusted
{
    import core.lifetime : move;

    auto ctx = ZSTD_createCCtx();
    if (ctx is null)
        return Result!Compressor.err(ZstdError(ZSTD_ErrorCode.ZSTD_error_memory_allocation,
                "failed to allocate ZSTD_CCtx"));
    Compressor c;
    c._ctx = ctx;
    return Result!Compressor.ok(move(c));
}

@safe unittest
{
    // Round-trip through the free function is covered in zstd.decompress; here we
    // just verify the context lifecycle and parameter setting.
    auto cr = createCompressor();
    assert(cr.isOk);
    assert(cr.value.handle !is null);
    assert(cr.value.setCompressionLevel(5).isOk);

    ubyte[] data = [1, 2, 3, 4, 5, 1, 2, 3, 4, 5];
    auto compressed = cr.value.compress(data);
    assert(compressed.isOk);
    assert(compressed.value.length > 0);
}

unittest
{
    import zstd.decompress : decompress;
    import etc.c.zstd.zstd : ZSTD_inBuffer, ZSTD_outBuffer, ZSTD_EndDirective, ZSTD_CStreamOutSize;

    // Streaming compression: feed the input and end the frame, then verify the
    // streamed output decompresses back to the original.
    ubyte[] data;
    foreach (i; 0 .. 5000)
        data ~= cast(ubyte)('a' + (i % 26));

    auto cr = createCompressor();
    assert(cr.isOk);
    assert(cr.value.setCompressionLevel(6).isOk);

    ubyte[] compressed;
    auto outBuf = new ubyte[ZSTD_CStreamOutSize()];
    auto input = ZSTD_inBuffer(data.ptr, data.length, 0);
    for (;;)
    {
        auto output = ZSTD_outBuffer(outBuf.ptr, outBuf.length, 0);
        auto step = cr.value.compressStream(input, output, ZSTD_EndDirective.ZSTD_e_end);
        assert(step.isOk);
        compressed ~= outBuf[0 .. output.pos];
        if (step.value == 0)
            break;
    }
    assert(compressed.length > 0);

    auto restored = decompress(compressed);
    assert(restored.isOk);
    assert(restored.value == data);
}
