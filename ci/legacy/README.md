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

The controller must provide an executable named `mex-legacy-build` on `PATH`,
or set `MEX_LEGACY_BUILD_DRIVER` to an executable path. The workflow invokes:

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
audit/finalization scripts there. Linux controllers need `file`, `readelf`,
`objdump`, and `ldd`; Windows controllers need PowerShell plus `dumpbin`;
macOS controllers need `bash`, `file`, `lipo`, and `otool`. These tools
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
