/**
 * Raw C bindings for `zstd.h` (Zstandard compression library, stable public API).
 *
 * This is a hand-translated 1:1 binding of the stable public surface of Meta's
 * Zstandard library (v1.5.7). The experimental API that is gated behind
 * `ZSTD_STATIC_LINKING_ONLY` in the C header is intentionally omitted, as it is
 * not part of the stable ABI.
 *
 * Symbols are resolved from the statically linked zstd library produced by the
 * package's build step. Prefer the D-native `zstd` wrapper package for
 * idiomatic usage; this module exists for callers that need the C API directly.
 *
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module etc.c.zstd.zstd;

public import etc.c.zstd.zstd_errors : ZSTD_ErrorCode;

extern (C):
nothrow:
@nogc:

/*------   Version   ------*/
enum ZSTD_VERSION_MAJOR = 1;
enum ZSTD_VERSION_MINOR = 5;
enum ZSTD_VERSION_RELEASE = 7;
enum ZSTD_VERSION_NUMBER = ZSTD_VERSION_MAJOR * 100 * 100 + ZSTD_VERSION_MINOR * 100 + ZSTD_VERSION_RELEASE;
enum ZSTD_VERSION_STRING = "1.5.7";

/*! ZSTD_versionNumber() :
 *  Return runtime library version, the value is (MAJOR*100*100 + MINOR*100 + RELEASE). */
uint ZSTD_versionNumber();

/*! ZSTD_versionString() :
 *  Return runtime library version, like "1.4.5". Requires v1.3.0+. */
const(char)* ZSTD_versionString();

/* *************************************
 *  Constants
 ***************************************/
enum ZSTD_CLEVEL_DEFAULT = 3;

/* All magic numbers are supposed read/written to/from files/memory using little-endian convention */
enum ZSTD_MAGICNUMBER = 0xFD2FB528; /* valid since v0.8.0 */
enum ZSTD_MAGIC_DICTIONARY = 0xEC30A437; /* valid since v0.7.0 */
enum ZSTD_MAGIC_SKIPPABLE_START = 0x184D2A50;
enum ZSTD_MAGIC_SKIPPABLE_MASK = 0xFFFFFFF0;

enum ZSTD_BLOCKSIZELOG_MAX = 17;
enum ZSTD_BLOCKSIZE_MAX = 1 << ZSTD_BLOCKSIZELOG_MAX;

/***************************************
*  Simple Core API
***************************************/
/*! ZSTD_compress() :
 *  Compresses `src` content as a single zstd compressed frame into already allocated `dst`.
 *  @return : compressed size written into `dst` (<= `dstCapacity`),
 *            or an error code if it fails (which can be tested using ZSTD_isError()). */
size_t ZSTD_compress(void* dst, size_t dstCapacity,
        const(void)* src, size_t srcSize,
        int compressionLevel);

/*! ZSTD_decompress() :
 * `compressedSize` : must be the _exact_ size of some number of compressed and/or skippable frames.
 * `dstCapacity` is an upper bound of originalSize to regenerate.
 * @return : the number of bytes decompressed into `dst` (<= `dstCapacity`),
 *           or an errorCode if it fails (which can be tested using ZSTD_isError()). */
size_t ZSTD_decompress(void* dst, size_t dstCapacity,
        const(void)* src, size_t compressedSize);

/*======  Decompression helper functions  ======*/

enum ulong ZSTD_CONTENTSIZE_UNKNOWN = 0UL - 1UL;
enum ulong ZSTD_CONTENTSIZE_ERROR = 0UL - 2UL;

/*! ZSTD_getFrameContentSize() : requires v1.3.0+
 * @return : - decompressed size of `src` frame content, if known
 *           - ZSTD_CONTENTSIZE_UNKNOWN if the size cannot be determined
 *           - ZSTD_CONTENTSIZE_ERROR if an error occurred (e.g. invalid magic number, srcSize too small) */
ulong ZSTD_getFrameContentSize(const(void)* src, size_t srcSize);

/*! ZSTD_getDecompressedSize() (obsolete):
 *  This function is now obsolete, in favor of ZSTD_getFrameContentSize(). */
deprecated("Replaced by ZSTD_getFrameContentSize")
ulong ZSTD_getDecompressedSize(const(void)* src, size_t srcSize);

/*! ZSTD_findFrameCompressedSize() : Requires v1.4.0+
 * @return : the compressed size of the first frame starting at `src`,
 *           suitable to pass as `srcSize` to `ZSTD_decompress` or similar,
 *           or an error code if input is invalid. */
size_t ZSTD_findFrameCompressedSize(const(void)* src, size_t srcSize);

/*======  Compression helper functions  ======*/

enum size_t ZSTD_MAX_INPUT_SIZE = size_t.sizeof == 8 ? 0xFF00FF00FF00FF00UL : 0xFF00FF00U;

/*! ZSTD_compressBound() :
 * maximum compressed size in worst case single-pass scenario. */
size_t ZSTD_compressBound(size_t srcSize);

/*======  Error helper functions  ======*/
/*!< tells if a `size_t` function result is an error code */
uint ZSTD_isError(size_t result);
/* convert a result into an error code, which can be compared to error enum list */
ZSTD_ErrorCode ZSTD_getErrorCode(size_t functionResult);
/*!< provides readable string from a function result */
const(char)* ZSTD_getErrorName(size_t result);
/*!< minimum negative compression level allowed, requires v1.4.0+ */
int ZSTD_minCLevel();
/*!< maximum compression level available */
int ZSTD_maxCLevel();
/*!< default compression level, specified by ZSTD_CLEVEL_DEFAULT, requires v1.5.0+ */
int ZSTD_defaultCLevel();

/***************************************
*  Explicit context
***************************************/
/*= Compression context */
struct ZSTD_CCtx_s;
alias ZSTD_CCtx = ZSTD_CCtx_s;
ZSTD_CCtx* ZSTD_createCCtx();
size_t ZSTD_freeCCtx(ZSTD_CCtx* cctx); /* compatible with NULL pointer */

/*! ZSTD_compressCCtx() :
 *  Same as ZSTD_compress(), using an explicit ZSTD_CCtx.
 *  __ignoring any other advanced parameter__ . */
size_t ZSTD_compressCCtx(ZSTD_CCtx* cctx,
        void* dst, size_t dstCapacity,
        const(void)* src, size_t srcSize,
        int compressionLevel);

/*= Decompression context */
struct ZSTD_DCtx_s;
alias ZSTD_DCtx = ZSTD_DCtx_s;
ZSTD_DCtx* ZSTD_createDCtx();
size_t ZSTD_freeDCtx(ZSTD_DCtx* dctx); /* accept NULL pointer */

/*! ZSTD_decompressDCtx() :
 *  Same as ZSTD_decompress(), requires an allocated ZSTD_DCtx. */
size_t ZSTD_decompressDCtx(ZSTD_DCtx* dctx,
        void* dst, size_t dstCapacity,
        const(void)* src, size_t srcSize);

/*********************************************
*  Advanced compression API (Requires v1.4.0+)
**********************************************/

/* Compression strategies, listed from fastest to strongest */
enum ZSTD_strategy
{
    ZSTD_fast = 1,
    ZSTD_dfast = 2,
    ZSTD_greedy = 3,
    ZSTD_lazy = 4,
    ZSTD_lazy2 = 5,
    ZSTD_btlazy2 = 6,
    ZSTD_btopt = 7,
    ZSTD_btultra = 8,
    ZSTD_btultra2 = 9
}

alias ZSTD_fast = ZSTD_strategy.ZSTD_fast;
alias ZSTD_dfast = ZSTD_strategy.ZSTD_dfast;
alias ZSTD_greedy = ZSTD_strategy.ZSTD_greedy;
alias ZSTD_lazy = ZSTD_strategy.ZSTD_lazy;
alias ZSTD_lazy2 = ZSTD_strategy.ZSTD_lazy2;
alias ZSTD_btlazy2 = ZSTD_strategy.ZSTD_btlazy2;
alias ZSTD_btopt = ZSTD_strategy.ZSTD_btopt;
alias ZSTD_btultra = ZSTD_strategy.ZSTD_btultra;
alias ZSTD_btultra2 = ZSTD_strategy.ZSTD_btultra2;

enum ZSTD_cParameter
{
    ZSTD_c_compressionLevel = 100,
    ZSTD_c_windowLog = 101,
    ZSTD_c_hashLog = 102,
    ZSTD_c_chainLog = 103,
    ZSTD_c_searchLog = 104,
    ZSTD_c_minMatch = 105,
    ZSTD_c_targetLength = 106,
    ZSTD_c_strategy = 107,
    ZSTD_c_targetCBlockSize = 130,
    ZSTD_c_enableLongDistanceMatching = 160,
    ZSTD_c_ldmHashLog = 161,
    ZSTD_c_ldmMinMatch = 162,
    ZSTD_c_ldmBucketSizeLog = 163,
    ZSTD_c_ldmHashRateLog = 164,
    ZSTD_c_contentSizeFlag = 200,
    ZSTD_c_checksumFlag = 201,
    ZSTD_c_dictIDFlag = 202,
    ZSTD_c_nbWorkers = 400,
    ZSTD_c_jobSize = 401,
    ZSTD_c_overlapLog = 402,
    ZSTD_c_experimentalParam1 = 500,
    ZSTD_c_experimentalParam2 = 10,
    ZSTD_c_experimentalParam3 = 1000,
    ZSTD_c_experimentalParam4 = 1001,
    ZSTD_c_experimentalParam5 = 1002,
    ZSTD_c_experimentalParam7 = 1004,
    ZSTD_c_experimentalParam8 = 1005,
    ZSTD_c_experimentalParam9 = 1006,
    ZSTD_c_experimentalParam10 = 1007,
    ZSTD_c_experimentalParam11 = 1008,
    ZSTD_c_experimentalParam12 = 1009,
    ZSTD_c_experimentalParam13 = 1010,
    ZSTD_c_experimentalParam14 = 1011,
    ZSTD_c_experimentalParam15 = 1012,
    ZSTD_c_experimentalParam16 = 1013,
    ZSTD_c_experimentalParam17 = 1014,
    ZSTD_c_experimentalParam18 = 1015,
    ZSTD_c_experimentalParam19 = 1016,
    ZSTD_c_experimentalParam20 = 1017
}

alias ZSTD_c_compressionLevel = ZSTD_cParameter.ZSTD_c_compressionLevel;
alias ZSTD_c_windowLog = ZSTD_cParameter.ZSTD_c_windowLog;
alias ZSTD_c_hashLog = ZSTD_cParameter.ZSTD_c_hashLog;
alias ZSTD_c_chainLog = ZSTD_cParameter.ZSTD_c_chainLog;
alias ZSTD_c_searchLog = ZSTD_cParameter.ZSTD_c_searchLog;
alias ZSTD_c_minMatch = ZSTD_cParameter.ZSTD_c_minMatch;
alias ZSTD_c_targetLength = ZSTD_cParameter.ZSTD_c_targetLength;
alias ZSTD_c_strategy = ZSTD_cParameter.ZSTD_c_strategy;
alias ZSTD_c_targetCBlockSize = ZSTD_cParameter.ZSTD_c_targetCBlockSize;
alias ZSTD_c_enableLongDistanceMatching = ZSTD_cParameter.ZSTD_c_enableLongDistanceMatching;
alias ZSTD_c_ldmHashLog = ZSTD_cParameter.ZSTD_c_ldmHashLog;
alias ZSTD_c_ldmMinMatch = ZSTD_cParameter.ZSTD_c_ldmMinMatch;
alias ZSTD_c_ldmBucketSizeLog = ZSTD_cParameter.ZSTD_c_ldmBucketSizeLog;
alias ZSTD_c_ldmHashRateLog = ZSTD_cParameter.ZSTD_c_ldmHashRateLog;
alias ZSTD_c_contentSizeFlag = ZSTD_cParameter.ZSTD_c_contentSizeFlag;
alias ZSTD_c_checksumFlag = ZSTD_cParameter.ZSTD_c_checksumFlag;
alias ZSTD_c_dictIDFlag = ZSTD_cParameter.ZSTD_c_dictIDFlag;
alias ZSTD_c_nbWorkers = ZSTD_cParameter.ZSTD_c_nbWorkers;
alias ZSTD_c_jobSize = ZSTD_cParameter.ZSTD_c_jobSize;
alias ZSTD_c_overlapLog = ZSTD_cParameter.ZSTD_c_overlapLog;

struct ZSTD_bounds
{
    size_t error;
    int lowerBound;
    int upperBound;
}

/*! ZSTD_cParam_getBounds() :
 *  All parameters must belong to an interval with lower and upper bounds. */
ZSTD_bounds ZSTD_cParam_getBounds(ZSTD_cParameter cParam);

/*! ZSTD_CCtx_setParameter() :
 *  Set one compression parameter, selected by enum ZSTD_cParameter.
 * @return : an error code (which can be tested using ZSTD_isError()). */
size_t ZSTD_CCtx_setParameter(ZSTD_CCtx* cctx, ZSTD_cParameter param, int value);

/*! ZSTD_CCtx_setPledgedSrcSize() :
 *  Total input data size to be compressed as a single frame.
 * @result : 0, or an error code (which can be tested with ZSTD_isError()). */
size_t ZSTD_CCtx_setPledgedSrcSize(ZSTD_CCtx* cctx, ulong pledgedSrcSize);

enum ZSTD_ResetDirective
{
    ZSTD_reset_session_only = 1,
    ZSTD_reset_parameters = 2,
    ZSTD_reset_session_and_parameters = 3
}

alias ZSTD_reset_session_only = ZSTD_ResetDirective.ZSTD_reset_session_only;
alias ZSTD_reset_parameters = ZSTD_ResetDirective.ZSTD_reset_parameters;
alias ZSTD_reset_session_and_parameters = ZSTD_ResetDirective.ZSTD_reset_session_and_parameters;

/*! ZSTD_CCtx_reset() :
 *  Reset the session and/or parameters of a compression context. */
size_t ZSTD_CCtx_reset(ZSTD_CCtx* cctx, ZSTD_ResetDirective reset);

/*! ZSTD_compress2() :
 *  Behave the same as ZSTD_compressCCtx(), but compression parameters are set using the advanced API. */
size_t ZSTD_compress2(ZSTD_CCtx* cctx,
        void* dst, size_t dstCapacity,
        const(void)* src, size_t srcSize);

/***********************************************
*  Advanced decompression API (Requires v1.4.0+)
************************************************/

enum ZSTD_dParameter
{
    ZSTD_d_windowLogMax = 100,
    ZSTD_d_experimentalParam1 = 1000,
    ZSTD_d_experimentalParam2 = 1001,
    ZSTD_d_experimentalParam3 = 1002,
    ZSTD_d_experimentalParam4 = 1003,
    ZSTD_d_experimentalParam5 = 1004,
    ZSTD_d_experimentalParam6 = 1005
}

alias ZSTD_d_windowLogMax = ZSTD_dParameter.ZSTD_d_windowLogMax;

/*! ZSTD_dParam_getBounds() :
 *  All parameters must belong to an interval with lower and upper bounds. */
ZSTD_bounds ZSTD_dParam_getBounds(ZSTD_dParameter dParam);

/*! ZSTD_DCtx_setParameter() :
 *  Set one decompression parameter, selected by enum ZSTD_dParameter.
 * @return : 0, or an error code (which can be tested using ZSTD_isError()). */
size_t ZSTD_DCtx_setParameter(ZSTD_DCtx* dctx, ZSTD_dParameter param, int value);

/*! ZSTD_DCtx_reset() :
 *  Return a DCtx to clean state. */
size_t ZSTD_DCtx_reset(ZSTD_DCtx* dctx, ZSTD_ResetDirective reset);

/****************************
*  Streaming
****************************/

struct ZSTD_inBuffer
{
    const(void)* src; /**< start of input buffer */
    size_t size; /**< size of input buffer */
    size_t pos; /**< position where reading stopped. Will be updated. Necessarily 0 <= pos <= size */
}

struct ZSTD_outBuffer
{
    void* dst; /**< start of output buffer */
    size_t size; /**< size of output buffer */
    size_t pos; /**< position where writing stopped. Will be updated. Necessarily 0 <= pos <= size */
}

/*-***********************************************************************
*  Streaming compression
************************************************************************/
alias ZSTD_CStream = ZSTD_CCtx; /**< CCtx and CStream are the same object (>= v1.3.0) */

/*===== ZSTD_CStream management functions =====*/
ZSTD_CStream* ZSTD_createCStream();
size_t ZSTD_freeCStream(ZSTD_CStream* zcs); /* accept NULL pointer */

/*===== Streaming compression functions =====*/
enum ZSTD_EndDirective
{
    ZSTD_e_continue = 0,
    ZSTD_e_flush = 1,
    ZSTD_e_end = 2
}

alias ZSTD_e_continue = ZSTD_EndDirective.ZSTD_e_continue;
alias ZSTD_e_flush = ZSTD_EndDirective.ZSTD_e_flush;
alias ZSTD_e_end = ZSTD_EndDirective.ZSTD_e_end;

/*! ZSTD_compressStream2() : Requires v1.4.0+
 *  Streaming compression with explicit control over the end directive. */
size_t ZSTD_compressStream2(ZSTD_CCtx* cctx,
        ZSTD_outBuffer* output,
        ZSTD_inBuffer* input,
        ZSTD_EndDirective endOp);

/**< recommended size for input buffer */
size_t ZSTD_CStreamInSize();
/**< recommended size for output buffer. Guarantee to successfully flush at least one complete compressed block. */
size_t ZSTD_CStreamOutSize();

/* Legacy streaming API, redundant but fully supported. */
size_t ZSTD_initCStream(ZSTD_CStream* zcs, int compressionLevel);
size_t ZSTD_compressStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output, ZSTD_inBuffer* input);
size_t ZSTD_flushStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output);
size_t ZSTD_endStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output);

/*-***************************************************************************
*  Streaming decompression
****************************************************************************/
alias ZSTD_DStream = ZSTD_DCtx; /**< DCtx and DStream are the same object (>= v1.3.0) */

/*===== ZSTD_DStream management functions =====*/
ZSTD_DStream* ZSTD_createDStream();
size_t ZSTD_freeDStream(ZSTD_DStream* zds); /* accept NULL pointer */

/*===== Streaming decompression functions =====*/
size_t ZSTD_initDStream(ZSTD_DStream* zds);
size_t ZSTD_decompressStream(ZSTD_DStream* zds, ZSTD_outBuffer* output, ZSTD_inBuffer* input);

/*!< recommended size for input buffer */
size_t ZSTD_DStreamInSize();
/*!< recommended size for output buffer. */
size_t ZSTD_DStreamOutSize();

/**************************
*  Simple dictionary API
***************************/
/*! ZSTD_compress_usingDict() :
 *  Compression at an explicit compression level using a Dictionary. */
size_t ZSTD_compress_usingDict(ZSTD_CCtx* ctx,
        void* dst, size_t dstCapacity,
        const(void)* src, size_t srcSize,
        const(void)* dict, size_t dictSize,
        int compressionLevel);

/*! ZSTD_decompress_usingDict() :
 *  Decompression using a known Dictionary. */
size_t ZSTD_decompress_usingDict(ZSTD_DCtx* dctx,
        void* dst, size_t dstCapacity,
        const(void)* src, size_t srcSize,
        const(void)* dict, size_t dictSize);

/***********************************
 *  Bulk processing dictionary API
 **********************************/
struct ZSTD_CDict_s;
alias ZSTD_CDict = ZSTD_CDict_s;

/*! ZSTD_createCDict() :
 *  Digest a dictionary once for reuse across many compressions. */
ZSTD_CDict* ZSTD_createCDict(const(void)* dictBuffer, size_t dictSize,
        int compressionLevel);

/*! ZSTD_freeCDict() : accepts NULL. */
size_t ZSTD_freeCDict(ZSTD_CDict* CDict);

/*! ZSTD_compress_usingCDict() :
 *  Compression using a digested Dictionary. */
size_t ZSTD_compress_usingCDict(ZSTD_CCtx* cctx,
        void* dst, size_t dstCapacity,
        const(void)* src, size_t srcSize,
        const(ZSTD_CDict)* cdict);

struct ZSTD_DDict_s;
alias ZSTD_DDict = ZSTD_DDict_s;

/*! ZSTD_createDDict() :
 *  Create a digested dictionary for decompression without startup delay. */
ZSTD_DDict* ZSTD_createDDict(const(void)* dictBuffer, size_t dictSize);

/*! ZSTD_freeDDict() : accepts NULL. */
size_t ZSTD_freeDDict(ZSTD_DDict* ddict);

/*! ZSTD_decompress_usingDDict() :
 *  Decompression using a digested Dictionary. */
size_t ZSTD_decompress_usingDDict(ZSTD_DCtx* dctx,
        void* dst, size_t dstCapacity,
        const(void)* src, size_t srcSize,
        const(ZSTD_DDict)* ddict);

/********************************
 *  Dictionary helper functions
 *******************************/

/*! ZSTD_getDictID_fromDict() : Requires v1.4.0+ */
uint ZSTD_getDictID_fromDict(const(void)* dict, size_t dictSize);

/*! ZSTD_getDictID_fromCDict() : Requires v1.5.0+ */
uint ZSTD_getDictID_fromCDict(const(ZSTD_CDict)* cdict);

/*! ZSTD_getDictID_fromDDict() : Requires v1.4.0+ */
uint ZSTD_getDictID_fromDDict(const(ZSTD_DDict)* ddict);

/*! ZSTD_getDictID_fromFrame() : Requires v1.4.0+ */
uint ZSTD_getDictID_fromFrame(const(void)* src, size_t srcSize);

/*******************************************************************************
 * Advanced dictionary and prefix API (Requires v1.4.0+)
 ******************************************************************************/

/*! ZSTD_CCtx_loadDictionary() : Requires v1.4.0+ */
size_t ZSTD_CCtx_loadDictionary(ZSTD_CCtx* cctx, const(void)* dict, size_t dictSize);

/*! ZSTD_CCtx_refCDict() : Requires v1.4.0+ */
size_t ZSTD_CCtx_refCDict(ZSTD_CCtx* cctx, const(ZSTD_CDict)* cdict);

/*! ZSTD_CCtx_refPrefix() : Requires v1.4.0+ */
size_t ZSTD_CCtx_refPrefix(ZSTD_CCtx* cctx,
        const(void)* prefix, size_t prefixSize);

/*! ZSTD_DCtx_loadDictionary() : Requires v1.4.0+ */
size_t ZSTD_DCtx_loadDictionary(ZSTD_DCtx* dctx, const(void)* dict, size_t dictSize);

/*! ZSTD_DCtx_refDDict() : Requires v1.4.0+ */
size_t ZSTD_DCtx_refDDict(ZSTD_DCtx* dctx, const(ZSTD_DDict)* ddict);

/*! ZSTD_DCtx_refPrefix() : Requires v1.4.0+ */
size_t ZSTD_DCtx_refPrefix(ZSTD_DCtx* dctx,
        const(void)* prefix, size_t prefixSize);

/* ===   Memory management   === */

/*! ZSTD_sizeof_*() : Requires v1.4.0+
 *  These functions give the _current_ memory usage of selected object. */
size_t ZSTD_sizeof_CCtx(const(ZSTD_CCtx)* cctx);
size_t ZSTD_sizeof_DCtx(const(ZSTD_DCtx)* dctx);
size_t ZSTD_sizeof_CStream(const(ZSTD_CStream)* zcs);
size_t ZSTD_sizeof_DStream(const(ZSTD_DStream)* zds);
size_t ZSTD_sizeof_CDict(const(ZSTD_CDict)* cdict);
size_t ZSTD_sizeof_DDict(const(ZSTD_DDict)* ddict);
