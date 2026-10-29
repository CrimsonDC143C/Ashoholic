#!/usr/bin/env python3
"""Dry-run the Ashoholic package and check addon manifest paths.

Builds the same archive as the release workflow, then deletes it unless
--zip is given. Never publishes a release.

Every file named by a tracked .toc, and every Script or Include in those
XML files, must exist in git and in the archive with the same case.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

# Source path -> path inside Ashoholic.zip. Kept aligned with the release
# archive: addon files at the repo root are packed under Ashoholic/.
EXPLICIT = {
    "Ashoholic.toc": "Ashoholic/Ashoholic.toc",
    "Ashoholic.bat": "Ashoholic/Ashoholic.bat",
    "AshoholicMerge.ps1": "Ashoholic/AshoholicMerge.ps1",
    "AshoholicSync.ps1": "Ashoholic/AshoholicSync.ps1",
    "Characters.lua": "Ashoholic/Characters.lua",
    "Core.lua": "Ashoholic/Core.lua",
    "RaidData.lua": "Ashoholic/RaidData.lua",
    "HourlyWidget.lua": "Ashoholic/HourlyWidget.lua",
    "Minimap.lua": "Ashoholic/Minimap.lua",
    "Themes.lua": "Ashoholic/Themes.lua",
    "UI.lua": "Ashoholic/UI.lua",
    "NexusDock.lua": "Ashoholic/NexusDock.lua",
    "FastSwap/FastSwap.toc": "FastSwap/FastSwap.toc",
    "FastSwap/FastSwap.lua": "FastSwap/FastSwap.lua",
    "FastSwap/FastSwap_Glue.lua": "FastSwap/FastSwap_Glue.lua",
    "FastSwap/Sync-FastSwapGlue.ps1": "FastSwap/Sync-FastSwapGlue.ps1",
}

# Entire tracked trees. The zip prefix is prepended to the source path.
PREFIXES = (
    ("Libraries/", "Ashoholic/"),
    ("SharedMedia/", ""),
)

REQUIRED_ZIP_ENTRIES = (
    "Ashoholic/Ashoholic.toc",
    "FastSwap/FastSwap.toc",
    "SharedMedia/SharedMedia.toc",
)


def git_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return [item for item in result.stdout.decode("utf-8").split("\0") if item]


def join_repo(base: str, relative: str) -> str:
    relative = relative.strip().replace("\\", "/")
    if relative.startswith("/") or (len(relative) >= 2 and relative[1] == ":"):
        raise ValueError(f"absolute path is not allowed: {relative}")
    parts = [part for part in base.split("/") if part] if base else []
    for part in relative.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                raise ValueError(f"path escapes the repository: {relative}")
            parts.pop()
            continue
        parts.append(part)
    return "/".join(parts)


def read_text(path: str) -> str:
    data = (ROOT / path).read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    return data.decode("utf-8")


def toc_entries(toc_path: str) -> list[str]:
    entries = []
    for line in read_text(toc_path).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        entries.append(line)
    return entries


def xml_entries(xml_path: str) -> list[tuple[str, str]]:
    try:
        root = ET.fromstring(read_text(xml_path))
    except ET.ParseError as exc:
        raise ValueError(f"{xml_path}: {exc}") from exc
    found = []
    for element in root.iter():
        tag = element.tag.rsplit("}", 1)[-1]
        if tag not in ("Script", "Include"):
            continue
        name = element.get("file")
        if not name or not name.strip():
            raise ValueError(f"{xml_path}: <{tag}> is missing a file attribute")
        found.append((tag, name.strip()))
    return found


def manifest_files(tracked: set[str], errors: list[str]) -> list[str]:
    """Return source paths loaded by every tracked TOC, following XML includes."""
    tocs = sorted(path for path in tracked if path.endswith(".toc"))
    if not tocs:
        errors.append("no tracked .toc files")
        return []

    loaded: list[str] = []
    seen_xml: set[str] = set()

    def visit_xml(xml_path: str) -> None:
        if xml_path in seen_xml:
            return
        seen_xml.add(xml_path)
        if xml_path not in tracked:
            return
        base = str(Path(xml_path).parent).replace("\\", "/")
        if base == ".":
            base = ""
        try:
            entries = xml_entries(xml_path)
        except ValueError as exc:
            errors.append(str(exc))
            return
        for _tag, name in entries:
            try:
                resolved = join_repo(base, name)
            except ValueError as exc:
                errors.append(f"{xml_path}: {exc}")
                continue
            require_tracked(resolved, f"{xml_path} references {name}", tracked, errors)
            loaded.append(resolved)
            if resolved.endswith(".xml"):
                visit_xml(resolved)

    for toc in tocs:
        base = str(Path(toc).parent).replace("\\", "/")
        if base == ".":
            base = ""
        try:
            entries = toc_entries(toc)
        except ValueError as exc:
            errors.append(str(exc))
            continue
        for name in entries:
            try:
                resolved = join_repo(base, name)
            except ValueError as exc:
                errors.append(f"{toc}: {exc}")
                continue
            require_tracked(resolved, f"{toc} references {name}", tracked, errors)
            loaded.append(resolved)
            if resolved.endswith(".xml"):
                visit_xml(resolved)
    return loaded


def require_tracked(path: str, origin: str, tracked: set[str], errors: list[str]) -> None:
    if path in tracked:
        return
    folded = {item.lower(): item for item in tracked}
    actual = folded.get(path.lower())
    if actual:
        errors.append(f"case mismatch: {origin} resolves to {path}, git has {actual}")
    else:
        errors.append(f"missing file: {origin} resolves to {path}")


def package_map(tracked: set[str], errors: list[str]) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for source, archive in EXPLICIT.items():
        require_tracked(source, "package list", tracked, errors)
        mapping[source] = archive
    for source_prefix, archive_prefix in PREFIXES:
        matched = [path for path in tracked if path.startswith(source_prefix)]
        if not matched:
            errors.append(f"package tree is empty: {source_prefix}")
            continue
        for source in matched:
            mapping[source] = archive_prefix + source
    return mapping


def version_of_ashoholic(errors: list[str]) -> None:
    for line in read_text("Ashoholic.toc").splitlines():
        if line.startswith("## Version:"):
            version = line.split(":", 1)[1].strip()
            if version:
                return
            break
    errors.append("Version missing from Ashoholic.toc")


def build_zip(mapping: dict[str, str], destination: Path) -> list[str]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    names = []
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for source in sorted(mapping):
            archive_name = mapping[source]
            archive.write(ROOT / source, archive_name)
            names.append(archive_name)
    return names


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--zip",
        metavar="PATH",
        help="write the archive to this path and keep it (the release workflow)",
    )
    args = parser.parse_args()

    errors: list[str] = []
    tracked = set(git_files())
    version_of_ashoholic(errors)
    loaded = manifest_files(tracked, errors)
    mapping = package_map(tracked, errors)

    missing_from_package = sorted({path for path in loaded if path not in mapping})
    for path in missing_from_package:
        errors.append(f"manifest file is not packaged: {path}")

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    if args.zip:
        destination = Path(args.zip)
        if not destination.is_absolute():
            destination = ROOT / destination
        names = build_zip(mapping, destination)
        kept = destination
    else:
        with tempfile.TemporaryDirectory(prefix="ashoholic-package-") as temporary:
            destination = Path(temporary) / "Ashoholic.zip"
            names = build_zip(mapping, destination)
            kept = None
            zip_names = set(names)
            for required in REQUIRED_ZIP_ENTRIES:
                if required not in zip_names:
                    errors.append(f"archive is missing {required}")
            packaged_sources = set(mapping)
            for path in loaded:
                archive_name = mapping[path]
                if archive_name not in zip_names:
                    errors.append(f"archive is missing {archive_name} ({path})")
            if errors:
                for error in errors:
                    print(error, file=sys.stderr)
                return 1
            print(
                f"package-content: {len(loaded)} manifest files, "
                f"{len(packaged_sources)} packaged files, dry-run archive discarded"
            )
            return 0

    zip_names = set(names)
    for required in REQUIRED_ZIP_ENTRIES:
        if required not in zip_names:
            errors.append(f"archive is missing {required}")
    for path in loaded:
        archive_name = mapping[path]
        if archive_name not in zip_names:
            errors.append(f"archive is missing {archive_name} ({path})")
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(
        f"package-content: {len(loaded)} manifest files, "
        f"{len(mapping)} packaged files, wrote {kept}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
