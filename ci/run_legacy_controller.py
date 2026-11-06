#!/usr/bin/env python3
"""Invoke the runner-local preserved-toolchain build appliance driver."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-sha", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = Path(os.path.abspath(os.path.expanduser(str(args.output))))
    bundled = Path(__file__).resolve().parent / "legacy" / "controller_driver.py"
    if not bundled.is_file():
        raise SystemExit(f"bundled legacy controller driver not found: {bundled}")
    command = [sys.executable, str(bundled)]

    driver = os.environ.get("MEX_LEGACY_BUILD_DRIVER")
    with tempfile.TemporaryDirectory(prefix="featool-mex-controller-config-") as temporary:
        if driver:
            resolved = shutil.which(driver)
            if resolved is None and Path(driver).is_file():
                resolved = str(Path(driver).resolve())
            if resolved is None:
                raise SystemExit(
                    "MEX_LEGACY_BUILD_DRIVER does not resolve to an executable file: "
                    + driver
                )
            git = shutil.which("git")
            if git is None:
                raise SystemExit("git is required for the legacy build-driver compatibility path")
            source = args.source.resolve()
            compatibility_source = Path(temporary) / "legacy-source"
            clone = subprocess.run(
                [
                    git,
                    "clone",
                    "--no-local",
                    "--no-checkout",
                    str(source),
                    str(compatibility_source),
                ],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            if clone.returncode:
                detail = clone.stderr.strip() or clone.stdout.strip()
                raise SystemExit(f"unable to create isolated legacy source checkout: {detail}")
            checkout = subprocess.run(
                [
                    git,
                    "-C",
                    str(compatibility_source),
                    "checkout",
                    "--detach",
                    args.source_sha,
                ],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            if checkout.returncode:
                detail = checkout.stderr.strip() or checkout.stdout.strip()
                raise SystemExit(f"unable to check out requested legacy source SHA: {detail}")
            subprocess.run(
                [git, "-C", str(compatibility_source), "remote", "remove", "origin"],
                check=True,
            )
            adapter = Path(__file__).resolve().parent / "legacy" / "legacy_driver_adapter.py"
            pass_env = [
                name.strip()
                for name in os.environ.get("MEX_LEGACY_BUILD_DRIVER_PASS_ENV", "").split(",")
                if name.strip()
            ]
            config = {
                "schema_version": 1,
                "appliances": [
                    {
                        "runtime": args.runtime,
                        "version": args.version,
                        "platform": args.platform,
                        "command": [
                            str(Path(sys.executable).resolve()),
                            str(adapter),
                            "--driver",
                            resolved,
                            "--source-checkout",
                            str(compatibility_source),
                        ],
                        "pass_env": pass_env,
                    }
                ],
            }
            config_path = Path(temporary) / "legacy-driver.json"
            config_path.write_text(json.dumps(config), encoding="utf-8")
            command.extend(["--config", str(config_path)])

        command.extend([
            "--runtime",
            args.runtime,
            "--version",
            args.version,
            "--platform",
            args.platform,
            "--source",
            str(args.source.resolve()),
            "--output",
            str(output),
            "--source-sha",
            args.source_sha,
            "--serial",
            "--smoke-test",
        ])
        print("Invoking preserved compatibility build appliance.")
        try:
            proc = subprocess.run(command, check=False, timeout=66 * 60)
        except subprocess.TimeoutExpired as exc:
            raise SystemExit("legacy controller exceeded 66 minutes") from exc
        if proc.returncode:
            return proc.returncode

    metadata = output / "BUILD-INFO.json"
    if not metadata.is_file():
        raise SystemExit(
            f"legacy build driver returned success but did not create {metadata}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
