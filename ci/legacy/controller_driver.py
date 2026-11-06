#!/usr/bin/env python3
"""Controller-side dispatcher for preserved MATLAB/Octave build appliances.

This script runs on the modern self-hosted GitHub Actions controller.  It never
builds a MEX file itself.  Instead it selects one configured appliance adapter
and forwards the repository's strict legacy-build contract to that adapter.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


CONFIG_ENV = "MEX_LEGACY_APPLIANCES_CONFIG"
SCHEMA_VERSION = 1
BUILD_TIMEOUT_SECONDS = 65 * 60
PROBE_TIMEOUT_SECONDS = 5 * 60
SUPPORTED_RUNTIMES = {"matlab", "octave"}
SUPPORTED_PLATFORMS = {
    "linux-x86_64",
    "windows-x86_64",
    "macos-x86_64",
    "macos-arm64",
}
SHA_RE = re.compile(r"^[0-9a-fA-F]{40,64}$")
ENV_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
BASE_ENV_NAMES = {
    "COMSPEC",
    "HOME",
    "LANG",
    "LC_ALL",
    "PATH",
    "PATHEXT",
    "SystemRoot",
    "TEMP",
    "TMP",
    "TMPDIR",
    "USER",
    "USERPROFILE",
    "WINDIR",
}
ROOT_FIELDS = {"schema_version", "appliances"}
APPLIANCE_FIELDS = {
    "runtime",
    "version",
    "platform",
    "command",
    "probe_command",
    "pass_env",
}


class ControllerError(RuntimeError):
    """Configuration or controller-contract failure."""


def default_config_path() -> Path:
    override = os.environ.get(CONFIG_ENV)
    if override:
        return Path(override).expanduser()
    if os.name == "nt":
        root = Path(os.environ.get("PROGRAMDATA", r"C:\ProgramData"))
        return root / "featool-mex" / "legacy-appliances.json"
    return Path("/etc/featool-mex/legacy-appliances.json")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Dispatch a compatibility build to one preserved appliance"
    )
    parser.add_argument("--runtime", choices=sorted(SUPPORTED_RUNTIMES), required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--platform", choices=sorted(SUPPORTED_PLATFORMS), required=True)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--source-sha")
    parser.add_argument("--serial", action="store_true")
    parser.add_argument("--smoke-test", action="store_true")
    parser.add_argument("--config", type=Path, default=default_config_path())
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate configuration and adapter availability without building",
    )
    parser.add_argument(
        "--probe",
        action="store_true",
        help="with --check, also run the configured non-build probe command",
    )
    return parser.parse_args()


def _nonempty_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ControllerError(f"{field} must be a non-empty string")
    return value


def _command(value: Any, field: str) -> list[str]:
    if not isinstance(value, list) or not value:
        raise ControllerError(f"{field} must be a non-empty JSON array")
    result: list[str] = []
    for item in value:
        result.append(_nonempty_string(item, field))
    return result


def load_config(path: Path) -> dict[tuple[str, str, str], dict[str, Any]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError as exc:
        raise ControllerError(
            f"controller appliance config not found: {path}. Set {CONFIG_ENV} or "
            "install the controller config at the default path."
        ) from exc
    except json.JSONDecodeError as exc:
        raise ControllerError(f"invalid JSON in controller config {path}: {exc}") from exc

    if not isinstance(data, dict):
        raise ControllerError("controller config root must be a JSON object")
    unknown_root = sorted(set(data) - ROOT_FIELDS)
    if unknown_root:
        raise ControllerError(
            "unknown controller config field(s): " + ", ".join(unknown_root)
        )
    if data.get("schema_version") != SCHEMA_VERSION:
        raise ControllerError(
            f"controller config schema_version must be {SCHEMA_VERSION}"
        )
    appliances = data.get("appliances")
    if not isinstance(appliances, list) or not appliances:
        raise ControllerError("controller config appliances must be a non-empty array")

    index: dict[tuple[str, str, str], dict[str, Any]] = {}
    for position, raw in enumerate(appliances, start=1):
        if not isinstance(raw, dict):
            raise ControllerError(f"appliances[{position}] must be a JSON object")
        unknown = sorted(set(raw) - APPLIANCE_FIELDS)
        if unknown:
            raise ControllerError(
                f"appliances[{position}] has unknown field(s): " + ", ".join(unknown)
            )
        runtime = _nonempty_string(raw.get("runtime"), f"appliances[{position}].runtime")
        version = _nonempty_string(raw.get("version"), f"appliances[{position}].version")
        platform = _nonempty_string(raw.get("platform"), f"appliances[{position}].platform")
        if runtime not in SUPPORTED_RUNTIMES:
            raise ControllerError(
                f"appliances[{position}].runtime must be one of {sorted(SUPPORTED_RUNTIMES)}"
            )
        if platform not in SUPPORTED_PLATFORMS:
            raise ControllerError(
                f"appliances[{position}].platform must be one of {sorted(SUPPORTED_PLATFORMS)}"
            )
        command = _command(raw.get("command"), f"appliances[{position}].command")
        probe_raw = raw.get("probe_command")
        probe_command = None if probe_raw is None else _command(
            probe_raw, f"appliances[{position}].probe_command"
        )
        pass_env_raw = raw.get("pass_env", [])
        if not isinstance(pass_env_raw, list):
            raise ControllerError(f"appliances[{position}].pass_env must be a JSON array")
        pass_env: list[str] = []
        seen_env: set[str] = set()
        for item in pass_env_raw:
            name = _nonempty_string(item, f"appliances[{position}].pass_env")
            if not ENV_NAME_RE.match(name):
                raise ControllerError(
                    f"appliances[{position}].pass_env contains invalid environment name {name!r}"
                )
            upper_name = name.upper()
            if upper_name.startswith("GITHUB_") or upper_name.startswith("ACTIONS_"):
                raise ControllerError(
                    f"appliances[{position}].pass_env may not forward GitHub runner internals: {name}"
                )
            folded = name.casefold()
            if folded not in seen_env:
                pass_env.append(name)
                seen_env.add(folded)
        key = (runtime, version, platform)
        if key in index:
            raise ControllerError(
                "duplicate appliance entry for " + ":".join(key)
            )
        index[key] = {
            "runtime": runtime,
            "version": version,
            "platform": platform,
            "command": command,
            "probe_command": probe_command,
            "pass_env": pass_env,
        }
    return index


def resolve_executable(command: list[str], field: str = "command") -> list[str]:
    executable = command[0]
    candidate = Path(executable).expanduser()
    if not candidate.is_absolute():
        raise ControllerError(
            f"{field} executable must use an absolute path to avoid PATH-dependent dispatch: {executable}"
        )
    if not candidate.is_file():
        raise ControllerError(f"{field} executable does not exist: {candidate}")
    if os.name != "nt" and not os.access(candidate, os.X_OK):
        raise ControllerError(f"{field} executable is not executable: {candidate}")
    resolved = str(candidate)
    return [resolved, *command[1:]]


def select_appliance(
    index: dict[tuple[str, str, str], dict[str, Any]],
    runtime: str,
    version: str,
    platform: str,
) -> dict[str, Any]:
    key = (runtime, version, platform)
    try:
        return index[key]
    except KeyError as exc:
        available = ", ".join(": ".join(item) for item in sorted(index))
        raise ControllerError(
            f"no preserved appliance is configured for {runtime}:{version}:{platform}. "
            f"Configured entries: {available or 'none'}"
        ) from exc


def controller_environment(appliance: dict[str, Any]) -> dict[str, str]:
    env: dict[str, str] = {}
    for name in BASE_ENV_NAMES:
        value = os.environ.get(name)
        if value is not None:
            env[name] = value
    for name in appliance.get("pass_env", []):
        value = os.environ.get(name)
        if value is None:
            raise ControllerError(
                f"configured adapter environment variable is not set: {name}"
            )
        env[name] = value
    runtime = appliance["runtime"]
    version = appliance["version"]
    platform = appliance["platform"]
    env["MEX_LEGACY_RUNTIME"] = runtime
    env["MEX_LEGACY_VERSION"] = version
    env["MEX_LEGACY_PLATFORM"] = platform
    env["MEX_OPENMP"] = "0"
    env["MEX_SMOKE_TEST"] = "1"
    return env


def _terminate_process_tree(proc: subprocess.Popen[Any]) -> None:
    if os.name == "nt":
        system_root = Path(os.environ.get("SystemRoot", r"C:\Windows"))
        taskkill = system_root / "System32" / "taskkill.exe"
        if taskkill.is_file():
            subprocess.run(
                [str(taskkill), "/PID", str(proc.pid), "/T", "/F"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        if proc.poll() is None:
            proc.kill()
    else:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if proc.poll() is None:
            proc.kill()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        pass


def _create_windows_kill_on_close_job(proc: subprocess.Popen[Any]) -> Any:
    import ctypes
    from ctypes import wintypes

    class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
        _fields_ = [
            ("PerProcessUserTimeLimit", ctypes.c_int64),
            ("PerJobUserTimeLimit", ctypes.c_int64),
            ("LimitFlags", wintypes.DWORD),
            ("MinimumWorkingSetSize", ctypes.c_size_t),
            ("MaximumWorkingSetSize", ctypes.c_size_t),
            ("ActiveProcessLimit", wintypes.DWORD),
            ("Affinity", ctypes.c_size_t),
            ("PriorityClass", wintypes.DWORD),
            ("SchedulingClass", wintypes.DWORD),
        ]

    class IO_COUNTERS(ctypes.Structure):
        _fields_ = [
            ("ReadOperationCount", ctypes.c_uint64),
            ("WriteOperationCount", ctypes.c_uint64),
            ("OtherOperationCount", ctypes.c_uint64),
            ("ReadTransferCount", ctypes.c_uint64),
            ("WriteTransferCount", ctypes.c_uint64),
            ("OtherTransferCount", ctypes.c_uint64),
        ]

    class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
        _fields_ = [
            ("BasicLimitInformation", JOBOBJECT_BASIC_LIMIT_INFORMATION),
            ("IoInfo", IO_COUNTERS),
            ("ProcessMemoryLimit", ctypes.c_size_t),
            ("JobMemoryLimit", ctypes.c_size_t),
            ("PeakProcessMemoryUsed", ctypes.c_size_t),
            ("PeakJobMemoryUsed", ctypes.c_size_t),
        ]

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
    kernel32.CreateJobObjectW.restype = wintypes.HANDLE
    kernel32.SetInformationJobObject.argtypes = [
        wintypes.HANDLE,
        ctypes.c_int,
        ctypes.c_void_p,
        wintypes.DWORD,
    ]
    kernel32.SetInformationJobObject.restype = wintypes.BOOL
    kernel32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
    kernel32.AssignProcessToJobObject.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL

    job = kernel32.CreateJobObjectW(None, None)
    if not job:
        raise ControllerError(f"unable to create Windows process job: {ctypes.WinError(ctypes.get_last_error())}")
    info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
    info.BasicLimitInformation.LimitFlags = 0x00002000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    if not kernel32.SetInformationJobObject(
        job, 9, ctypes.byref(info), ctypes.sizeof(info)
    ):
        error = ctypes.WinError(ctypes.get_last_error())
        kernel32.CloseHandle(job)
        raise ControllerError(f"unable to configure Windows process job: {error}")
    process_handle = wintypes.HANDLE(int(proc._handle))
    if not kernel32.AssignProcessToJobObject(job, process_handle):
        error = ctypes.WinError(ctypes.get_last_error())
        kernel32.CloseHandle(job)
        raise ControllerError(f"unable to assign process to Windows job: {error}")
    return job


def _close_windows_job(job: Any) -> None:
    import ctypes
    from ctypes import wintypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL
    kernel32.CloseHandle(job)


def run_process_tree(
    command: list[str],
    *,
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
    timeout: int,
) -> int:
    kwargs: dict[str, Any] = {}
    if os.name == "nt":
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True
    proc = subprocess.Popen(
        command,
        env=env,
        cwd=None if cwd is None else str(cwd),
        **kwargs,
    )
    job = None
    if os.name == "nt":
        try:
            job = _create_windows_kill_on_close_job(proc)
        except ControllerError:
            _terminate_process_tree(proc)
            raise
    try:
        returncode = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        if job is not None:
            _close_windows_job(job)
            job = None
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
        else:
            _terminate_process_tree(proc)
        raise
    else:
        if job is not None:
            _close_windows_job(job)
            job = None
        else:
            _terminate_process_tree(proc)
        return returncode
    finally:
        if job is not None:
            _close_windows_job(job)


def _run_checked(command: list[str], failure: str) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode:
        detail = proc.stderr.strip() or proc.stdout.strip()
        if detail:
            failure = f"{failure}: {detail}"
        raise ControllerError(failure)
    return proc


def create_source_archive(source: Path, source_sha: str, root: Path) -> tuple[Path, str]:
    git = shutil.which("git")
    if git is None:
        raise ControllerError("git is required on the controller host")

    head = _run_checked(
        [git, "-C", str(source), "rev-parse", "HEAD"],
        f"unable to read Git HEAD from {source}",
    ).stdout.strip()
    if head.lower() != source_sha.lower():
        raise ControllerError(
            f"checked-out HEAD {head} does not match requested source SHA {source_sha}"
        )
    _run_checked(
        [git, "-C", str(source), "diff", "--quiet", "--ignore-submodules", "HEAD", "--"],
        "tracked source worktree differs from the requested commit",
    )
    _run_checked(
        [
            git,
            "-C",
            str(source),
            "diff",
            "--cached",
            "--quiet",
            "--ignore-submodules",
            "HEAD",
            "--",
        ],
        "Git index differs from the requested commit",
    )

    archive = root / "source.tar"
    _run_checked(
        [
            git,
            "-C",
            str(source),
            "archive",
            "--format=tar",
            f"--output={archive}",
            source_sha,
        ],
        f"unable to archive source commit {source_sha}",
    )
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    return archive, digest


def run_probe(appliance: dict[str, Any]) -> int:
    probe = appliance.get("probe_command")
    if probe is None:
        raise ControllerError(
            "--probe requested but this appliance has no probe_command configured"
        )
    command = resolve_executable(probe, "probe_command")
    env = controller_environment(appliance)
    print(
        "Running non-build appliance probe for "
        f"{appliance['runtime']}:{appliance['version']}:{appliance['platform']}"
    )
    with tempfile.TemporaryDirectory(prefix="featool-mex-probe-") as temporary:
        try:
            return run_process_tree(
                command,
                env=env,
                cwd=Path(temporary),
                timeout=PROBE_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired as exc:
            raise ControllerError(
                f"probe exceeded {PROBE_TIMEOUT_SECONDS} seconds"
            ) from exc


def _require_build_args(args: argparse.Namespace) -> None:
    missing: list[str] = []
    if args.source is None:
        missing.append("--source")
    if args.output is None:
        missing.append("--output")
    if not args.source_sha:
        missing.append("--source-sha")
    if missing:
        raise ControllerError("build mode requires " + ", ".join(missing))
    if not args.serial:
        raise ControllerError("legacy compatibility builds must include --serial")
    if not args.smoke_test:
        raise ControllerError("legacy compatibility builds must include --smoke-test")
    if not SHA_RE.match(args.source_sha):
        raise ControllerError("--source-sha must be a full hexadecimal Git object ID")


def _verify_metadata(
    output: Path, runtime: str, version: str, platform: str, source_sha: str
) -> None:
    metadata_path = output / "BUILD-INFO.json"
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ControllerError(
            f"appliance adapter returned success but did not create {metadata_path}"
        ) from exc
    except json.JSONDecodeError as exc:
        raise ControllerError(f"invalid BUILD-INFO.json: {exc}") from exc

    expected = {
        "runtime": runtime,
        "built_with": version,
        "arch": platform,
        "source_sha": source_sha,
    }
    for key, expected_value in expected.items():
        actual = metadata.get(key)
        if actual != expected_value:
            raise ControllerError(
                f"BUILD-INFO.json {key} mismatch: expected {expected_value!r}, got {actual!r}"
            )
    if metadata.get("openmp") is not False:
        raise ControllerError("BUILD-INFO.json must record openmp=false")


def _verify_receipt(
    receipt_path: Path,
    runtime: str,
    version: str,
    platform: str,
    source_sha: str,
    archive_sha256: str,
) -> None:
    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ControllerError(
            "appliance adapter returned success without writing the required "
            f"transport receipt: {receipt_path}"
        ) from exc
    except json.JSONDecodeError as exc:
        raise ControllerError(f"invalid adapter transport receipt: {exc}") from exc

    expected = {
        "runtime": runtime,
        "version": version,
        "platform": platform,
        "source_sha": source_sha,
        "source_archive_sha256": archive_sha256,
        "build": "passed",
        "smoke_test": "passed",
    }
    for key, expected_value in expected.items():
        actual = receipt.get(key)
        if actual != expected_value:
            raise ControllerError(
                f"adapter receipt {key} mismatch: expected {expected_value!r}, got {actual!r}"
            )


def _staging_identity(output: Path) -> tuple[int, int]:
    try:
        info = os.lstat(output)
    except FileNotFoundError as exc:
        raise ControllerError(f"adapter output directory disappeared: {output}") from exc
    file_attributes = getattr(info, "st_file_attributes", 0)
    reparse_point = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0)
    if stat.S_ISLNK(info.st_mode) or (file_attributes & reparse_point):
        raise ControllerError(f"adapter output root may not be a symlink: {output}")
    if not stat.S_ISDIR(info.st_mode):
        raise ControllerError(f"adapter output root must be a directory: {output}")
    return info.st_dev, info.st_ino


def _validate_staging_output(output: Path) -> tuple[int, int]:
    identity = _staging_identity(output)
    entries = list(output.iterdir())
    if not entries:
        raise ControllerError("appliance adapter returned success with an empty output directory")
    for item in entries:
        if item.is_symlink():
            raise ControllerError(f"adapter output may not contain symlinks: {item.name}")
        if not item.is_file():
            raise ControllerError(
                f"adapter output must be flat regular files only: {item.name}"
            )
    return identity


def _prepare_requested_output(output: Path) -> None:
    if output.exists() or output.is_symlink():
        raise ControllerError(
            f"output path must not already exist before dispatch: {output}"
        )
    output.parent.mkdir(parents=True, exist_ok=True)


def _promote_output(
    staging: Path, output: Path, expected_identity: tuple[int, int]
) -> None:
    if output.exists() or output.is_symlink():
        raise ControllerError(f"output path appeared during dispatch: {output}")
    if _staging_identity(staging) != expected_identity:
        raise ControllerError("adapter output directory changed after validation")
    os.replace(staging, output)


def run_build(args: argparse.Namespace, appliance: dict[str, Any]) -> int:
    _require_build_args(args)
    source = args.source.resolve()
    output = Path(os.path.abspath(os.path.expanduser(str(args.output))))
    if not source.is_dir():
        raise ControllerError(f"source directory does not exist: {source}")
    _prepare_requested_output(output)

    with tempfile.TemporaryDirectory(prefix="featool-mex-source-") as temporary:
        temporary_root = Path(temporary)
        archive, archive_sha256 = create_source_archive(
            source, args.source_sha, temporary_root
        )
        receipt = temporary_root / "adapter-receipt.json"
        with tempfile.TemporaryDirectory(
            prefix=f".{output.name}.staging-", dir=str(output.parent)
        ) as staging_parent:
            staging_output = Path(staging_parent) / "artifact"
            staging_output.mkdir()
            command = resolve_executable(appliance["command"])
            command.extend(
                [
                    "--runtime",
                    args.runtime,
                    "--version",
                    args.version,
                    "--platform",
                    args.platform,
                    "--source-archive",
                    str(archive),
                    "--source-archive-sha256",
                    archive_sha256,
                    "--output",
                    str(staging_output),
                    "--receipt",
                    str(receipt),
                    "--source-sha",
                    args.source_sha,
                    "--serial",
                    "--smoke-test",
                ]
            )
            env = controller_environment(appliance)
            env["MEX_SOURCE_SHA"] = args.source_sha
            env["MEX_SOURCE_ARCHIVE_SHA256"] = archive_sha256
            print(
                "Dispatching preserved compatibility build to configured adapter for "
                f"{args.runtime}:{args.version}:{args.platform}."
            )
            print(f"Immutable source archive SHA256: {archive_sha256}")
            try:
                returncode = run_process_tree(
                    command,
                    env=env,
                    cwd=temporary_root,
                    timeout=BUILD_TIMEOUT_SECONDS,
                )
            except subprocess.TimeoutExpired as exc:
                raise ControllerError(
                    f"appliance adapter exceeded {BUILD_TIMEOUT_SECONDS} seconds"
                ) from exc
            if returncode:
                return returncode
            _verify_receipt(
                receipt,
                args.runtime,
                args.version,
                args.platform,
                args.source_sha,
                archive_sha256,
            )
            staging_identity = _validate_staging_output(staging_output)
            _verify_metadata(
                staging_output, args.runtime, args.version, args.platform, args.source_sha
            )
            _promote_output(staging_output, output, staging_identity)
    return 0


def main() -> int:
    args = parse_args()
    try:
        index = load_config(args.config.resolve())
        appliance = select_appliance(index, args.runtime, args.version, args.platform)
        resolve_executable(appliance["command"])
        if args.check:
            print(
                "Controller configuration is valid for "
                f"{args.runtime}:{args.version}:{args.platform}."
            )
            if args.probe:
                return run_probe(appliance)
            return 0
        if args.probe:
            raise ControllerError("--probe is only valid together with --check")
        return run_build(args, appliance)
    except ControllerError as exc:
        print(f"controller error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
