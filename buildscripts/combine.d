/**
 * A D port of zstd's `build/single_file_libs/combine.py`.
 *
 * Bundles multiple C/C++ source files into one, inlining quoted `#include`
 * directives. This removes any Python dependency from the package's build step:
 * it is imported and driven by `build_zstd.d`.
 *
 * Behaviour mirrors the original tool:
 * $(UL
 *   $(LI `roots` are the include search paths (like `-I`).)
 *   $(LI `excludes` (`-x`) files are replaced with an `#error` directive.)
 *   $(LI `keeps` (`-k`) files keep their `#include` directive on first sight.)
 *   $(LI `#pragma once` directives are stripped unless `keepPragma` is set.)
 * )
 *
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module buildscripts.combine;

import std.file : exists, isFile, read;
import std.path : absolutePath, baseName, buildNormalizedPath, buildPath, dirName;
import std.regex : ctRegex, matchFirst;
import std.stdio : File, stderr;
import std.string : lineSplitter;

/// Options controlling an amalgamation run.
struct CombineOptions
{
    /// Include search roots (equivalent to `-I` paths).
    string[] roots;
    /// Files to exclude and replace with an `#error` directive (`-x`).
    string[] excludes;
    /// Files to keep as `#include` directives rather than inline (`-k`).
    string[] keeps;
    /// Keep `#pragma once` directives instead of stripping them (`-p`).
    bool keepPragma;
    /// The root input file to process.
    string input;
    /// The destination file to write.
    string output;
}

private enum includeRe = ctRegex!(`^\s*#\s*include\s*"(.+?)"`);
private enum pragmaRe = ctRegex!(`^\s*#\s*pragma\s*once\s*`);

private string canon(string p)
{
    return buildNormalizedPath(absolutePath(p));
}

/// Resolves an include `file` against the search `roots`, then the including
/// file's `parentDir`, then the working directory. Returns the canonical path,
/// or `null` if not found.
private string resolveInclude(string file, string parentDir, const string[] roots)
{
    foreach (root; roots)
    {
        auto cand = canon(buildPath(root, file));
        if (exists(cand) && isFile(cand))
            return cand;
    }
    if (parentDir.length)
    {
        auto cand = canon(buildPath(parentDir, file));
        if (exists(cand) && isFile(cand))
            return cand;
    }
    if (exists(file) && isFile(file))
        return canon(file);
    return null;
}

/// Runs an amalgamation described by `opt`, writing the combined source to
/// `opt.output`.
void amalgamate(CombineOptions opt)
{
    bool[string] found;
    bool[string] excludeSet;
    bool[string] keepSet;

    foreach (x; opt.excludes)
    {
        auto r = resolveInclude(x, null, opt.roots);
        if (r !is null)
            excludeSet[r] = true;
        else
            stderr.writeln("Warning: excluded file not found: ", x);
    }
    foreach (k; opt.keeps)
    {
        auto r = resolveInclude(k, null, opt.roots);
        if (r !is null)
            keepSet[r] = true;
        else
            stderr.writeln("Warning: kept file not found: ", k);
    }

    auto outFile = File(opt.output, "w");
    scope (exit)
        outFile.close();

    const inputCanon = canon(opt.input);
    found[inputCanon] = true;
    addFile(inputCanon, baseName(opt.input), outFile, opt, found, excludeSet, keepSet);
}

private void addFile(string path, string displayName, ref File outFile, ref CombineOptions opt,
        ref bool[string] found, ref bool[string] excludeSet, ref bool[string] keepSet)
{
    stderr.writeln("Processing: ", displayName);
    const content = cast(string) read(path);
    const parentDir = dirName(path);

    foreach (line; content.lineSplitter)
    {
        auto m = matchFirst(line, includeRe);
        if (!m.empty)
        {
            const incName = m[1];
            auto resolved = resolveInclude(incName, parentDir, opt.roots);
            if (resolved is null)
            {
                outFile.writeln("#error Unable to find: ", incName);
                stderr.writeln("Error: Unable to find: ", incName);
                continue;
            }
            if (resolved in excludeSet)
            {
                outFile.writeln("#error Using excluded file: ", incName,
                        " (re-amalgamate source to fix)");
                continue;
            }
            if (resolved in found)
            {
                outFile.writeln("/**** skipping file: ", incName, " ****/");
                continue;
            }
            found[resolved] = true;
            if (resolved in keepSet)
            {
                outFile.writeln("/**** *NOT* inlining ", incName, " ****/");
                outFile.writeln(line);
                continue;
            }
            outFile.writeln("/**** start inlining ", incName, " ****/");
            addFile(resolved, incName, outFile, opt, found, excludeSet, keepSet);
            outFile.writeln("/**** ended inlining ", incName, " ****/");
        }
        else if (opt.keepPragma || matchFirst(line, pragmaRe).empty)
        {
            outFile.writeln(line);
        }
    }
}
