#!/usr/bin/env python3
"""Invoke the runner-local preserved-toolchain build appliance driver."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    driver = os.environ.get("MEX_LEGACY_BUILD_DRIVER", "mex-legacy-build")
    resolved = shutil.which(driver)
    if resolved is None and Path(driver).is_file():
        resolved = str(Path(driver).resolve())
    if resolved is None:
        raise SystemExit(
            "legacy build controller driver not found. Install 'mex-legacy-build' "
            "on the controller runner or set MEX_LEGACY_BUILD_DRIVER."
        )

    args.output.mkdir(parents=True, exist_ok=True)
    command = [
        resolved,
        "--runtime",
        args.runtime,
        "--version",
        args.version,
        "--platform",
        args.platform,
        "--source",
        str(args.source.resolve()),
        "--output",
        str(args.output.resolve()),
        "--serial",
        "--smoke-test",
    ]
    print("Invoking preserved compatibility build appliance.")
    proc = subprocess.run(command, check=False)
    if proc.returncode:
        return proc.returncode

    metadata = args.output / "BUILD-INFO.json"
    if not metadata.is_file():
        raise SystemExit(
            f"legacy build driver returned success but did not create {metadata}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
