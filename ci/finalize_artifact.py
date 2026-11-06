#!/usr/bin/env python3
"""Verify a MEX artifact directory and add checksums/compatibility metadata."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TARGET_RE = re.compile(r"make_target\('([^']+)'\s*,")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--extension", required=True)
    parser.add_argument("--runtime", choices=("matlab", "octave"), required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--audit-file", type=Path)
    parser.add_argument("--compatibility", default="build-runtime smoke test passed")
    parser.add_argument("--source-sha")
    parser.add_argument("--built-with")
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    args = parse_args()
    directory = args.directory.resolve()
    if not directory.is_dir():
        raise SystemExit(f"artifact directory does not exist: {directory}")

    manifest_text = (ROOT / "build_manifest.m").read_text(encoding="utf-8")
    target_names = TARGET_RE.findall(manifest_text)
    if not target_names:
        raise SystemExit("could not read target names from build_manifest.m")

    extension = args.extension.lstrip(".")
    missing = [
        name for name in target_names if not (directory / f"{name}.{extension}").is_file()
    ]
    if missing:
        raise SystemExit(f"missing expected MEX targets: {', '.join(missing)}")

    wrapper = directory / "iluk.m"
    if not wrapper.is_file():
        raise SystemExit(f"missing required wrapper: {wrapper}")

    metadata_path = directory / "BUILD-INFO.json"
    if not metadata_path.is_file():
        raise SystemExit(f"missing build metadata: {metadata_path}")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata.get("runtime") != args.runtime:
        raise SystemExit(
            f"BUILD-INFO runtime={metadata.get('runtime')!r}, expected {args.runtime!r}"
        )
    if metadata.get("arch") != args.platform:
        raise SystemExit(
            f"BUILD-INFO arch={metadata.get('arch')!r}, expected {args.platform!r}"
        )
    if metadata.get("openmp") is not False:
        raise SystemExit("baseline artifact must have openmp=false")
    if metadata.get("mex_extension") != extension:
        raise SystemExit(
            f"BUILD-INFO mex_extension={metadata.get('mex_extension')!r}, "
            f"expected {extension!r}"
        )
    if args.built_with and metadata.get("built_with") != args.built_with:
        raise SystemExit(
            f"BUILD-INFO built_with={metadata.get('built_with')!r}, "
            f"expected {args.built_with!r}"
        )
    if sorted(metadata.get("targets", [])) != sorted(target_names):
        raise SystemExit(
            "BUILD-INFO target list does not match build_manifest.m"
        )
    expected_sha = args.source_sha or os.environ.get("GITHUB_SHA")
    if expected_sha:
        if metadata.get("source_sha") != expected_sha:
            raise SystemExit(
                f"BUILD-INFO source_sha={metadata.get('source_sha')!r}, "
                f"expected {expected_sha!r}"
            )
    elif metadata.get("source_sha") in (None, "", "unknown"):
        raise SystemExit(
            "BUILD-INFO source_sha is unknown and no expected source SHA was supplied"
        )

    metadata["compatibility_statement"] = args.compatibility
    if args.audit_file:
        audit = args.audit_file.resolve()
        if not audit.is_file():
            raise SystemExit(f"audit file does not exist: {audit}")
        if audit.suffix.lower() == ".json":
            metadata["binary_audit"] = json.loads(audit.read_text(encoding="utf-8"))
        else:
            metadata["binary_audit_report"] = audit.name

    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    compatibility_path = directory / "COMPATIBILITY.txt"
    compatibility_path.write_text(
        f"Runtime: {args.runtime}\n"
        f"Platform: {args.platform}\n"
        f"Status: {args.compatibility}\n"
        "OpenMP: disabled\n",
        encoding="utf-8",
    )

    checksum_path = directory / "SHA256SUMS"
    files = sorted(
        path
        for path in directory.iterdir()
        if path.is_file() and path.name != checksum_path.name
    )
    checksum_path.write_text(
        "".join(f"{sha256(path)}  {path.name}\n" for path in files),
        encoding="utf-8",
    )

    print(
        f"artifact finalized: {len(target_names)} MEX targets, "
        f"{len(files)} checksummed files"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
