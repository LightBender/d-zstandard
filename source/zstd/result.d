/**
 * A lightweight result type for the D-native Zstandard wrapper.
 *
 * Zstandard reports outcomes through `size_t` return codes: a value that is
 * either a meaningful size, or an error code that can be recognised with
 * `ZSTD_isError()`. This module mirrors that model with a `Result` value type
 * so wrapper functions can return either a value or rich error information
 * without throwing.
 *
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module zstd.result;

import etc.c.zstd.zstd : ZSTD_getErrorCode, ZSTD_getErrorName, ZSTD_isError;
import etc.c.zstd.zstd_errors : ZSTD_ErrorCode;

/**
 * A decoded Zstandard error: the stable error code plus a human-readable
 * message obtained from the library.
 */
struct ZstdError
{
    /// The Zstandard error code (see `ZSTD_ErrorCode`).
    ZSTD_ErrorCode code;

    /// The human-readable message reported by `ZSTD_getErrorName`.
    string message;
}

/**
 * Returns `true` when a raw Zstandard `size_t` return value represents an
 * error code rather than a valid result.
 */
bool isZstdError(size_t returnCode) @trusted nothrow @nogc
{
    return ZSTD_isError(returnCode) != 0;
}

/**
 * Decodes a raw Zstandard `size_t` return code into a `ZstdError`, resolving
 * both the stable error code and its message.
 */
ZstdError toZstdError(size_t returnCode) @trusted
{
    import std.string : fromStringz;

    const code = ZSTD_getErrorCode(returnCode);
    auto namez = ZSTD_getErrorName(returnCode);
    string message = namez is null ? "unknown zstd error" : fromStringz(namez).idup;
    return ZstdError(code, message);
}

/**
 * The outcome of a Zstandard operation.
 *
 * Carries either a success value of type `T`, or a decoded `ZstdError`. Use
 * `Result!void` for operations that produce no value.
 */
struct Result(T)
{
    private bool _ok = true;
    private ZstdError _error;

    static if (!is(T == void))
        private T _value;

    /// Constructs a successful result.
    static if (!is(T == void))
    {
        /// Constructs a successful result wrapping `value`.
        ///
        /// The value is moved into the result, so non-copyable values (such as
        /// the RAII context handles) can be passed with `core.lifetime.move`.
        static Result ok(T value)
        {
            import core.lifetime : move;

            Result r;
            r._ok = true;
            r._value = move(value);
            return r;
        }
    }
    else
    {
        /// Constructs a successful result carrying no value.
        static Result ok() @safe
        {
            Result r;
            r._ok = true;
            return r;
        }
    }

    /// Constructs a failed result from a decoded error.
    static Result err(ZstdError error) @safe
    {
        Result r;
        r._ok = false;
        r._error = error;
        return r;
    }

    /// Constructs a failed result from a raw Zstandard return code.
    static Result err(size_t returnCode) @trusted
    {
        return err(toZstdError(returnCode));
    }

    /// `true` if the operation succeeded.
    bool isOk() const @nogc nothrow pure @safe
    {
        return _ok;
    }

    /// `true` if the operation failed.
    bool isErr() const @nogc nothrow pure @safe
    {
        return !_ok;
    }

    /// Allows `if (result)` to test for success.
    bool opCast(B : bool)() const @nogc nothrow pure @safe
    {
        return _ok;
    }

    static if (!is(T == void))
    {
        /// The success value. Only meaningful when `isOk` is `true`.
        ref inout(T) value() inout @nogc nothrow pure @safe
        {
            return _value;
        }
    }

    /// The decoded error (default-initialised on success).
    ZstdError error() const @nogc nothrow pure @safe
    {
        return _error;
    }

    /// The Zstandard error code (`ZSTD_error_no_error` on success).
    ZSTD_ErrorCode code() const @nogc nothrow pure @safe
    {
        return _error.code;
    }

    /// The human-readable error message (`null` on success).
    string message() const @nogc nothrow pure @safe
    {
        return _error.message;
    }
}

@safe unittest
{
    auto ok = Result!int.ok(42);
    assert(ok.isOk);
    assert(!ok.isErr);
    assert(ok.value == 42);
    assert(cast(bool) ok);
    assert(ok.message is null);
    assert(ok.code == ZSTD_ErrorCode.ZSTD_error_no_error);
}

@safe unittest
{
    auto err = Result!int.err(ZstdError(ZSTD_ErrorCode.ZSTD_error_dstSize_tooSmall, "Destination buffer is too small"));
    assert(err.isErr);
    assert(!err.isOk);
    assert(!cast(bool) err);
    assert(err.code == ZSTD_ErrorCode.ZSTD_error_dstSize_tooSmall);
    assert(err.message == "Destination buffer is too small");
}

@safe unittest
{
    // Result!void for operations that produce no value.
    auto ok = Result!void.ok();
    assert(ok.isOk);

    auto err = Result!void.err(ZstdError(ZSTD_ErrorCode.ZSTD_error_GENERIC, "generic"));
    assert(err.isErr);
    assert(err.code == ZSTD_ErrorCode.ZSTD_error_GENERIC);
}
