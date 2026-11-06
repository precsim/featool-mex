#!/usr/bin/env python3
"""Inspect Linux MEX ELF architecture, dependencies, and symbol versions."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


NAMESPACES = ("GLIBC", "GLIBCXX", "CXXABI", "GCC")
VERSION_RE = re.compile(r"\b(GLIBC|GLIBCXX|CXXABI|GCC)_([0-9]+(?:\.[0-9]+)*)\b")
NEEDED_RE = re.compile(r"\(NEEDED\).*?\[([^\]]+)\]")
OPENMP_RE = re.compile(r"(?:libgomp|libomp|libiomp|vcomp)", re.IGNORECASE)


def run(*args: str) -> str:
    proc = subprocess.run(args, check=False, text=True, capture_output=True)
    if proc.returncode:
        sys.stderr.write(proc.stdout)
        sys.stderr.write(proc.stderr)
        raise RuntimeError(f"command failed ({proc.returncode}): {' '.join(args)}")
    return proc.stdout + proc.stderr


def run_diagnostic(*args: str) -> str:
    proc = subprocess.run(args, check=False, text=True, capture_output=True)
    return proc.stdout + proc.stderr


def version_tuple(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in value.split("."))


def highest(values: set[str]) -> str | None:
    if not values:
        return None
    return max(values, key=version_tuple)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--extensions", default="mexa64,mex")
    parser.add_argument("--max-glibc")
    parser.add_argument("--max-glibcxx")
    parser.add_argument("--max-cxxabi")
    parser.add_argument("--max-gcc")
    parser.add_argument("--allow-openmp", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    extensions = {f".{item.strip().lstrip('.')}" for item in args.extensions.split(",")}
    binaries = sorted(
        path for path in args.directory.iterdir() if path.is_file() and path.suffix in extensions
    )
    if not binaries:
        raise SystemExit(f"no Linux MEX binaries found in {args.directory}")

    report: dict[str, object] = {"platform": "linux-x86_64", "binaries": {}}
    failures: list[str] = []

    for binary in binaries:
        file_output = run("file", str(binary))
        header = run("readelf", "-h", str(binary))
        dynamic = run("readelf", "-d", str(binary))
        version_info = run("readelf", "--version-info", str(binary))
        symbols = run("objdump", "-T", str(binary))
        ldd_output = run_diagnostic("ldd", str(binary))

        if "x86-64" not in file_output and "X86-64" not in header:
            failures.append(f"{binary.name}: expected x86-64 ELF")

        dependencies = sorted(set(NEEDED_RE.findall(dynamic)))
        if not args.allow_openmp:
            openmp_deps = [dep for dep in dependencies if OPENMP_RE.search(dep)]
            if openmp_deps:
                failures.append(
                    f"{binary.name}: unexpected OpenMP dependencies: {openmp_deps}"
                )

        versions: dict[str, set[str]] = {name: set() for name in NAMESPACES}
        for namespace, value in VERSION_RE.findall(version_info + "\n" + symbols):
            versions[namespace].add(value)
        maxima = {name: highest(values) for name, values in versions.items()}

        ceilings = {
            "GLIBC": args.max_glibc,
            "GLIBCXX": args.max_glibcxx,
            "CXXABI": args.max_cxxabi,
            "GCC": args.max_gcc,
        }
        for namespace, ceiling in ceilings.items():
            if ceiling and maxima[namespace]:
                if version_tuple(maxima[namespace]) <= version_tuple(ceiling):
                    continue
                failures.append(
                    f"{binary.name}: {namespace}_{maxima[namespace]} exceeds "
                    f"configured ceiling {namespace}_{ceiling}"
                )

        report["binaries"][binary.name] = {
            "file": file_output.strip(),
            "dependencies": dependencies,
            "ldd_diagnostic": ldd_output.strip(),
            "max_symbol_versions": maxima,
        }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if failures:
        for failure in failures:
            print(f"ABI audit failed: {failure}", file=sys.stderr)
        return 1

    print(f"Linux ABI audit passed for {len(binaries)} MEX binaries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
