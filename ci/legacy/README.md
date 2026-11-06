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
  --runtime matlab
  --version <MATLAB release>
  --platform <repository platform tag>
  --source <checked-out repository>
  --output <artifact directory>
  --serial
  --smoke-test
```

The driver is responsible for copying the exact checked-out source SHA into the
preserved appliance, invoking this repository's `build.m` with OpenMP disabled,
running `test/smoke_mex.m` on that same runtime, and copying the resulting
artifact directory back to `--output`. It must propagate any build or smoke
failure as a non-zero exit code.

Before invoking MATLAB, the appliance should set
`MEX_COMPILER_DESCRIPTION` and `MEX_LINKER_DESCRIPTION` to versioned
toolchain descriptions. These values are written into `BUILD-INFO.json`;
they are especially useful for R2011a, where modern MATLAB compiler
configuration APIs are unavailable.

Expected MATLAB appliances:

| Platform | Compatibility runtime | Environment objective |
| --- | --- | --- |
| `windows-x86_64` | R2011a x64 | compiler supported by the preserved MATLAB installation |
| `linux-x86_64` | R2011a x64 | glibc 2.5-class userspace/sysroot and supported GCC |
| `macos-x86_64` | R2011a Intel | oldest practical preserved macOS/Xcode combination |
| `macos-arm64` | R2023b arm64 | preserved supported Apple-silicon macOS environment |

The workflow performs platform binary inspection after the appliance returns
the artifacts. The Linux R2011a job enforces a maximum imported
`GLIBC_2.5` symbol version; if that objective proves impossible, change the
declared floor only after recording the measured replacement floor.

The repository variable `ENABLE_MEX_LEGACY_RELEASE=true` is required before a
version tag can schedule these controller jobs. This prevents releases from
silently queueing for absent self-hosted runners. A manual workflow dispatch
can also explicitly select the compatibility builders.

MATLAB licenses and credentials belong in the appliance/controller's protected
configuration or GitHub secrets. They must not be copied into this repository,
VM exports intended for distribution, or uploaded artifacts.
