/**
 * Native build orchestrator for the vendored Zstandard sources.
 *
 * Run by dub as a pre-generate step (see dub.sdl). Responsibilities:
 * $(UL
 *   $(LI Ensure the vendored zstd git submodule is initialized.)
 *   $(LI Detect the target OS/architecture (honouring dub's `$DUB_ARCH`).)
 *   $(LI Compute a build stamp from the zstd submodule commit, the build
 *        scripts, and the compiler, and skip rebuilding when it is unchanged.)
 *   $(LI Amalgamate the zstd sources into a single C file (via `combine.d`).)
 *   $(LI Build a static library: on Windows prefer MSVC (ImportC cannot resolve
 *        MSVC/Windows SDK intrinsics), otherwise prefer ImportC and fall back
 *        to the native C toolchain.)
 * )
 *
 * The resulting library is written to `lib/<os>-<arch>/` and consumed by dub.
 *
 * Usage: rdmd -Ibuildscripts buildscripts/build_zstd.d
 *
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module buildscripts.build_zstd;

import std.algorithm : canFind, startsWith;
import std.array : join, split;
import std.digest.md : MD5, toHexString;
import std.file;
import std.path;
import std.process;
import std.stdio;
import std.string : strip, splitLines;

import buildscripts.combine;

enum logPrefix = "[build_zstd] ";

void log(Args...)(Args args)
{
    stderr.writeln(logPrefix, args);
}

int main()
{
    const root = getcwd();
    // DUB may rewrite dub.sdl as dub.json when the package is used as a dependency.
    if (!exists(buildPath(root, "dub.sdl")) && !exists(buildPath(root, "dub.json")))
    {
        log("error: must be run from the package root (neither dub.sdl nor dub.json found in ", root, ")");
        return 1;
    }

    const zstdDir = buildPath(root, "zstd");
    if (!ensureZstdSubmodule(root, zstdDir))
        return 1;

    const zstdLib = buildPath(zstdDir, "lib");
    const os = detectOS();
    const arch = detectArch();
    const osArch = os ~ "-" ~ arch;
    const libDir = buildPath(root, "lib", osArch);
    const isWindows = os == "windows";
    // A single object file (not an archive): linking a directly-referenced object
    // includes every function, so zstd's internal-linkage helpers resolve. An
    // archive would pull members on demand and leave `static` helpers undefined.
    const objName = isWindows ? "zstd-build.obj" : "zstd-build.o";
    const objPath = buildPath(libDir, objName);
    const stampPath = buildPath(libDir, ".build-stamp");

    log("target: ", osArch);

    const stamp = computeStamp(root, zstdDir, os, arch);
    if (exists(objPath) && exists(stampPath) && readText(stampPath).strip == stamp)
    {
        log("library is up to date: ", objPath.relativePath(root));
        return 0;
    }

    mkdirRecurse(libDir);

    // 1. Amalgamate the zstd sources into a single C file.
    const amalgamDir = buildPath(root, "build", "amalgam");
    mkdirRecurse(amalgamDir);
    const amalgamFile = buildPath(amalgamDir, "zstd.c");
    log("amalgamating zstd sources -> ", amalgamFile.relativePath(root));
    CombineOptions opt;
    opt.roots = [zstdLib];
    opt.excludes = ["legacy/zstd_legacy.h"];
    opt.input = buildPath(zstdDir, "build", "single_file_libs", "zstd-in.c");
    opt.output = amalgamFile;
    amalgamate(opt);

    // 2. Compile the amalgamation. On Windows, MSVC is preferred: ImportC uses
    //    the MSVC preprocessor/headers and emits unresolved MSVC/Windows SDK
    //    intrinsics. Elsewhere ImportC is tried first, then the native C toolchain.
    //    Every candidate object is verified with a test link before acceptance.
    if (isWindows)
    {
        log("Windows target: preferring MSVC for the native zstd object");
        if (buildWithNativeCC(amalgamFile, objPath, arch, isWindows)
                && verifyObject(objPath, arch, isWindows))
        {
            std.file.write(stampPath, stamp);
            log("built via native C toolchain: ", objPath.relativePath(root));
            return 0;
        }
        log("MSVC path unavailable/failed; trying ImportC with a portable shim...");
        if (buildWithImportC(amalgamFile, objPath, arch, isWindows)
                && verifyObject(objPath, arch, isWindows))
        {
            std.file.write(stampPath, stamp);
            log("built via ImportC: ", objPath.relativePath(root));
            return 0;
        }
    }
    else
    {
        if (buildWithImportC(amalgamFile, objPath, arch, isWindows)
                && verifyObject(objPath, arch, isWindows))
        {
            std.file.write(stampPath, stamp);
            log("built via ImportC: ", objPath.relativePath(root));
            return 0;
        }
        log("ImportC path unavailable/failed; trying the native C toolchain...");
        if (buildWithNativeCC(amalgamFile, objPath, arch, isWindows)
                && verifyObject(objPath, arch, isWindows))
        {
            std.file.write(stampPath, stamp);
            log("built via native C toolchain: ", objPath.relativePath(root));
            return 0;
        }
    }

    log("error: failed to build the zstd object for ", osArch, ".");
    if (isWindows)
        log("       ensure the MSVC 'cl' compiler (Visual Studio C++ tools) is available.");
    else
        log("       ensure a D compiler with ImportC support, or a C compiler (cc/gcc/clang), is available.");
    return 1;
}

// Upstream zstd pin used when the package is not a full git checkout
// (e.g. DUB registry / dependency installs, which have no .git metadata).
enum zstdGitUrl = "https://github.com/facebook/zstd.git";
enum zstdPinnedCommit = "f8745da6ff1ad1e7bab384bd1f9d742439278e99"; // v1.5.7

/// Ensures the vendored `zstd` sources are present and usable.
///
/// Order of attempts when `zstd/lib/zstd.h` is missing:
/// $(OL
///   $(LI `git submodule update --init zstd`, if the package root is a git repo.)
///   $(LI Clone `zstdGitUrl` and check out the pinned commit — required for DUB
///        dependency installs, which are not git repositories.)
/// )
/// Returns `true` when the sources are ready.
bool ensureZstdSubmodule(string root, string zstdDir)
{
    const header = buildPath(zstdDir, "lib", "zstd.h");
    if (exists(header))
        return true;

    log("zstd sources not found; attempting to fetch...");

    if (findInPath("git") is null)
    {
        log("error: git is not on PATH; cannot fetch the zstd sources.");
        log("       install git, then re-run the build, or manually place zstd at:");
        log("         ", zstdDir);
        return false;
    }

    // Prefer submodule init for real repository checkouts.
    if (isGitRepo(root))
    {
        log("running git submodule update --init zstd");
        auto r = tryRun(["git", "-C", root, "submodule", "update", "--init", "zstd"]);
        if (r.ran && r.status == 0 && exists(header))
        {
            log("zstd submodule initialized.");
            return true;
        }
        if (r.output.length)
            log(r.output);
        log("submodule update failed or incomplete; falling back to clone");
    }
    else
    {
        // DUB dependency installs are plain trees without .git.
        log("package root is not a git repository (common for DUB dependencies)");
    }

    if (!cloneZstdSources(zstdDir, resolveZstdUrl(root), resolveZstdCommit(root)))
        return false;

    if (!exists(header))
    {
        log("error: zstd sources still missing after fetch (expected ", header, ").");
        return false;
    }

    log("zstd sources ready.");
    return true;
}

/// True when `dir` is inside a git working tree.
bool isGitRepo(string dir)
{
    auto r = tryRun(["git", "-C", dir, "rev-parse", "--is-inside-work-tree"]);
    return r.ran && r.status == 0 && r.output.strip == "true";
}

/// Resolves the zstd remote URL from `.gitmodules` when present.
string resolveZstdUrl(string root)
{
    const gm = buildPath(root, ".gitmodules");
    if (exists(gm))
    {
        foreach (line; readText(gm).splitLines)
        {
            auto t = line.strip;
            if (t.startsWith("url"))
            {
                auto parts = t.split("=");
                if (parts.length >= 2)
                {
                    const url = parts[1 .. $].join("=").strip;
                    if (url.length)
                        return url;
                }
            }
        }
    }
    return zstdGitUrl;
}

/// Resolves the pinned zstd commit: gitlink SHA from the parent repo if
/// available, otherwise the hard-coded pin matching the submodule.
string resolveZstdCommit(string root)
{
    if (isGitRepo(root))
    {
        // `git ls-tree HEAD zstd` → "160000 commit <sha>\tzstd"
        auto r = tryRun(["git", "-C", root, "ls-tree", "HEAD", "zstd"]);
        if (r.ran && r.status == 0)
        {
            auto fields = r.output.strip.split();
            if (fields.length >= 3 && fields[0] == "160000")
                return fields[2];
        }
    }
    return zstdPinnedCommit;
}

/// Clones zstd into `zstdDir` at `commit`. Uses a temporary directory so a
/// failed fetch never leaves a half-populated tree in place.
bool cloneZstdSources(string zstdDir, string url, string commit)
{
    const tmpDir = zstdDir ~ ".fetch-tmp";
    silentRemoveTree(tmpDir);

    log("cloning ", url, " @ ", commit);

    // Shallow fetch of the exact commit (works without a full history).
    mkdirRecurse(tmpDir);
    auto init = tryRun(["git", "-C", tmpDir, "init"]);
    if (!init.ran || init.status != 0)
    {
        logGitFailure("git init", init);
        silentRemoveTree(tmpDir);
        return false;
    }

    auto remote = tryRun(["git", "-C", tmpDir, "remote", "add", "origin", url]);
    if (!remote.ran || remote.status != 0)
    {
        logGitFailure("git remote add", remote);
        silentRemoveTree(tmpDir);
        return false;
    }

    auto fetch = tryRun(["git", "-C", tmpDir, "fetch", "--depth", "1", "origin", commit]);
    if (!fetch.ran || fetch.status != 0)
    {
        // Some hosts/git versions reject shallow fetches of arbitrary SHAs.
        if (fetch.output.length)
            log(fetch.output);
        log("shallow fetch failed; retrying full fetch of ", commit);
        fetch = tryRun(["git", "-C", tmpDir, "fetch", "origin", commit]);
    }
    if (!fetch.ran || fetch.status != 0)
    {
        logGitFailure("git fetch", fetch);
        silentRemoveTree(tmpDir);
        return false;
    }

    auto checkout = tryRun(["git", "-C", tmpDir, "checkout", "--force", "FETCH_HEAD"]);
    if (!checkout.ran || checkout.status != 0)
    {
        logGitFailure("git checkout", checkout);
        silentRemoveTree(tmpDir);
        return false;
    }

    // Replace any incomplete placeholder directory left by an uninited submodule.
    silentRemoveTree(zstdDir);
    try
    {
        rename(tmpDir, zstdDir);
    }
    catch (Exception e)
    {
        log("error: failed to move fetched zstd into place: ", e.msg);
        silentRemoveTree(tmpDir);
        return false;
    }
    return true;
}

void logGitFailure(string step, ProcessResult r)
{
    if (r.output.length)
        log(r.output);
    if (!r.ran)
        log("error: failed to run git during ", step, ". Ensure git is installed and on PATH.");
    else
        log("error: ", step, " failed (exit ", r.status, ").");
}

/// Removes a file or directory tree if present, ignoring errors.
void silentRemoveTree(string path) nothrow
{
    try
    {
        if (!exists(path))
            return;
        if (isDir(path))
            rmdirRecurse(path);
        else
            remove(path);
    }
    catch (Exception)
    {
    }
}

string detectOS()
{
    version (Windows)
        return "windows";
    else version (OSX)
        return "osx";
    else version (linux)
        return "linux";
    else version (FreeBSD)
        return "freebsd";
    else
        return "posix";
}

string detectArch()
{
    auto dubArch = environment.get("DUB_ARCH", "");
    if (dubArch.length)
        return normalizeArch(dubArch);

    version (X86_64)
        return "x86_64";
    else version (X86)
        return "x86";
    else version (AArch64)
        return "aarch64";
    else version (ARM)
        return "arm";
    else
        return "unknown";
}

string normalizeArch(string a)
{
    import std.uni : toLower;

    const l = a.toLower;
    if (l.canFind("aarch64") || l.canFind("arm64"))
        return "aarch64";
    if (l.canFind("x86_64") || l.canFind("amd64"))
        return "x86_64";
    if (l.startsWith("x86") || l.startsWith("i386") || l.startsWith("i686"))
        return "x86";
    return l;
}

/// Flag selecting the target model width for the D / C compilers.
string archModelFlag(string arch)
{
    return arch == "x86" ? "-m32" : "-m64";
}

string computeStamp(string root, string zstdDir, string os, string arch)
{
    const zstdSha = gitHead(zstdDir);
    const scriptHash = hashFiles([
        buildPath(root, "buildscripts", "build_zstd.d"),
        buildPath(root, "buildscripts", "combine.d"),
    ]);
    const compilerId = firstLine(runCapture(["dmd", "--version"]));
    return join([
        "zstd=" ~ zstdSha,
        "scripts=" ~ scriptHash,
        "compiler=" ~ compilerId,
        "target=" ~ os ~ "-" ~ arch,
    ], "\n");
}

string gitHead(string dir)
{
    auto r = execute(["git", "-C", dir, "rev-parse", "HEAD"]);
    return r.status == 0 ? r.output.strip : "unknown";
}

string hashFiles(string[] paths)
{
    MD5 md5;
    md5.start();
    foreach (p; paths)
        if (exists(p))
            md5.put(cast(const(ubyte)[]) read(p));
    return md5.finish().toHexString().idup;
}

string runCapture(string[] cmd)
{
    try
    {
        auto r = execute(cmd);
        return r.status == 0 ? r.output : "";
    }
    catch (Exception)
        return "";
}

string firstLine(string s)
{
    auto lines = s.splitLines;
    return lines.length ? lines[0].strip : "";
}

/// Builds the static library using the D compiler's ImportC support.
///
/// DMD's ImportC uses the platform C preprocessor but its own C compiler, which
/// does not implement MSVC/Windows SDK intrinsics. The shim forces portable C
/// paths (no SIMD, no MSVC bitops, no Windows threading headers) so the object
/// can link with the D toolchain.
bool buildWithImportC(string amalgamFile, string objPath, string arch, bool isWindows)
{
    const dc = environment.get("DMD", "dmd");
    const shimFile = buildPath(dirName(amalgamFile), "zstd_importc.c");
    std.file.write(shimFile, importCShimPrefix(isWindows) ~ cast(string) read(amalgamFile));

    // Drop any previous failed object so a partial ImportC result cannot linger.
    silentRemove(objPath);

    auto cmd = [
        dc, "-c", archModelFlag(arch), "-of=" ~ objPath, shimFile,
    ];
    log("running: ", cmd.join(" "));
    ProcessResult r = tryRun(cmd);
    if (!r.ran)
        return false;
    if (r.status != 0)
    {
        log(r.output);
        silentRemove(objPath);
        return false;
    }
    return exists(objPath);
}

/// Preprocessor prefix prepended to the amalgamation for the ImportC build.
///
/// On Windows, ImportC still sees MSVC headers (`_MSC_VER`, `windows.h`,
/// `intrin.h`) and would otherwise emit unresolved MSVC/SDK symbols. The shim
/// forces zstd's portable C fallbacks and disables the multithreaded path that
/// pulls in `windows.h`.
string importCShimPrefix(bool isWindows)
{
    // Use explicit ~ concatenation (DMD 2.113+ rejects adjacent string literals).
    // Avoid nested WYSIWYG strings so later backtick literals remain valid.
    string s =
        "/* Auto-generated by build_zstd.d for ImportC.\n" ~
        " * Force portable C: no MSVC/SIMD intrinsics that ImportC cannot lower. */\n" ~
        "#define __assume(x) ((void)0)\n" ~
        "#define __inline\n" ~
        "#define __forceinline\n" ~
        "#define ZSTD_NO_INTRINSICS 1\n" ~
        "#define NO_PREFETCH 1\n" ~
        "#define ZSTD_DISABLE_ASM 1\n" ~
        "#define DYNAMIC_BMI2 0\n" ~
        "#define STATIC_BMI2 0\n";
    if (isWindows)
    {
        // Undefine MSVC identity so bits.h/cpu.h take portable branches, and
        // drop multithreading so windows.h is not included under ImportC.
        s ~=
            "#ifdef _MSC_VER\n" ~
            "#undef _MSC_VER\n" ~
            "#endif\n" ~
            "#ifdef _MSC_FULL_VER\n" ~
            "#undef _MSC_FULL_VER\n" ~
            "#endif\n" ~
            "#ifdef ZSTD_MULTITHREAD\n" ~
            "#undef ZSTD_MULTITHREAD\n" ~
            "#endif\n";
    }
    return s;
}

/// Builds the object file using the native C toolchain.
bool buildWithNativeCC(string amalgamFile, string objPath, string arch, bool isWindows)
{
    if (isWindows)
        return buildWithMSVC(amalgamFile, objPath);
    return buildWithPosixCC(amalgamFile, objPath, arch);
}

bool buildWithMSVC(string amalgamFile, string objPath)
{
    const arch = detectArch();
    const vcvars = findVcvarsall();
    if (vcvars is null)
    {
        log("MSVC not found (vcvarsall.bat could not be located via vswhere).");
        return false;
    }
    const vcArch = arch == "x86" ? "x86" : (arch == "aarch64" ? "x64_arm64" : "x64");

    silentRemove(objPath);

    // Run vcvarsall (to populate INCLUDE/LIB/PATH) and cl in one cmd session.
    const batPath = buildPath(dirName(objPath), "zstd_cl_build.bat");
    std.file.write(batPath,
            "@echo off\r\n"
            ~ "call \"" ~ vcvars ~ "\" " ~ vcArch ~ "\r\n"
            ~ "if errorlevel 1 exit /b %ERRORLEVEL%\r\n"
            ~ "cl /nologo /c /O2 /DZSTD_DISABLE_ASM=1 /Fo\"" ~ objPath ~ "\" \"" ~ amalgamFile ~ "\"\r\n"
            ~ "exit /b %ERRORLEVEL%\r\n");
    scope (exit)
        silentRemove(batPath);

    log("running MSVC build via ", vcvars, " (", vcArch, ")");
    auto r = tryRun(["cmd", "/c", batPath]);
    if (!r.ran || r.status != 0)
    {
        if (r.output.length)
            log(r.output);
        silentRemove(objPath);
        return false;
    }
    return exists(objPath);
}

/// Locates `vcvarsall.bat` from the latest Visual Studio install using vswhere.
string findVcvarsall()
{
    const pf86 = environment.get("ProgramFiles(x86)", environment.get("ProgramFiles", ""));
    if (pf86.length == 0)
        return null;
    const vswhere = buildPath(pf86, "Microsoft Visual Studio", "Installer", "vswhere.exe");
    if (!exists(vswhere))
        return null;
    auto r = execute([
        vswhere, "-latest", "-products", "*",
        "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "-property", "installationPath",
    ]);
    if (r.status != 0)
        return null;
    const instPath = r.output.strip;
    if (instPath.length == 0)
        return null;
    const vc = buildPath(instPath, "VC", "Auxiliary", "Build", "vcvarsall.bat");
    return exists(vc) ? vc : null;
}

/// Verifies a produced object by linking a tiny D program against it. This
/// catches objects that compiled but reference intrinsics the D toolchain cannot
/// resolve at link time (e.g. MSVC intrinsics under ImportC).
bool verifyObject(string objPath, string arch, bool isWindows)
{
    const dir = dirName(objPath);
    const testSrc = buildPath(dir, "zstd_linktest.d");
    const testExe = buildPath(dir, isWindows ? "zstd_linktest.exe" : "zstd_linktest");
    std.file.write(testSrc,
            "extern(C) uint ZSTD_versionNumber() @nogc nothrow;\n"
            ~ "void main() { assert(ZSTD_versionNumber() > 0); }\n");

    const dc = environment.get("DMD", "dmd");
    auto cmd = [dc, archModelFlag(arch), "-od=" ~ dir, "-of=" ~ testExe, testSrc, objPath];
    if (!isWindows)
        cmd ~= "-L-lpthread";
    log("verifying object via test link");
    auto r = tryRun(cmd);

    foreach (de; dirEntries(dir, "zstd_linktest*", SpanMode.shallow))
        silentRemove(de.name);

    if (!r.ran || r.status != 0)
    {
        if (r.output.length)
            log(r.output);
        return false;
    }
    return true;
}

bool buildWithPosixCC(string amalgamFile, string objPath, string arch)
{
    string cc = environment.get("CC", "");
    if (cc.length == 0)
    {
        foreach (candidate; ["cc", "gcc", "clang"])
            if (findInPath(candidate) !is null)
            {
                cc = candidate;
                break;
            }
    }
    if (cc.length == 0)
    {
        log("no C compiler (cc/gcc/clang) found in PATH.");
        return false;
    }

    silentRemove(objPath);

    auto compile = [
        cc, archModelFlag(arch), "-O2", "-fPIC", "-DZSTD_DISABLE_ASM=1",
        "-c", amalgamFile, "-o", objPath,
    ];
    log("running: ", compile.join(" "));
    auto c = tryRun(compile);
    if (!c.ran || c.status != 0)
    {
        log(c.output);
        silentRemove(objPath);
        return false;
    }
    return exists(objPath);
}

struct ProcessResult
{
    bool ran;
    int status;
    string output;
}

ProcessResult tryRun(const(string)[] cmd)
{
    try
    {
        auto r = execute(cmd);
        return ProcessResult(true, r.status, r.output);
    }
    catch (ProcessException e)
    {
        return ProcessResult(false, -1, e.msg);
    }
    catch (Exception e)
        return ProcessResult(false, -1, e.msg);
}

/// Removes a file if present, ignoring any error.
void silentRemove(string path) nothrow
{
    try
    {
        if (exists(path))
            remove(path);
    }
    catch (Exception)
    {
    }
}

/// Returns the resolved path of `exe` if found on PATH, else `null`.
string findInPath(string exe)
{
    const pathVar = environment.get("PATH", "");
    version (Windows)
        const exts = [".exe", ".cmd", ".bat", ""];
    else
        const exts = [""];
    foreach (dir; pathVar.split(pathSeparator))
    {
        if (dir.length == 0)
            continue;
        foreach (ext; exts)
        {
            const candidate = buildPath(dir, exe ~ ext);
            if (exists(candidate) && isFile(candidate))
                return candidate;
        }
    }
    return null;
}

