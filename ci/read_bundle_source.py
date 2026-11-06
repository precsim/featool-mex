#!/usr/bin/env python3
"""Resolve and validate the source commit recorded in a release bundle."""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: read_bundle_source.py <bundle-directory>")

    directory = Path(sys.argv[1])
    build_info = directory / "BUILD-INFO.json"
    if not build_info.is_file():
        raise SystemExit(f"missing build metadata: {build_info}")

    data = json.loads(build_info.read_text(encoding="utf-8"))
    source_sha = data.get("source_sha")
    if not isinstance(source_sha, str) or not SHA_RE.fullmatch(source_sha):
        raise SystemExit(f"invalid source_sha in {build_info}: {source_sha!r}")
    source_sha = source_sha.lower()

    expected = os.environ.get("EXPECTED_SOURCE_SHA", "").strip().lower()
    if expected:
        if not SHA_RE.fullmatch(expected):
            raise SystemExit(f"invalid expected source SHA: {expected!r}")
        if source_sha != expected:
            raise SystemExit(
                "published bundle source SHA does not match release workflow: "
                f"bundle={source_sha}, workflow={expected}"
            )

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with Path(github_output).open("a", encoding="utf-8") as handle:
            handle.write(f"source_sha={source_sha}\n")

    print(f"published bundle source SHA: {source_sha}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
