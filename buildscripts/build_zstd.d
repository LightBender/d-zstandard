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
 *   $(LI Build a static library, preferring the D compiler's ImportC, and
 *        falling back to the native C toolchain when ImportC cannot compile it.)
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

    // 2. Try the primary path: the D compiler's ImportC. DMD's `-c` can succeed
    //    while leaving unresolved intrinsics, so the object is verified by a test
    //    link before we accept it.
    if (buildWithImportC(amalgamFile, objPath, arch, isWindows) && verifyObject(objPath, arch, isWindows))
    {
        std.file.write(stampPath, stamp);
        log("built via ImportC: ", objPath.relativePath(root));
        return 0;
    }
    log("ImportC path unavailable/failed; trying the native C toolchain...");

    // 3. Fall back to the native C toolchain, also verified.
    if (buildWithNativeCC(amalgamFile, objPath, arch, isWindows) && verifyObject(objPath, arch, isWindows))
    {
        std.file.write(stampPath, stamp);
        log("built via native C toolchain: ", objPath.relativePath(root));
        return 0;
    }

    log("error: failed to build the zstd object for ", osArch, ".");
    if (isWindows)
        log("       ensure a D compiler with ImportC support, or the MSVC 'cl' compiler, is available.");
    else
        log("       ensure a D compiler with ImportC support, or a C compiler (cc/gcc/clang), is available.");
    return 1;
}

/// Ensures the vendored `zstd` git submodule is present and usable.
///
/// If `zstd/lib/zstd.h` is missing, runs `git submodule update --init zstd`
/// from the package root. Returns `true` when the submodule is ready.
bool ensureZstdSubmodule(string root, string zstdDir)
{
    const header = buildPath(zstdDir, "lib", "zstd.h");
    if (exists(header))
        return true;

    log("zstd submodule not initialized; running git submodule update --init zstd");

    if (!exists(buildPath(root, ".gitmodules")))
    {
        log("error: .gitmodules not found; cannot initialize the zstd submodule.");
        return false;
    }

    auto r = tryRun(["git", "-C", root, "submodule", "update", "--init", "zstd"]);
    if (!r.ran)
    {
        log("error: failed to run git. Ensure git is installed and on PATH.");
        log("       then run: git submodule update --init zstd");
        return false;
    }
    if (r.status != 0)
    {
        if (r.output.length)
            log(r.output);
        log("error: git submodule update --init zstd failed (exit ", r.status, ").");
        log("       run manually: git submodule update --init zstd");
        return false;
    }

    if (!exists(header))
    {
        log("error: zstd submodule still missing after init (expected ", header, ").");
        log("       run manually: git submodule update --init zstd");
        return false;
    }

    log("zstd submodule initialized.");
    return true;
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
/// does not implement every MSVC/GCC compiler intrinsic. We therefore compile a
/// tiny shim translation unit that neutralises the intrinsics zstd relies on and
/// then includes the amalgamation.
bool buildWithImportC(string amalgamFile, string objPath, string arch, bool isWindows)
{
    const dc = environment.get("DMD", "dmd");
    const shimFile = buildPath(dirName(amalgamFile), "zstd_importc.c");
    std.file.write(shimFile, importCShimPrefix() ~ cast(string) read(amalgamFile));

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
        return false;
    }
    return exists(objPath);
}

/// Preprocessor prefix prepended to the amalgamation for the ImportC build:
/// neutralise intrinsics and inline hints DMD's ImportC does not implement, so
/// every helper is emitted as a real function.
string importCShimPrefix()
{
    return `/* Auto-generated by build_zstd.d. Neutralises compiler intrinsics and
 * inline hints that DMD's ImportC does not fully implement. */
#define __assume(x) ((void)0)
#define __inline
#define __forceinline
`;
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

    // Run vcvarsall (to populate INCLUDE/LIB/PATH) and cl in one cmd session.
    const batPath = buildPath(dirName(objPath), "zstd_cl_build.bat");
    std.file.write(batPath,
            "@echo off\r\n"
            ~ `call "` ~ vcvars ~ `" ` ~ vcArch ~ "\r\n"
            ~ `cl /nologo /c /O2 /Fo"` ~ objPath ~ `" "` ~ amalgamFile ~ `"` ~ "\r\n"
            ~ "exit /b %ERRORLEVEL%\r\n");
    scope (exit)
        silentRemove(batPath);

    log("running MSVC build via ", vcvars, " (", vcArch, ")");
    auto r = tryRun(["cmd", "/c", batPath]);
    if (!r.ran || r.status != 0)
    {
        log(r.output);
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

    auto compile = [
        cc, archModelFlag(arch), "-O2", "-fPIC", "-DZSTD_DISABLE_ASM=1",
        "-c", amalgamFile, "-o", objPath,
    ];
    log("running: ", compile.join(" "));
    auto c = tryRun(compile);
    if (!c.ran || c.status != 0)
    {
        log(c.output);
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
