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
    for raw_line in sums.read_text(encoding="utf-8").splitlines():
        if not raw_line.strip():
            continue
        expected, separator, name = raw_line.partition("  ")
        if not separator or not expected or not name:
            raise SystemExit(f"invalid SHA256SUMS line: {raw_line!r}")
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
    print(f"verified {checked} artifact checksums")
    return 0


if __name__ == "__main__":
    sys.exit(main())
