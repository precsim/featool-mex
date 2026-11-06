# Legacy compatibility runner contract

The release workflow deliberately keeps GitHub's runner agent outside the
legacy operating system. Current Actions runner releases require a modern host
and cannot run directly on a RHEL/CentOS 5-class Linux image or on the old
macOS versions needed by historical MATLAB.

Each compatibility builder is therefore a supported self-hosted **controller**
runner that invokes a preserved build appliance (VM, physical host, or other
immutable environment). Controller runners use these labels:

- `self-hosted, mex-controller, linux, x64`
- `self-hosted, mex-controller, windows, x64`
- `self-hosted, mex-controller, macos, x64`
- `self-hosted, mex-controller, macos, arm64`

The repository now includes `ci/legacy/controller_driver.py`, which is the
default controller-side dispatcher. A controller may still set
`MEX_LEGACY_BUILD_DRIVER` to replace it with a site-specific executable. The
workflow invokes either dispatcher with:

```text
mex-legacy-build
  --runtime <matlab|octave>
  --version <runtime release/version>
  --platform <repository platform tag>
  --source <checked-out repository>
  --output <artifact directory>
  --source-sha <full Git commit SHA>
  --serial
  --smoke-test
```

The driver is responsible for copying the exact checked-out source SHA into the
preserved appliance, invoking this repository's `build.m` for MATLAB or
`build_octave.m` for Octave with OpenMP disabled, running
`test/smoke_mex.m` on that same runtime, and copying the resulting artifact
directory back to `--output`. It must propagate any build or smoke failure as
a non-zero exit code.

The bundled dispatcher deliberately does not know whether an appliance is a VM,
physical host, SSH target, or another preserved environment. It reads an
appliance map from `MEX_LEGACY_APPLIANCES_CONFIG`, defaulting to
`/etc/featool-mex/legacy-appliances.json` on Linux/macOS and
`%ProgramData%\featool-mex\legacy-appliances.json` on Windows. Start from
`ci/legacy/legacy-appliances.example.json`. Each exact
`runtime:version:platform` entry contains a `command` argv array. The dispatcher
executes that adapter directly, without a shell. The adapter protocol carries
`--runtime`, `--version`, `--platform`, `--source-sha`, `--serial`, and
`--smoke-test` from the workflow contract, but replaces the mutable `--source`
directory with `--source-archive <tar>` and
`--source-archive-sha256 <sha256>`. It also supplies `--output <staging-dir>`
and `--receipt <json-path>`. An optional `probe_command` is used only by
controller readiness checks and must not compile or build anything.

Adapter and probe executables must be absolute paths. An optional `pass_env`
array may name controller-local environment variables that an adapter needs for
protected credentials. The dispatcher starts adapters with a deliberately
restricted environment and refuses to forward `GITHUB_*` or `ACTIONS_*`
runner internals. Prefer OS credential stores or provider-specific protected
configuration over environment credentials where practical.

Before dispatch, the bundled driver verifies that the checkout's `HEAD` equals
the requested `--source-sha` and that the tracked worktree and Git index are
unchanged. It then uses `git archive <source-sha>` to create the only source
payload supplied to the appliance adapter. The adapter must verify the tarball
against `--source-archive-sha256`, transfer/unpack that verified payload into
the preserved appliance, and build from it. The same hash is exposed as
`MEX_SOURCE_ARCHIVE_SHA256`.

After the build and same-runtime smoke test pass, the adapter must write the
JSON file named by `--receipt`. It must echo `runtime`, `version`, `platform`,
`source_sha`, and `source_archive_sha256`, and set both `build` and `smoke_test`
to `"passed"`. The controller rejects success without this receipt or when any
receipt value differs. This makes source-transport acknowledgement part of the
adapter protocol instead of relying only on declarative `BUILD-INFO.json`.

On a successful adapter return, the bundled dispatcher also verifies that
`BUILD-INFO.json` reports the requested runtime, actual requested runtime
version, platform, source SHA, and `openmp=false`. This prevents a controller
from silently routing a release job to the wrong preserved appliance. Adapter
output is first written to controller-owned temporary staging, must consist only
of flat regular files, and is atomically renamed into the workflow output
directory only after these checks pass. The final output path must not already
exist, which prevents partial/stale artifacts from being silently reused.

## Provisioning a controller runner

The repository currently expects one modern controller for each label set:

| Platform | Required labels | MATLAB appliance mapping |
| --- | --- | --- |
| Linux x86_64 | `self-hosted,mex-controller,linux,x64` | `matlab:R2011a:linux-x86_64` |
| Windows x86_64 | `self-hosted,mex-controller,windows,x64` | `matlab:R2011a:windows-x86_64` |
| Intel macOS | `self-hosted,mex-controller,macos,x64` | `matlab:R2011a:macos-x86_64` |
| Apple silicon macOS | `self-hosted,mex-controller,macos,arm64` | `matlab:R2023b:macos-arm64` |

Use a supported modern operating system for the controller. The old runtime and
old operating system belong inside the preserved appliance, not on the GitHub
runner host. Download and unpack the current GitHub Actions runner using the
instructions under repository **Settings > Actions > Runners > New self-hosted
runner**. Runner registration tokens are time-limited and must never be checked
in. Prefer passing the token through the transient
`GITHUB_RUNNER_REGISTRATION_TOKEN` environment variable so it is not saved in
shell history. Then create the controller's appliance JSON outside the checkout
and run:

```text
# Linux / macOS
ci/legacy/provision-controller.sh \
  --platform linux-x86_64 \
  --runner-dir /opt/actions-runner \
  --repo-url https://github.com/precsim/featool-mex \
  --name mex-linux-x64-01 \
  --config /etc/featool-mex/legacy-appliances.json
```

For Windows, run an elevated PowerShell session when installing the runner as a
service:

```powershell
ci\legacy\provision-controller.ps1 `
  -Platform windows-x86_64 `
  -RunnerDir C:\actions-runner `
  -RepositoryUrl https://github.com/precsim/featool-mex `
  -RunnerName mex-windows-x64-01 `
  -ConfigPath C:\ProgramData\featool-mex\legacy-appliances.json
```

The provisioning scripts register the runner, add only the custom
`mex-controller` label, retain GitHub's default OS/architecture labels, place
`MEX_LEGACY_APPLIANCES_CONFIG` in the runner's `.env`,
and configure the runner as a service by default. They do not invoke MATLAB,
Octave, a compiler, or an appliance build. The controller service account must
have read access to the JSON and execute/access rights for the configured
adapter and its protected appliance credentials.

After registration, run the **MEX controller check** workflow manually for that
platform and supply the exact preserved Octave version configured on that
controller. The readiness check requires both the platform's MATLAB mapping and
that Octave mapping, validates required adapter environment variables, and
checks the controller audit toolchain. A GitHub-hosted watchdog observes this
workflow run's selected controller job and cancels the readiness run if that job
does not start within five minutes; this bounds failures caused by an offline
runner or incorrect labels without requiring repository Administration access.
With `probe=true` the controller job also invokes each adapter's explicitly
configured non-build `probe_command`. Only after this full platform check passes
should the corresponding release variables be enabled.

Keep self-hosted controller labels out of pull-request workflows. These runners
have access to preserved build infrastructure and should execute only trusted
manual/tag release workflows and the manual controller readiness check.

The driver must set `MEX_SOURCE_SHA` to the supplied `--source-sha` inside
the build appliance before invoking MATLAB/Octave. Runtime metadata must come
from the runtime itself: `build.m` records MATLAB's actual release and
`build_octave.m` records Octave's actual `version()`. Release finalization
rejects missing or mismatched source provenance or runtime-version metadata.

Before invoking MATLAB, the appliance should set
`MEX_COMPILER_DESCRIPTION` and `MEX_LINKER_DESCRIPTION` to versioned
toolchain descriptions. These values are written into `BUILD-INFO.json`;
they are especially useful for R2011a, where modern MATLAB compiler
configuration APIs are unavailable.

Controller hosts also need Python 3 because the workflow runs the repository
audit/finalization scripts there. All controllers need Git. Linux controllers
need `file`, `readelf`, `objdump`, and `ldd`; Windows controllers need Python,
PowerShell 7 (`pwsh`), and either `dumpbin` on `PATH` or Visual Studio C++
tools discoverable through `vswhere.exe`; macOS controllers need `bash`,
`file`, `lipo`, and `otool`. These tools
inspect the returned binaries on the controller rather than inside the preserved
appliance.

macOS compatibility releases require an explicit deployment-target ceiling for
each preserved appliance. Configure the following repository variables with the
newest target that the corresponding compatibility artifact is allowed to
require:

- `MEX_MATLAB_R2011A_MACOS_X64_MAX_DEPLOYMENT_TARGET`
- `MEX_MATLAB_R2023B_MACOS_ARM64_MAX_DEPLOYMENT_TARGET`
- `MEX_OCTAVE_MACOS_X64_MAX_DEPLOYMENT_TARGET`
- `MEX_OCTAVE_MACOS_ARM64_MAX_DEPLOYMENT_TARGET`

The release preflight rejects missing values. The Mach-O audit receives the
configured ceiling explicitly, fails if any returned MEX binary requires a
newer macOS target, and records the measured target in the artifact metadata.

All C targets require C99. The appliance must configure C compilation with
`-std=c99` (or an equivalent verified mode) in its explicit MEX options. The
repository build driver also adds `-std=c99` automatically for GNU/Clang-like
toolchains that it can identify.

Expected MATLAB appliances:

| Platform | Compatibility runtime | Environment objective |
| --- | --- | --- |
| `windows-x86_64` | R2011a x64 | verified C99-capable compiler/toolchain selected through explicit MEX options |
| `linux-x86_64` | R2011a x64 | glibc 2.5-class userspace/sysroot and supported GCC |
| `macos-x86_64` | R2011a Intel | oldest practical preserved macOS/Xcode combination |
| `macos-arm64` | R2023b arm64 | preserved supported Apple-silicon macOS environment |

Expected Octave appliances are configured empirically rather than hard-coded in
the repository. Once the oldest reproducible version on a platform passes the
full build, same-runtime smoke test, and ABI audit, record that exact
`version()` value in these repository variables:

- `MEX_OCTAVE_WINDOWS_VERSION`
- `MEX_OCTAVE_LINUX_VERSION`
- `MEX_OCTAVE_MACOS_X64_VERSION`
- `MEX_OCTAVE_MACOS_ARM64_VERSION`

Replace each `<validated-version>` placeholder in
`ci/legacy/legacy-appliances.example.json` with that platform's measured exact
Octave `version()` before installing the controller configuration. Use the same
value as the `octave_version` input when running the controller readiness check.

Set `ENABLE_MEX_OCTAVE_RELEASE=true` only after all four controller appliances
exist. Tag releases require those variables and build Octave artifacts on the
preserved versions, then forward-test the exact downloaded binaries on current
GitHub-hosted Octave installations without rebuilding.

Also set the following variables to the measured release ceilings established
by the preserved Linux Octave builder:

- `MEX_OCTAVE_LINUX_MAX_GLIBC`
- `MEX_OCTAVE_LINUX_MAX_GLIBCXX`
- `MEX_OCTAVE_LINUX_MAX_CXXABI`
- `MEX_OCTAVE_LINUX_MAX_GCC`

The release audit fails if any target imports a newer symbol in any configured
namespace.

The Windows sources use C99 features including variable-length arrays and
declarations in `for` initializers. If the compiler officially supported by
the preserved R2011a installation cannot compile those sources, the controller
must use an explicitly configured and validated C99-capable MEX toolchain
(for example through the per-language `mexopts.c`/`mexopts.cpp` support in
`build.m`). Do not claim an official-compiler R2011a build unless that exact
compiler has passed the full build and smoke suite.

The workflow performs platform binary inspection after the appliance returns
the artifacts. The Linux R2011a job enforces a maximum imported
`GLIBC_2.5` symbol version; if that objective proves impossible, change the
declared floor only after recording the measured replacement floor.

The R2011a C++ and compiler-runtime ceilings are not hard-coded because they
depend on the exact validated toolchain. Record the measured ceilings from the
preserved builder in these required repository variables before enabling a
compatibility release:

- `MEX_MATLAB_R2011A_LINUX_MAX_GLIBCXX`
- `MEX_MATLAB_R2011A_LINUX_MAX_CXXABI`
- `MEX_MATLAB_R2011A_LINUX_MAX_GCC`

The repository variable `ENABLE_MEX_LEGACY_RELEASE=true` is required before a
version tag can schedule these controller jobs. This prevents releases from
silently queueing for absent self-hosted runners. A manual workflow dispatch
runs the same compatibility builders and validation chain without publishing a
GitHub Release.

MATLAB licenses and credentials belong in the appliance/controller's protected
configuration or GitHub secrets. They must not be copied into this repository,
VM exports intended for distribution, or uploaded artifacts.
