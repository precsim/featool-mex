#!/usr/bin/env python3
"""Validate build_manifest.m against the source tree without compiling."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
MANIFEST = ROOT / "build_manifest.m"
OCTAVE_BLAS_COMPAT = ROOT / "compat" / "octave" / "blas.h"
OCTAVE_MEX_COMPAT = ROOT / "compat" / "octave" / "mex_compat.h"

TARGET_RE = re.compile(
    r"targets\((\d+)\)\s*=\s*make_target\("
    r"'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'",
    re.MULTILINE,
)
DEP_RE = re.compile(r"'(src_dep/[^']+\.(?:c|cpp))'")
INCLUDE_RE = re.compile(r'^\s*#include\s+"src_dep/([^"]+)\.h"', re.MULTILINE)
BOOL_RE = re.compile(r"\b(true|false)\b")


def fail(message: str) -> None:
    raise SystemExit(f"manifest check failed: {message}")


def main() -> int:
    text = MANIFEST.read_text(encoding="utf-8")
    matches = list(TARGET_RE.finditer(text))
    if not matches:
        fail("no targets found")

    entries: list[tuple[int, str, str, str, set[str], bool, bool]] = []
    for index, match in enumerate(matches):
        start = match.start()
        end = matches[index + 1].start() if index + 1 < len(matches) else text.find("\nend", start)
        if end < 0:
            end = len(text)
        block = text[start:end]
        deps = set(DEP_RE.findall(block))
        flags = BOOL_RE.findall(block)
        if len(flags) != 2:
            fail(
                f"{match.group(2)}: expected exactly two boolean manifest flags "
                f"(blas/openmp), found {flags}"
            )
        entries.append(
            (
                int(match.group(1)),
                match.group(2),
                match.group(3),
                match.group(4),
                deps,
                flags[0] == "true",
                flags[1] == "true",
            )
        )

    indices = [entry[0] for entry in entries]
    if indices != list(range(1, len(entries) + 1)):
        fail(f"target indices are not contiguous: {indices}")

    source_files = sorted(
        path.name
        for path in SRC.iterdir()
        if path.is_file() and path.suffix in {".c", ".cpp"}
    )
    manifest_sources = sorted(entry[3] for entry in entries)
    if source_files != manifest_sources:
        missing = sorted(set(source_files) - set(manifest_sources))
        extra = sorted(set(manifest_sources) - set(source_files))
        fail(f"source mismatch; missing={missing}, extra={extra}")

    names: set[str] = set()
    for _, name, language, source, deps, blas, openmp in entries:
        if name in names:
            fail(f"duplicate target name: {name}")
        names.add(name)

        expected_language = "cpp" if source.endswith(".cpp") else "c"
        if language != expected_language:
            fail(f"{name}: language={language}, expected {expected_language}")

        source_path = SRC / source
        source_text = source_path.read_text(encoding="utf-8", errors="replace")
        expected_deps: set[str] = set()
        dep_ext = ".cpp" if language == "cpp" else ".c"
        for header_base in INCLUDE_RE.findall(source_text):
            candidate = SRC / "src_dep" / f"{header_base}{dep_ext}"
            if candidate.exists():
                expected_deps.add(candidate.relative_to(SRC).as_posix())

        if deps != expected_deps:
            fail(
                f"{name}: dependencies={sorted(deps)}, "
                f"expected={sorted(expected_deps)}"
            )

        for dep in deps:
            if not (SRC / dep).is_file():
                fail(f"{name}: dependency does not exist: {dep}")

        dependency_text = "\n".join(
            (SRC / dep).read_text(encoding="utf-8", errors="replace")
            for dep in sorted(deps)
        )
        combined_text = source_text + "\n" + dependency_text
        has_openmp = "_OPENMP" in combined_text or "#pragma omp" in combined_text
        if openmp != has_openmp:
            fail(
                f"{name}: openmp={openmp}, but source OpenMP usage={has_openmp}"
            )

        has_blas_header = '"blas.h"' in combined_text or "<blas.h>" in combined_text
        if has_blas_header and not OCTAVE_BLAS_COMPAT.is_file():
            fail("Octave compatibility header is missing: compat/octave/blas.h")

        if not OCTAVE_MEX_COMPAT.is_file():
            fail("Octave compatibility header is missing: compat/octave/mex_compat.h")

        if blas:
            fail(f"{name}: BLAS linking is enabled although the baseline sources do not call BLAS")

    if len(entries) != len(source_files):
        fail(f"expected {len(source_files)} targets, found {len(entries)}")

    print(f"manifest check passed: {len(entries)} deterministic targets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
