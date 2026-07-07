/**
 * Raw C bindings for `zstd_errors.h` (Zstandard error codes).
 *
 * This is a hand-translated 1:1 binding of the stable public error API from
 * Meta's Zstandard library. It declares the `ZSTD_ErrorCode` enumeration and
 * the `ZSTD_getErrorString()` entry point. The symbols are resolved from the
 * statically linked zstd library.
 *
 * Prefer the D-native `zstd` wrapper package for idiomatic usage; this module
 * exists for callers that need direct access to the C API.
 *
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module etc.c.zstd.zstd_errors;

extern (C):
nothrow:
@nogc:

/*-*********************************************
 *  Error codes list
 *-*********************************************
 *  Error codes _values_ are pinned down since v1.3.1 only.
 *  Only values < 100 are considered stable.
 *  Prefer relying on the enum than on its value whenever possible.
 *  ZSTD_isError() is always correct, whatever the library version.
 **********************************************/
enum ZSTD_ErrorCode
{
    ZSTD_error_no_error = 0,
    ZSTD_error_GENERIC = 1,
    ZSTD_error_prefix_unknown = 10,
    ZSTD_error_version_unsupported = 12,
    ZSTD_error_frameParameter_unsupported = 14,
    ZSTD_error_frameParameter_windowTooLarge = 16,
    ZSTD_error_corruption_detected = 20,
    ZSTD_error_checksum_wrong = 22,
    ZSTD_error_literals_headerWrong = 24,
    ZSTD_error_dictionary_corrupted = 30,
    ZSTD_error_dictionary_wrong = 32,
    ZSTD_error_dictionaryCreation_failed = 34,
    ZSTD_error_parameter_unsupported = 40,
    ZSTD_error_parameter_combination_unsupported = 41,
    ZSTD_error_parameter_outOfBound = 42,
    ZSTD_error_tableLog_tooLarge = 44,
    ZSTD_error_maxSymbolValue_tooLarge = 46,
    ZSTD_error_maxSymbolValue_tooSmall = 48,
    ZSTD_error_cannotProduce_uncompressedBlock = 49,
    ZSTD_error_stabilityCondition_notRespected = 50,
    ZSTD_error_stage_wrong = 60,
    ZSTD_error_init_missing = 62,
    ZSTD_error_memory_allocation = 64,
    ZSTD_error_workSpace_tooSmall = 66,
    ZSTD_error_dstSize_tooSmall = 70,
    ZSTD_error_srcSize_wrong = 72,
    ZSTD_error_dstBuffer_null = 74,
    ZSTD_error_noForwardProgress_destFull = 80,
    ZSTD_error_noForwardProgress_inputEmpty = 82,
    /* following error codes are __NOT STABLE__, they can be removed or changed in future versions */
    ZSTD_error_frameIndex_tooLarge = 100,
    ZSTD_error_seekableIO = 102,
    ZSTD_error_dstBuffer_wrong = 104,
    ZSTD_error_srcBuffer_wrong = 105,
    ZSTD_error_sequenceProducer_failed = 106,
    ZSTD_error_externalSequences_invalid = 107,
    ZSTD_error_maxCode = 120 /* never EVER use this value directly, it can change in future versions! Use ZSTD_isError() instead */
}

/* Global aliases so the C enumerator names are available unqualified,
 * mirroring how the constants are exposed in C. */
alias ZSTD_error_no_error = ZSTD_ErrorCode.ZSTD_error_no_error;
alias ZSTD_error_GENERIC = ZSTD_ErrorCode.ZSTD_error_GENERIC;
alias ZSTD_error_prefix_unknown = ZSTD_ErrorCode.ZSTD_error_prefix_unknown;
alias ZSTD_error_version_unsupported = ZSTD_ErrorCode.ZSTD_error_version_unsupported;
alias ZSTD_error_frameParameter_unsupported = ZSTD_ErrorCode.ZSTD_error_frameParameter_unsupported;
alias ZSTD_error_frameParameter_windowTooLarge = ZSTD_ErrorCode.ZSTD_error_frameParameter_windowTooLarge;
alias ZSTD_error_corruption_detected = ZSTD_ErrorCode.ZSTD_error_corruption_detected;
alias ZSTD_error_checksum_wrong = ZSTD_ErrorCode.ZSTD_error_checksum_wrong;
alias ZSTD_error_literals_headerWrong = ZSTD_ErrorCode.ZSTD_error_literals_headerWrong;
alias ZSTD_error_dictionary_corrupted = ZSTD_ErrorCode.ZSTD_error_dictionary_corrupted;
alias ZSTD_error_dictionary_wrong = ZSTD_ErrorCode.ZSTD_error_dictionary_wrong;
alias ZSTD_error_dictionaryCreation_failed = ZSTD_ErrorCode.ZSTD_error_dictionaryCreation_failed;
alias ZSTD_error_parameter_unsupported = ZSTD_ErrorCode.ZSTD_error_parameter_unsupported;
alias ZSTD_error_parameter_combination_unsupported = ZSTD_ErrorCode.ZSTD_error_parameter_combination_unsupported;
alias ZSTD_error_parameter_outOfBound = ZSTD_ErrorCode.ZSTD_error_parameter_outOfBound;
alias ZSTD_error_tableLog_tooLarge = ZSTD_ErrorCode.ZSTD_error_tableLog_tooLarge;
alias ZSTD_error_maxSymbolValue_tooLarge = ZSTD_ErrorCode.ZSTD_error_maxSymbolValue_tooLarge;
alias ZSTD_error_maxSymbolValue_tooSmall = ZSTD_ErrorCode.ZSTD_error_maxSymbolValue_tooSmall;
alias ZSTD_error_cannotProduce_uncompressedBlock = ZSTD_ErrorCode.ZSTD_error_cannotProduce_uncompressedBlock;
alias ZSTD_error_stabilityCondition_notRespected = ZSTD_ErrorCode.ZSTD_error_stabilityCondition_notRespected;
alias ZSTD_error_stage_wrong = ZSTD_ErrorCode.ZSTD_error_stage_wrong;
alias ZSTD_error_init_missing = ZSTD_ErrorCode.ZSTD_error_init_missing;
alias ZSTD_error_memory_allocation = ZSTD_ErrorCode.ZSTD_error_memory_allocation;
alias ZSTD_error_workSpace_tooSmall = ZSTD_ErrorCode.ZSTD_error_workSpace_tooSmall;
alias ZSTD_error_dstSize_tooSmall = ZSTD_ErrorCode.ZSTD_error_dstSize_tooSmall;
alias ZSTD_error_srcSize_wrong = ZSTD_ErrorCode.ZSTD_error_srcSize_wrong;
alias ZSTD_error_dstBuffer_null = ZSTD_ErrorCode.ZSTD_error_dstBuffer_null;
alias ZSTD_error_noForwardProgress_destFull = ZSTD_ErrorCode.ZSTD_error_noForwardProgress_destFull;
alias ZSTD_error_noForwardProgress_inputEmpty = ZSTD_ErrorCode.ZSTD_error_noForwardProgress_inputEmpty;
alias ZSTD_error_frameIndex_tooLarge = ZSTD_ErrorCode.ZSTD_error_frameIndex_tooLarge;
alias ZSTD_error_seekableIO = ZSTD_ErrorCode.ZSTD_error_seekableIO;
alias ZSTD_error_dstBuffer_wrong = ZSTD_ErrorCode.ZSTD_error_dstBuffer_wrong;
alias ZSTD_error_srcBuffer_wrong = ZSTD_ErrorCode.ZSTD_error_srcBuffer_wrong;
alias ZSTD_error_sequenceProducer_failed = ZSTD_ErrorCode.ZSTD_error_sequenceProducer_failed;
alias ZSTD_error_externalSequences_invalid = ZSTD_ErrorCode.ZSTD_error_externalSequences_invalid;
alias ZSTD_error_maxCode = ZSTD_ErrorCode.ZSTD_error_maxCode;

/**< Same as ZSTD_getErrorName, but using a `ZSTD_ErrorCode` enum argument */
const(char)* ZSTD_getErrorString(ZSTD_ErrorCode code);
