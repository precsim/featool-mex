#!/usr/bin/env python3
"""Verify one downloaded GitHub Release asset against release SHA256SUMS."""

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
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: verify_release_asset.py <download-directory> <asset-name>"
        )

    directory = Path(sys.argv[1])
    asset_name = sys.argv[2]
    if Path(asset_name).name != asset_name or asset_name in (".", ".."):
        raise SystemExit(f"invalid asset name: {asset_name!r}")

    asset = directory / asset_name
    sums = directory / "SHA256SUMS"
    if not asset.is_file():
        raise SystemExit(f"missing release asset: {asset}")
    if not sums.is_file():
        raise SystemExit(f"missing release checksum file: {sums}")

    entries: dict[str, str] = {}
    for raw_line in sums.read_text(encoding="utf-8").splitlines():
        if not raw_line.strip():
            continue
        expected, separator, name = raw_line.partition("  ")
        if not separator or not expected or not name:
            raise SystemExit(f"invalid SHA256SUMS line: {raw_line!r}")
        if "/" in name or "\\" in name or Path(name).name != name:
            raise SystemExit(f"invalid checksum path: {name!r}")
        if name in entries:
            raise SystemExit(f"duplicate checksum entry: {name}")
        entries[name] = expected

    expected = entries.get(asset_name)
    if expected is None:
        raise SystemExit(f"release checksum does not list asset: {asset_name}")

    actual = sha256(asset)
    if actual.lower() != expected.lower():
        raise SystemExit(
            f"checksum mismatch for {asset_name}: expected {expected}, got {actual}"
        )

    print(f"verified published release checksum for {asset_name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
