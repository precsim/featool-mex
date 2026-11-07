#!/usr/bin/env bash
set -euo pipefail

compiler="${1:?compiler name is required}"
shift

image="${MEX_MANYLINUX_IMAGE:?MEX_MANYLINUX_IMAGE must be set}"
workspace="${GITHUB_WORKSPACE:?GITHUB_WORKSPACE must be set}"
matlab_root="${MEX_MANYLINUX_MATLAB_ROOT:?MEX_MANYLINUX_MATLAB_ROOT must be set}"

docker_args=(
  run
  --rm
  --user "$(id -u):$(id -g)"
  --env HOME=/tmp
  --env TMPDIR=/tmp
  --volume "$workspace:$workspace"
  --volume "$matlab_root:$matlab_root:ro"
  --volume /tmp:/tmp
  --workdir "$PWD"
)

if [[ -n "${RUNNER_TEMP:-}" && "$RUNNER_TEMP" != /tmp* ]]; then
  docker_args+=(--volume "$RUNNER_TEMP:$RUNNER_TEMP")
fi

case "$PWD" in
  "$workspace"|"$workspace"/*|"$matlab_root"|"$matlab_root"/*|/tmp|/tmp/*)
    ;;
  *)
    if [[ -n "${RUNNER_TEMP:-}" ]]; then
      case "$PWD" in
        "$RUNNER_TEMP"|"$RUNNER_TEMP"/*) ;;
        *) docker_args+=(--volume "$PWD:$PWD") ;;
      esac
    else
      docker_args+=(--volume "$PWD:$PWD")
    fi
    ;;
esac

exec docker "${docker_args[@]}" "$image" "$compiler" "$@"
