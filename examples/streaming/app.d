/**
 * Streaming compression example using a reusable `Compressor` context and the
 * low-level streaming primitives.
 *
 * Build & run: dub run :streaming
 */
module examples.streaming.app;

import std.stdio;
import zstd;
import etc.c.zstd.zstd : ZSTD_inBuffer, ZSTD_outBuffer, ZSTD_EndDirective, ZSTD_CStreamOutSize;

void main()
{
    // Some repetitive data to compress.
    ubyte[] data;
    foreach (i; 0 .. 20_000)
        data ~= cast(ubyte)('A' + (i % 26));

    auto cr = createCompressor();
    if (cr.isErr)
    {
        stderr.writeln("failed to create compressor: ", cr.message);
        return;
    }
    cr.value.setCompressionLevel(6);

    // Feed the input through the streaming API, ending the frame in one pass.
    ubyte[] compressed;
    auto outBuf = new ubyte[ZSTD_CStreamOutSize()];
    auto input = ZSTD_inBuffer(data.ptr, data.length, 0);
    for (;;)
    {
        auto output = ZSTD_outBuffer(outBuf.ptr, outBuf.length, 0);
        auto step = cr.value.compressStream(input, output, ZSTD_EndDirective.ZSTD_e_end);
        if (step.isErr)
        {
            stderr.writeln("stream error: ", step.message);
            return;
        }
        compressed ~= outBuf[0 .. output.pos];
        if (step.value == 0)
            break; // frame fully flushed
    }

    writefln("streamed %s -> %s bytes", data.length, compressed.length);

    auto restored = decompress(compressed);
    assert(restored.isOk && restored.value == data);
    writeln("streaming round-trip ok");
}
