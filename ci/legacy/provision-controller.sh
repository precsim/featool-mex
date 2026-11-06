#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: provision-controller.sh \
  --platform <linux-x86_64|macos-x86_64|macos-arm64> \
  --runner-dir <unpacked GitHub Actions runner directory> \
  --repo-url <https://github.com/owner/repo> \
  [--token <one-hour runner registration token>] \
  --name <runner name> \
  --config <absolute legacy-appliances.json path> [--no-service]

If --token is omitted, set GITHUB_RUNNER_REGISTRATION_TOKEN in the environment.
The script registers a modern self-hosted controller only. It never launches a
MATLAB/Octave build or the preserved appliance.
EOF
}

platform=""
runner_dir=""
repo_url=""
token=""
runner_name=""
config=""
install_service=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) platform="$2"; shift 2 ;;
    --runner-dir) runner_dir="$2"; shift 2 ;;
    --repo-url) repo_url="$2"; shift 2 ;;
    --token) token="$2"; shift 2 ;;
    --name) runner_name="$2"; shift 2 ;;
    --config) config="$2"; shift 2 ;;
    --no-service) install_service=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$token" ]]; then
  token="${GITHUB_RUNNER_REGISTRATION_TOKEN:-}"
fi

for value in platform runner_dir repo_url token runner_name config; do
  if [[ -z "${!value}" ]]; then
    echo "Missing required option for $value" >&2
    usage >&2
    exit 2
  fi
done

runner_dir="$(cd "$runner_dir" && pwd -P)"
config="$(cd "$(dirname "$config")" && pwd -P)/$(basename "$config")"

if [[ ! -x "$runner_dir/config.sh" ]]; then
  echo "Expected executable $runner_dir/config.sh" >&2
  exit 2
fi
if [[ ! -f "$config" ]]; then
  echo "Controller config does not exist: $config" >&2
  exit 2
fi
if [[ -e "$runner_dir/.runner" ]]; then
  echo "Runner directory is already configured. Remove the existing runner before reprovisioning." >&2
  exit 2
fi

kernel="$(uname -s)"
machine="$(uname -m)"
case "$platform" in
  linux-x86_64)
    [[ "$kernel" == "Linux" ]] || { echo "linux-x86_64 requires Linux" >&2; exit 2; }
    [[ "$machine" == "x86_64" || "$machine" == "amd64" ]] || { echo "linux-x86_64 requires x86_64" >&2; exit 2; }
    labels="mex-controller"
    ;;
  macos-x86_64)
    [[ "$kernel" == "Darwin" ]] || { echo "macos-x86_64 requires macOS" >&2; exit 2; }
    [[ "$machine" == "x86_64" ]] || { echo "macos-x86_64 requires x86_64" >&2; exit 2; }
    labels="mex-controller"
    ;;
  macos-arm64)
    [[ "$kernel" == "Darwin" ]] || { echo "macos-arm64 requires macOS" >&2; exit 2; }
    [[ "$machine" == "arm64" || "$machine" == "aarch64" ]] || { echo "macos-arm64 requires arm64" >&2; exit 2; }
    labels="mex-controller"
    ;;
  *)
    echo "Unsupported platform: $platform" >&2
    exit 2
    ;;
esac

(
  cd "$runner_dir"
  ./config.sh \
    --unattended \
    --replace \
    --url "$repo_url" \
    --token "$token" \
    --name "$runner_name" \
    --labels "$labels" \
    --work _work
)

# config.sh regenerates the runner's .env. Add the controller-local setting only
# after registration and before installing/starting the service.
env_file="$runner_dir/.env"
tmp_env="$runner_dir/.env.featool-mex.$$"
if [[ -f "$env_file" ]]; then
  grep -v '^MEX_LEGACY_APPLIANCES_CONFIG=' "$env_file" > "$tmp_env" || true
else
  : > "$tmp_env"
fi
printf 'MEX_LEGACY_APPLIANCES_CONFIG=%s\n' "$config" >> "$tmp_env"
mv "$tmp_env" "$env_file"
chmod 600 "$env_file"

if [[ "$install_service" -eq 1 ]]; then
  if [[ ! -x "$runner_dir/svc.sh" ]]; then
    echo "Runner configured, but svc.sh is unavailable; service was not installed." >&2
    exit 2
  fi
  if [[ "$kernel" == "Linux" ]]; then
    (
      cd "$runner_dir"
      sudo ./svc.sh install "$(id -un)"
      sudo ./svc.sh start
      sudo ./svc.sh status
    )
  else
    (
      cd "$runner_dir"
      ./svc.sh install
      ./svc.sh start
      ./svc.sh status
    )
  fi
fi

echo "Controller runner '$runner_name' registered for $platform."
echo "No MATLAB/Octave build was executed. Run the MEX controller check workflow next."
