# ZStandard for D

`d-zstd` provides D bindings and a lightweight, D-native wrapper for
[Zstandard](https://github.com/facebook/zstd) (zstd), Meta's fast lossless
compression library. The upstream zstd sources are vendored as a git submodule
and compiled into a static object at build time, so there is no external runtime
dependency to install.

The package exposes two layers:

- **`etc.c.zstd.*`** — a hand-translated 1:1 binding of the stable zstd C API
  (`zstd.h`, `zdict.h`, `zstd_errors.h`), for callers who want the C interface.
- **`zstd`** — an idiomatic D wrapper that works with slices and returns a
  `Result` type carrying either a value or a decoded error, so you never have to
  marshal buffers or check raw error codes by hand.

## Features

- **D-native API** — compress and decompress `ubyte[]` slices directly.
- **`Result`-based error handling** — no exceptions; every operation returns a
  `Result!T` with `isOk` / `isErr`, the value, and a human-readable message.
- **Full stable API** — one-shot, streaming, and dictionary compression, plus
  reusable `Compressor` / `Decompressor` contexts and dictionary training.
- **Self-contained builds** — zstd is amalgamated and compiled locally; the
  build detects when it is already up to date and only rebuilds when the zstd
  submodule or the build scripts change.
- **Cross-platform** — Windows, Linux, macOS, and FreeBSD.

## Requirements

- A D compiler (DMD or LDC) and DUB.
- The zstd submodule. If you cloned without submodules, run:

  ```sh
  git submodule update --init
  ```

- A C toolchain for building the native zstd object:
  - The build first tries the D compiler's **ImportC**.
  - If ImportC cannot compile the amalgamation (for example, on Windows where
    zstd relies on MSVC intrinsics), it automatically falls back to the native C
    compiler: **MSVC** (`cl`, located automatically via Visual Studio) on
    Windows, or **cc/gcc/clang** on POSIX. On Windows this means a Visual Studio
    (or Build Tools) installation with the C++ workload is required.

## Installation

Add `d-zstd` to your project using DUB:

```sh
dub add d-zstd
```

Or add it to your `dub.sdl`:

```
dependency "d-zstd" version="~>1.0.0"
```

The first build runs a pre-generate step that amalgamates and compiles zstd into
`lib/<os>-<arch>/`. Subsequent builds reuse the cached object and skip
recompilation until the zstd submodule commit or the build scripts change (this
is tracked with a `.build-stamp` file next to the object).

## Usage

### D-native API

One-shot compression and decompression:

```d
import zstd;
import std.stdio;

void main()
{
    ubyte[] data = cast(ubyte[]) "some data to compress".dup;

    auto compressed = compress(data, 9); // level 9
    if (compressed.isErr)
    {
        writeln("compress failed: ", compressed.message);
        return;
    }

    auto restored = decompress(compressed.value);
    if (restored.isErr)
    {
        writeln("decompress failed: ", restored.message);
        return;
    }

    assert(restored.value == data);
}
```

Reusable contexts (advanced parameters, dictionaries, and streaming) via
`Compressor` / `Decompressor`:

```d
import zstd;

auto cr = createCompressor();
if (cr.isErr) { /* handle */ }
cr.value.setCompressionLevel(19);
auto compressed = cr.value.compress(data);
```

Dictionary training and dictionary-based compression:

```d
import zstd;

auto trained = trainDictionary(samples, 100 * 1024); // samples is ubyte[][]
auto cdict = createCompressionDictionary(trained.value, 3);
auto ddict = createDecompressionDictionary(trained.value);

auto packed = compressWithDictionary(record, cdict.value);
auto original = decompressWithDictionary(packed.value, ddict.value);
```

### Raw C API

The full zstd C API is available directly if you prefer it:

```d
import etc.c.zstd.zstd;
import std.string : fromStringz;

ubyte[] src = cast(ubyte[]) "hello".dup;
auto dst = new ubyte[ZSTD_compressBound(src.length)];
const n = ZSTD_compress(dst.ptr, dst.length, src.ptr, src.length, 3);
if (ZSTD_isError(n))
    writeln(fromStringz(ZSTD_getErrorName(n)));
```

### Examples

Runnable examples live in [`examples/`](examples/) and are wired up as DUB
subpackages:

```sh
dub run :simple        # one-shot compress/decompress (D API)
dub run :streaming     # streaming compression (D API)
dub run :dictionary    # dictionary training and use (D API)
dub run :raw-c         # the raw C API through etc.c.zstd
```

## Supported platforms

| OS      | x86 | x86_64 | arm64 (aarch64) |
| ------- | --- | ------ | --------------- |
| Windows | ✓   | ✓      | ✓ (cross)       |
| Linux   | ✓   | ✓      | ✓ (cross)       |
| macOS   | —   | ✓      | ✓               |
| FreeBSD | ✓   | ✓      | ✓ (cross)       |

Architectures other than the host require the appropriate cross toolchain to be
installed; the build reports a clear error when one is missing.

## How the native build works

The build orchestrator is a single cross-platform D script,
[`buildscripts/build_zstd.d`](buildscripts/build_zstd.d), run by DUB as a
`preGenerateCommands` step. It:

1. Detects the target OS/architecture (honouring DUB's `$DUB_ARCH`).
2. Computes a stamp from the zstd submodule commit, the build scripts, and the
   compiler, and skips the build when the existing object is up to date.
3. Amalgamates the zstd sources into a single C file using a D port of zstd's
   `combine.py` ([`buildscripts/combine.d`](buildscripts/combine.d)) — no Python
   required.
4. Builds a single object file, trying ImportC first and falling back to the
   native C toolchain, verifying the result with a test link.

## Contributing

Contributions are welcome via Pull Requests.

**LLM guideline:** If you use a Large Language Model (GitHub Copilot, ChatGPT,
Claude, etc.) to generate or substantially assist with your contribution, you
**must** include the exact prompt(s) you used in the [`PROMPTS.txt`](PROMPTS.txt)
file at the root of the repository.

## License

This project is licensed under the Boost Software License 1.0. See the
[`LICENSE`](LICENSE) file for details. Vendored Zstandard is licensed under the
BSD-3-Clause and GPLv2 licenses (see [`zstd/LICENSE`](zstd/LICENSE)).

