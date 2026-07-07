/**
 * Raw C bindings for `zdict.h` (Zstandard dictionary builder, stable public API).
 *
 * This is a hand-translated 1:1 binding of the stable public surface of the
 * Zstandard dictionary builder (v1.5.7). The experimental API gated behind
 * `ZDICT_STATIC_LINKING_ONLY` in the C header is intentionally omitted.
 *
 * Symbols are resolved from the statically linked zstd library. Prefer the
 * D-native `zstd` wrapper package for idiomatic usage.
 *
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module etc.c.zstd.zdict;

extern (C):
nothrow:
@nogc:

/*! ZDICT_trainFromBuffer():
 *  Train a dictionary from an array of samples.
 *  Samples must be stored concatenated in a single flat buffer `samplesBuffer`,
 *  supplied with an array of sizes `samplesSizes`, providing the size of each sample, in order.
 * @return: size of dictionary stored into `dictBuffer` (<= `dictBufferCapacity`)
 *          or an error code, which can be tested with ZDICT_isError(). */
size_t ZDICT_trainFromBuffer(void* dictBuffer, size_t dictBufferCapacity,
        const(void)* samplesBuffer,
        const(size_t)* samplesSizes, uint nbSamples);

struct ZDICT_params_t
{
    int compressionLevel; /**< optimize for a specific zstd compression level; 0 means default */
    uint notificationLevel; /**< Write log to stderr; 0 = none (default); 1 = errors; 2 = progression; 3 = details; 4 = debug; */
    uint dictID; /**< force dictID value; 0 means auto mode (32-bits random value) */
}

/*! ZDICT_finalizeDictionary():
 *  Given a custom content as a basis for dictionary, and a set of samples,
 *  finalize dictionary by adding headers and statistics according to the zstd
 *  dictionary format.
 * @return: size of dictionary stored into `dstDictBuffer` (<= `maxDictSize`),
 *          or an error code, which can be tested by ZDICT_isError(). */
size_t ZDICT_finalizeDictionary(void* dstDictBuffer, size_t maxDictSize,
        const(void)* dictContent, size_t dictContentSize,
        const(void)* samplesBuffer, const(size_t)* samplesSizes, uint nbSamples,
        ZDICT_params_t parameters);

/*======   Helper functions   ======*/

/**< extracts dictID; @return zero if error (not a valid dictionary) */
uint ZDICT_getDictID(const(void)* dictBuffer, size_t dictSize);

/* returns dict header size; returns a ZSTD error code on failure */
size_t ZDICT_getDictHeaderSize(const(void)* dictBuffer, size_t dictSize);

uint ZDICT_isError(size_t errorCode);
const(char)* ZDICT_getErrorName(size_t errorCode);
