#!/usr/bin/env python3
"""Runs every tools/tests/*.test.luau under the plain `luau` CLI (must be on PATH).

Each test file names the modules it needs with header lines:  --@use <path> <LocalName>
  --@include <path>  inserts a file as-is (the Roblox mock);  --@sources  embeds every src/**/*.lua as SOURCES[path]
The runner builds one script: stubs.luau, then each module wrapped as `local Name = (function() ... end)()`,
then the test. Modules therefore must not require() other modules at load time (the pure Core modules don't).
It also checks that BeyConfig refuses to load when crate odds do not total 100%.
Exit code is non-zero if anything fails. These tests cover pure logic only, not Roblox physics or replication.
"""
import glob
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
STUBS = open(os.path.join(ROOT, "tools", "tests", "stubs.luau")).read()


def build(test_path, replace=None):
    test = open(test_path).read()
    parts = [STUBS]
    for path in re.findall(r"^--@include (\S+)\s*$", test, re.M):
        parts.append(open(os.path.join(ROOT, path)).read())
    if re.search(r"^--@sources\s*$", test, re.M):
        entries = []
        for dirpath, _, files in os.walk(os.path.join(ROOT, "src")):
            for fname in sorted(files):
                if fname.endswith(".lua"):
                    full = os.path.join(dirpath, fname)
                    rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
                    text = open(full).read()
                    assert "]======]" not in text
                    entries.append(f'["{rel}"] = [======[\n{text}]======],')
        parts.append("SOURCES = {\n" + "\n".join(entries) + "\n}\n")
    for path, name in re.findall(r"^--@use (\S+) (\w+)\s*$", test, re.M):
        src = open(os.path.join(ROOT, path)).read()
        if replace and replace[0] == path:
            src = src.replace(replace[1], replace[2])
        parts.append(f"local {name} = (function()\n{src}\nend)()\n")
    parts.append(test)
    return "\n".join(parts)


def run(script):
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as f:
        f.write(script)
        path = f.name
    try:
        out = subprocess.run(["luau", path], capture_output=True, text=True, timeout=600)
        return out.returncode, out.stdout + out.stderr
    finally:
        os.unlink(path)


def main():
    failures = []
    for test in sorted(glob.glob(os.path.join(ROOT, "tools", "tests", "*.test.luau"))):
        name = os.path.basename(test)
        code, out = run(build(test))
        ok = code == 0 and "TESTS PASSED" in out
        print(("PASS " if ok else "FAIL ") + name)
        if not ok or "-v" in sys.argv:
            print(out.rstrip())
        if not ok:
            failures.append(name)

    # Negative check: a crate whose odds total 10001 bp must refuse to load.
    code, out = run(build(os.path.join(ROOT, "tools", "tests", "config.test.luau"), ("src/shared/BeyConfig.lua", "Epic = 550", "Epic = 551")))
    ok = code != 0 and "must be 10000" in out
    print(("PASS " if ok else "FAIL ") + "bad crate odds are rejected")
    if not ok:
        failures.append("bad-odds")

    print()
    if failures:
        print("FAILED: " + ", ".join(failures))
        sys.exit(1)
    print("ALL TESTS PASSED")


if __name__ == "__main__":
    main()
