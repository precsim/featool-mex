#!/usr/bin/env python3
"""Non-build readiness check for a self-hosted MEX controller runner."""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

import controller_driver


TOOLS = {
    "linux-x86_64": ("git", "file", "readelf", "objdump", "ldd"),
    "windows-x86_64": ("git", "python", "pwsh"),
    "macos-x86_64": ("git", "bash", "file", "lipo", "otool"),
    "macos-arm64": ("git", "bash", "file", "lipo", "otool"),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=sorted(controller_driver.SUPPORTED_PLATFORMS), required=True)
    parser.add_argument(
        "--require",
        action="append",
        default=[],
        metavar="RUNTIME:VERSION",
        help="require a configured appliance; may be repeated",
    )
    parser.add_argument("--config", type=Path, default=controller_driver.default_config_path())
    parser.add_argument(
        "--probe",
        action="store_true",
        help="run each required appliance's configured non-build probe_command",
    )
    parser.add_argument(
        "--config-only",
        action="store_true",
        help="validate JSON/schema only; do not inspect host tools or adapter executables",
    )
    return parser.parse_args()


def expected_host(platform_tag: str) -> tuple[str, set[str]]:
    if platform_tag == "linux-x86_64":
        return "linux", {"x86_64", "amd64"}
    if platform_tag == "windows-x86_64":
        return "windows", {"x86_64", "amd64"}
    if platform_tag == "macos-x86_64":
        return "darwin", {"x86_64", "amd64"}
    return "darwin", {"arm64", "aarch64"}


def parse_requirement(value: str) -> tuple[str, str]:
    if ":" not in value:
        raise controller_driver.ControllerError(
            f"invalid --require {value!r}; expected RUNTIME:VERSION"
        )
    runtime, version = value.split(":", 1)
    if runtime not in controller_driver.SUPPORTED_RUNTIMES or not version:
        raise controller_driver.ControllerError(
            f"invalid --require {value!r}; runtime must be matlab or octave"
        )
    return runtime, version


def check_host(platform_tag: str) -> None:
    expected_system, expected_machines = expected_host(platform_tag)
    actual_system = platform.system().lower()
    actual_machine = platform.machine().lower()
    if actual_system != expected_system:
        raise controller_driver.ControllerError(
            f"runner OS mismatch for {platform_tag}: expected {expected_system}, got {actual_system}"
        )
    if actual_machine not in expected_machines:
        raise controller_driver.ControllerError(
            f"runner architecture mismatch for {platform_tag}: got {actual_machine}"
        )

    missing = [tool for tool in TOOLS[platform_tag] if shutil.which(tool) is None]
    if missing:
        raise controller_driver.ControllerError(
            "controller audit tools missing from PATH: " + ", ".join(missing)
        )
    if platform_tag == "windows-x86_64" and shutil.which("dumpbin") is None:
        program_files_x86 = os.environ.get("ProgramFiles(x86)")
        if not program_files_x86:
            raise controller_driver.ControllerError(
                "dumpbin is not on PATH and ProgramFiles(x86) is unavailable for vswhere discovery"
            )
        vswhere = (
            Path(program_files_x86)
            / "Microsoft Visual Studio"
            / "Installer"
            / "vswhere.exe"
        )
        if not vswhere.is_file():
            raise controller_driver.ControllerError(
                "dumpbin is not on PATH and Visual Studio vswhere.exe is unavailable"
            )
        proc = subprocess.run(
            [
                str(vswhere),
                "-latest",
                "-products",
                "*",
                "-requires",
                "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                "-property",
                "installationPath",
            ],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if proc.returncode or not proc.stdout.strip():
            raise controller_driver.ControllerError(
                "Visual Studio C++ x86/x64 tools required for dumpbin audit were not found"
            )
        installation = Path(proc.stdout.strip().splitlines()[-1])
        tools_root = installation / "VC" / "Tools" / "MSVC"
        candidates = sorted(
            tools_root.glob("*/bin/Hostx64/x64/dumpbin.exe"), reverse=True
        )
        if not candidates or not candidates[0].is_file():
            raise controller_driver.ControllerError(
                "Visual Studio C++ tools were reported by vswhere, but x64 dumpbin.exe was not found"
            )


def main() -> int:
    args = parse_args()
    try:
        index = controller_driver.load_config(args.config.resolve())
        if args.config_only:
            print(f"Controller config schema is valid: {args.config}")
            return 0

        check_host(args.platform)
        requirements = [parse_requirement(value) for value in args.require]
        if not requirements:
            raise controller_driver.ControllerError(
                "at least one --require RUNTIME:VERSION is required for host readiness checks"
            )

        for runtime, version in requirements:
            appliance = controller_driver.select_appliance(
                index, runtime, version, args.platform
            )
            controller_driver.resolve_executable(appliance["command"])
            controller_driver.controller_environment(appliance)
            if args.probe:
                rc = controller_driver.run_probe(appliance)
                if rc:
                    raise controller_driver.ControllerError(
                        f"probe failed for {runtime}:{version}:{args.platform} with exit code {rc}"
                    )

        runner_environment = os.environ.get("RUNNER_ENVIRONMENT")
        if runner_environment and runner_environment != "self-hosted":
            raise controller_driver.ControllerError(
                f"expected a self-hosted GitHub runner, got RUNNER_ENVIRONMENT={runner_environment!r}"
            )
        print(
            f"Controller readiness passed for {args.platform}; "
            f"validated {len(requirements)} appliance configuration(s)."
        )
        return 0
    except controller_driver.ControllerError as exc:
        print(f"controller readiness failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
