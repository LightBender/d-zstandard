/**
 * Simple one-shot compression example using the D-native `zstd` wrapper.
 *
 * Build & run: dub run :simple
 */
module examples.simple.app;

import std.stdio;
import zstd;

void main()
{
    ubyte[] original = cast(ubyte[]) "Hello, Zstandard from D! ".dup;
    foreach (_; 0 .. 6)
        original ~= original; // make it big enough to compress well

    // Compress at level 9. `compress` returns a Result carrying either the
    // compressed bytes or a decoded error.
    auto compressed = compress(original, 9);
    if (compressed.isErr)
    {
        stderr.writeln("compression failed: ", compressed.message);
        return;
    }

    writefln("original:   %s bytes", original.length);
    writefln("compressed: %s bytes", compressed.value.length);

    // Decompress and verify the round-trip.
    auto restored = decompress(compressed.value);
    if (restored.isErr)
    {
        stderr.writeln("decompression failed: ", restored.message);
        return;
    }

    assert(restored.value == original);
    writeln("round-trip succeeded; zstd version ", versionString());
}
