#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: check_macos_binary.sh <directory> <x86_64|arm64> <report-file> [allow-openmp] [max-deployment-target]" >&2
  exit 2
fi

artifact_dir="$1"
expected_arch="$2"
report_file="$3"
allow_openmp="false"
if [[ $# -ge 4 ]]; then
  allow_openmp="$4"
fi
max_deployment_target=""
if [[ $# -ge 5 ]]; then
  max_deployment_target="$5"
fi

if [[ $# -ge 5 && -z "$max_deployment_target" ]]; then
  echo "max-deployment-target must be non-empty" >&2
  exit 2
fi

mkdir -p "$(dirname "$report_file")"
: > "$report_file"

found=0
failed=0
while IFS= read -r -d '' binary; do
  found=$((found + 1))
  {
    echo "===== $(basename "$binary") ====="
    file "$binary"
    echo "architectures: $(lipo -archs "$binary")"
    otool -hv "$binary"
    otool -L "$binary"
    otool -l "$binary"
  } >> "$report_file"

  archs="$(lipo -archs "$binary")"
  if [[ "$archs" != "$expected_arch" ]]; then
    echo "$(basename "$binary"): expected exactly $expected_arch, found $archs" >&2
    failed=1
  fi

  deployment_target="$(
    otool -l "$binary" |
      awk '
        $1 == "cmd" && $2 == "LC_BUILD_VERSION" { build = 1; legacy = 0; next }
        $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { legacy = 1; build = 0; next }
        build && $1 == "minos" { print $2; exit }
        legacy && $1 == "version" { print $2; exit }
      '
  )"
  echo "minimum_macos: ${deployment_target:-unknown}" >> "$report_file"
  if [[ -n "$max_deployment_target" ]]; then
    if [[ -z "$deployment_target" ]]; then
      echo "$(basename "$binary"): could not determine macOS deployment target" >&2
      failed=1
    elif ! python3 - "$deployment_target" "$max_deployment_target" <<'PY'
import sys

def version(value):
    return tuple(int(part) for part in value.split("."))

raise SystemExit(0 if version(sys.argv[1]) <= version(sys.argv[2]) else 1)
PY
    then
      echo "$(basename "$binary"): deployment target $deployment_target exceeds $max_deployment_target" >&2
      failed=1
    fi
  fi

  if [[ "$allow_openmp" != "true" ]]; then
    deps="$(otool -L "$binary")"
    if grep -Eiq '(libgomp|libomp|libiomp)' <<<"$deps"; then
      echo "$(basename "$binary"): unexpected OpenMP runtime dependency" >&2
      failed=1
    fi
  fi
done < <(find "$artifact_dir" -maxdepth 1 -type f \( -name '*.mexmaci64' -o -name '*.mexmaca64' -o -name '*.mex' \) -print0)

if [[ "$found" -eq 0 ]]; then
  echo "no macOS MEX binaries found in $artifact_dir" >&2
  exit 1
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "macOS binary audit passed for $found MEX binaries"
