#!/usr/bin/env python3
"""Adapt the historical site-specific build-driver contract to the strict adapter protocol."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import controller_driver


BUILD_TIMEOUT_SECONDS = 60 * 60


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--driver", type=Path, required=True)
    parser.add_argument("--source-checkout", type=Path, required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--source-archive-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--serial", action="store_true")
    parser.add_argument("--smoke-test", action="store_true")
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_checkout(checkout: Path, source_sha: str, archive_sha256: str) -> None:
    git = shutil.which("git")
    if git is None:
        raise SystemExit("git is required by the legacy-driver compatibility adapter")
    if not checkout.is_dir():
        raise SystemExit(f"isolated legacy source checkout does not exist: {checkout}")
    head = subprocess.check_output(
        [git, "-C", str(checkout), "rev-parse", "HEAD"], text=True
    ).strip()
    if head.lower() != source_sha.lower():
        raise SystemExit(
            f"isolated legacy source checkout HEAD {head} does not match {source_sha}"
        )
    with tempfile.TemporaryDirectory(prefix="featool-mex-legacy-verify-") as temporary:
        archive = Path(temporary) / "source.tar"
        proc = subprocess.run(
            [
                git,
                "-C",
                str(checkout),
                "archive",
                "--format=tar",
                f"--output={archive}",
                source_sha,
            ],
            check=False,
        )
        if proc.returncode:
            raise SystemExit("unable to archive isolated legacy source checkout")
        checkout_digest = sha256(archive)
    if checkout_digest != archive_sha256:
        raise SystemExit(
            "isolated legacy source checkout does not match immutable source archive: "
            f"expected {archive_sha256}, got {checkout_digest}"
        )


def main() -> int:
    args = parse_args()
    if not args.serial or not args.smoke_test:
        raise SystemExit("legacy compatibility builds require --serial and --smoke-test")

    driver = args.driver.resolve()
    if not driver.is_file():
        raise SystemExit(f"legacy build driver does not exist: {driver}")

    archive = args.source_archive.resolve()
    actual_digest = sha256(archive)
    if actual_digest != args.source_archive_sha256:
        raise SystemExit(
            "source archive SHA256 mismatch: "
            f"expected {args.source_archive_sha256}, got {actual_digest}"
        )

    output = args.output.resolve()
    if not output.is_dir():
        raise SystemExit(f"legacy build output directory does not exist: {output}")

    source = args.source_checkout.resolve()
    verify_checkout(source, args.source_sha, args.source_archive_sha256)

    with tempfile.TemporaryDirectory(prefix="featool-mex-legacy-driver-") as temporary:
        temporary_root = Path(temporary)
        command = [
            str(driver),
            "--runtime",
            args.runtime,
            "--version",
            args.version,
            "--platform",
            args.platform,
            "--source",
            str(source),
            "--output",
            str(output),
            "--source-sha",
            args.source_sha,
            "--serial",
            "--smoke-test",
        ]
        try:
            returncode = controller_driver.run_process_tree(
                command,
                env=os.environ.copy(),
                cwd=temporary_root,
                timeout=BUILD_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired as exc:
            raise SystemExit(
                f"legacy build driver exceeded {BUILD_TIMEOUT_SECONDS} seconds"
            ) from exc
        if returncode:
            return returncode

    receipt = {
        "runtime": args.runtime,
        "version": args.version,
        "platform": args.platform,
        "source_sha": args.source_sha,
        "source_archive_sha256": args.source_archive_sha256,
        "build": "passed",
        "smoke_test": "passed",
    }
    args.receipt.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
