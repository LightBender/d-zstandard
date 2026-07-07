/**
 * Dictionary training and dictionary-based compression example.
 *
 * Build & run: dub run :dictionary
 */
module examples.dictionary.app;

import std.stdio;
import std.format : format;
import zstd;

void main()
{
    // Gather many small, similar samples to train on.
    ubyte[][] samples;
    foreach (i; 0 .. 2000)
        samples ~= cast(ubyte[]) format(`{"user":%s,"role":"member","active":true}`, i).dup;

    auto trained = trainDictionary(samples, 16 * 1024);
    if (trained.isErr)
    {
        stderr.writeln("dictionary training failed: ", trained.message);
        return;
    }
    writefln("trained dictionary: %s bytes, id=%s",
            trained.value.length, dictionaryID(trained.value));

    // Digest the dictionary once for reuse.
    auto cdict = createCompressionDictionary(trained.value, 3);
    auto ddict = createDecompressionDictionary(trained.value);
    if (cdict.isErr || ddict.isErr)
    {
        stderr.writeln("failed to build digested dictionaries");
        return;
    }

    ubyte[] record = cast(ubyte[]) `{"user":424242,"role":"member","active":true}`.dup;
    auto compressed = compressWithDictionary(record, cdict.value);
    if (compressed.isErr)
    {
        stderr.writeln("dictionary compression failed: ", compressed.message);
        return;
    }

    auto restored = decompressWithDictionary(compressed.value, ddict.value);
    assert(restored.isOk && restored.value == record);
    writefln("dictionary-compressed %s -> %s bytes; round-trip ok",
            record.length, compressed.value.length);
}
