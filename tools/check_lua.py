#!/usr/bin/env python3
"""Parse every tracked Lua file with Lua 5.1.

Ashoholic has no separate offline test suite. This is the syntax check the
offline-suite job runs. luac -p only parses; it does not execute addon code.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def lua51_compiler() -> str:
    for name in ("luac5.1", "luac"):
        path = shutil.which(name)
        if not path:
            continue
        result = subprocess.run([path, "-v"], capture_output=True, text=True)
        version = f"{result.stdout}{result.stderr}"
        if "5.1" in version:
            return path
    sys.exit("Lua 5.1 compiler not found (expected luac5.1).")


def tracked_lua() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--", "*.lua"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return [item for item in result.stdout.decode("utf-8").split("\0") if item]


def main() -> int:
    compiler = lua51_compiler()
    files = tracked_lua()
    if not files:
        print("no tracked Lua files", file=sys.stderr)
        return 1

    failed = 0
    for relative in files:
        result = subprocess.run(
            [compiler, "-p", str(ROOT / relative)],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            failed += 1
            message = (result.stderr or result.stdout).strip()
            print(f"{relative}: {message}", file=sys.stderr)

    if failed:
        print(f"offline-suite: {failed} of {len(files)} Lua files failed to parse", file=sys.stderr)
        return 1

    print(f"offline-suite: parsed {len(files)} Lua files with {compiler}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
