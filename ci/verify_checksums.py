#!/usr/bin/env python3
"""Verify SHA256SUMS inside a downloaded artifact directory."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_checksums.py <artifact-directory>")
    directory = Path(sys.argv[1])
    sums = directory / "SHA256SUMS"
    if not sums.is_file():
        raise SystemExit(f"missing checksum file: {sums}")

    checked = 0
    listed: set[str] = set()
    for raw_line in sums.read_text(encoding="utf-8").splitlines():
        if not raw_line.strip():
            continue
        expected, separator, name = raw_line.partition("  ")
        if not separator or not expected or not name:
            raise SystemExit(f"invalid SHA256SUMS line: {raw_line!r}")
        if "/" in name or "\\" in name or Path(name).name != name or name in (".", ".."):
            raise SystemExit(f"invalid checksum path: {name!r}")
        if name in listed:
            raise SystemExit(f"duplicate checksum entry: {name}")
        listed.add(name)
        path = directory / name
        if not path.is_file():
            raise SystemExit(f"checksummed file is missing: {name}")
        actual = sha256(path)
        if actual.lower() != expected.lower():
            raise SystemExit(
                f"checksum mismatch for {name}: expected {expected}, got {actual}"
            )
        checked += 1

    if checked == 0:
        raise SystemExit("SHA256SUMS contains no files")

    nested_entries = sorted(
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*")
        if path.parent != directory or path.is_dir()
    )
    if nested_entries:
        raise SystemExit(
            "artifact directory must be flat; unexpected nested entries: "
            + ", ".join(nested_entries)
        )

    actual_files = {
        path.name
        for path in directory.iterdir()
        if path.is_file() and path.name != sums.name
    }
    if listed != actual_files:
        missing = sorted(actual_files - listed)
        extra = sorted(listed - actual_files)
        details = []
        if missing:
            details.append("unlisted files: " + ", ".join(missing))
        if extra:
            details.append("listed but absent files: " + ", ".join(extra))
        raise SystemExit("checksum manifest does not match artifact: " + "; ".join(details))

    print(f"verified {checked} artifact checksums")
    return 0


if __name__ == "__main__":
    sys.exit(main())
