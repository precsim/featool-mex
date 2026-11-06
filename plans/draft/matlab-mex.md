# MATLAB/Octave MEX build and compatibility plan

## Current execution policy

All MATLAB, Octave, and MEX compilation/build/test work for this repository runs
only on standard GitHub-hosted Actions runners. The self-hosted/preserved-runner
ideas later in this draft are historical design notes and are not part of the
active implementation.

The hosted release baseline is R2023a on `ubuntu-22.04` and `windows-2022`,
R2024b on `macos-15-intel` and `macos-15`, followed by fresh-runner testing
on newer MATLAB releases. R2011a-compatible source syntax and the legacy Matrix
API are retained, but the release must not claim an R2011a-tested artifact
unless a standard GitHub-hosted runner can actually provision and execute that
runtime.

## Goal

Build the MEX sources under `src/` on GitHub Actions or attached GitHub Actions runners for:

- Windows x86-64
- Linux x86-64
- macOS Intel x86-64
- macOS Apple silicon arm64

Produce MATLAB and Octave artifacts separately, with the widest practical backward and forward compatibility. The Linux build should follow the same principle as manylinux: compile against an old enough glibc/userspace that the resulting binary runs on newer mainstream glibc distributions, then verify the actual imported symbol versions before publishing.

The initial compatibility objective is:

- MATLAB x86-64: investigate R2011a as the primary build baseline, with R2010b/R2009b as optional experiments if they require no material source changes.
- MATLAB Apple silicon: R2023b or the oldest native Apple-silicon MATLAB release that can build the sources.
- Linux x86-64: aspirational glibc 2.5 floor, matching the Linux baseline documented for MATLAB R2011a and equivalent in spirit to `manylinux_2_5_x86_64`/`manylinux1`.
- Octave: determine an empirical minimum supported Octave version per platform, then build with that version and test the resulting binaries on newer Octave releases.

Compatibility claims must be based on successful runtime tests and binary ABI inspection. Do not infer compatibility only from a successful compile.

## Repository constraints

The current repository has no CI or general-purpose build system. The relevant files are:

- `build.m`: MATLAB build driver. It enumerates top-level `.c` and `.cpp` files under `src/`, discovers `src_dep` sources by shelling out to `grep`, and calls `mex`.
- `build.bat`: older direct GCC/MinGW Windows build example which points at MATLAB R2011a.
- `src/*.c`, `src/*.cpp`: top-level MEX entry points.
- `src/src_dep/*`: companion implementation sources compiled into selected MEX files.

The sources use the classic MATLAB C Matrix API. In particular:

- `mwSize` and `mwIndex` are used.
- `mxGetPr` is used throughout.
- `fsparse.c` uses `mxGetPi`, so it depends on the separate-complex API.
- sparse matrix access uses `mxGetIr`/`mxGetJc`.
- some sources include MATLAB `blas.h`.
- C++ sources use STL and are compatible with an old C++ language level.
- OpenMP is optional and guarded by `_OPENMP` in most sources.

This favors old Matrix API builds. A legacy MATLAB build should use `-largeArrayDims`. A build performed with newer MATLAB should explicitly request the old API with `-R2017b`; `-R2018a` is incompatible with the current `mxGetPi` usage unless the source is migrated to interleaved complex.

## Compatibility model

Use two distinct CI concepts:

1. **Compatibility build**: compile once using the oldest practical MATLAB/Octave toolchain for the target architecture.
2. **Forward-runtime test**: download exactly that binary on newer MATLAB/Octave environments and run it without rebuilding.

The release binary should come from the compatibility build. Newer runtimes are validation targets rather than release compilers.

For each platform, record these values in artifact metadata:

- source commit SHA
- MATLAB or Octave version used to build
- compiler and linker versions
- target architecture
- MEX extension
- minimum OS/deployment target where applicable
- imported dynamic libraries
- highest imported `GLIBC_*`, `GLIBCXX_*`, and `CXXABI_*` symbol versions on Linux
- whether OpenMP is enabled

## MATLAB target matrix

### Windows x86-64

Primary compatibility target:

- MATLAB R2011a x64.
- Use a compiler officially supported by that MATLAB release where possible.
- Prefer the normal `mex` driver over manually reproducing its link command.
- Experiment with a static compiler runtime only if it materially reduces redistribution dependencies and passes all runtime tests.

Validation targets:

- R2011a itself.
- One intermediate pre-R2018a release.
- One post-R2018a release.
- Latest MATLAB available on Windows.

Output:

- `*.mexw64`

Binary checks:

- PE x86-64 architecture.
- dependent DLL list.
- no accidental dependency on an unredistributable compiler runtime.
- no OpenMP runtime in the baseline artifact.

GitHub Actions execution:

- Use a self-hosted Windows runner or disposable Windows VM image containing R2011a for the legacy compatibility build.
- Use current GitHub-hosted `windows-2022` or `windows-2025` jobs with `matlab-actions` for newer forward-runtime tests.

### Linux x86-64

Primary compatibility target:

- MATLAB R2011a x64.
- Build in a RHEL 5/CentOS 5-class userspace, or an equivalently old controlled sysroot/toolchain, with glibc 2.5 as the aspirational ABI floor.
- Use the exact GCC family supported by R2011a once confirmed from the MathWorks compiler matrix.
- Compile with `-largeArrayDims`.
- Avoid CPU-specific optimizations newer than the x86-64 baseline. Do not use `-march=native`.

MATLAB R2011a documented that Linux systems with kernel 2.6 and glibc 2.5 or later were likely to run MATLAB. The manylinux model defines `manylinux_2_5_x86_64` as a promise that a binary works on mainstream glibc systems with glibc 2.5 or later. MEX files are not Python wheels and should not be labeled as formal manylinux wheels, but the same ABI discipline is appropriate.

The Linux compatibility goal is therefore:

```text
maximum imported GLIBC symbol version <= GLIBC_2.5
```

subject to what MATLAB's own libraries and the selected compiler actually require. Also audit:

```text
GLIBCXX_*
CXXABI_*
GCC_*
```

The C++ MEX files may make the libstdc++ floor more restrictive than the glibc floor. That must be measured independently.

Do not statically link glibc. The manylinux approach relies on the system glibc ABI and building against an old enough userspace; static glibc can break dynamic loading and resolver behavior.

Preferred build architecture:

```text
GitHub Actions workflow
        |
        v
self-hosted legacy Linux runner/VM
        |
        +-- R2011a installation
        +-- glibc 2.5 userspace/sysroot
        +-- MathWorks-supported GCC
        |
        v
*.mexa64 release artifacts
        |
        +--> readelf/objdump ABI audit
        +--> legacy MATLAB smoke tests
        +--> modern MATLAB smoke tests on hosted runners
```

The legacy builder should preferably be an immutable VM image. Containers are acceptable only if MATLAB R2011a and its licensing mechanism operate reliably inside the container and the host kernel is compatible with the old userspace. The release process must not depend on mutable packages from an EOL distribution mirror at build time; archive all required RPMs/toolchain inputs or bake them into the VM image.

ABI audit commands/scripts should collect at least:

- `file <mex>`
- `readelf -h <mex>`
- `readelf -d <mex>`
- `readelf --version-info <mex>`
- `objdump -T <mex>`
- `ldd <mex>` in a controlled environment for diagnostics only

Extract and fail on a symbol version newer than the configured floor. The audit script should report the maximum versions found for GLIBC, GLIBCXX, CXXABI, and GCC symbol namespaces.

If glibc 2.5 proves impossible because the supported compiler or C++ runtime imports newer symbols, define the actual measured floor explicitly, for example `glibc >= 2.12`, rather than silently weakening the claim. `manylinux_2_12` and `manylinux_2_17` can be used as familiar reference points, but release artifacts remain ordinary MATLAB MEX files.

Validation targets should include:

- the compatibility builder itself.
- at least one RHEL/CentOS 6-class glibc 2.12 environment if available.
- a glibc 2.17 environment.
- current Ubuntu or RHEL.
- several MATLAB generations, including current MATLAB.

Output:

- `*.mexa64`

### macOS Intel x86-64

Primary compatibility target:

- Investigate R2011a as the legacy baseline.
- Use the oldest practical macOS/Xcode combination supported by that MATLAB release.
- Build with the lowest practical `MACOSX_DEPLOYMENT_TARGET` accepted by the supported toolchain.

Output:

- `*.mexmaci64`

Validation:

- legacy MATLAB on the build host.
- intermediate Intel MATLAB releases.
- R2025b, which is the final MATLAB release supporting Intel Macs.

Current GitHub-hosted Intel macOS runners are `macos-15-intel` and `macos-26-intel`. These are useful for Octave and binary inspection but are too new to host a true R2011a build. A self-hosted legacy Intel Mac or preserved macOS VM is required for the oldest build floor.

Inspect each binary with:

- `file`
- `otool -hv`
- `otool -L`
- `otool -l` to verify minimum macOS load commands
- `codesign -dv --verbose=4` when signing is used

Do not create a universal MATLAB MEX as the primary artifact. MATLAB Intel and Apple-silicon releases are separate products and use different MEX extensions.

### macOS Apple silicon arm64

Primary compatibility target:

- MATLAB R2023b, subject to verification that it is the earliest native Apple-silicon release suitable for building these sources.
- Use native arm64 MATLAB and compiler.

Output:

- `*.mexmaca64`

Hosted runner:

- `macos-15` is currently an Apple-silicon GitHub-hosted runner.
- `macos-26` is also Apple silicon.

Use a pinned label rather than `macos-latest` in release builds.

Validation targets:

- oldest supported native Apple-silicon MATLAB build environment.
- current MATLAB on Apple silicon.

Inspect architecture and deployment target with `file`, `otool`, and `codesign` tooling.

## Octave target matrix

Octave artifacts must be separate from MATLAB artifacts. Build using Octave's MEX compatibility layer:

```text
mkoctfile --mex ...
```

The first implementation should discover the oldest Octave release that can compile and run the current source unchanged on each architecture. Do not assume Octave's MEX ABI has the same compatibility guarantees as MATLAB.

Proposed discovery matrix:

| Platform | Initial minimum-version investigation | Current-version validation |
| --- | --- | --- |
| Windows x86-64 | oldest readily reproducible 64-bit Octave with MEX support | current Octave |
| Linux x86-64 | old Octave built in the same old-glibc environment where practical | current Octave |
| macOS Intel | oldest reproducible Intel Octave compatible with the build host | current Intel Octave available for testing |
| macOS arm64 | oldest native arm64 Octave practical on supported macOS | current Octave |

For Linux Octave, apply the same symbol-version audit as MATLAB. The Octave MEX binary should receive a documented glibc floor based on the actual imported symbols. The MATLAB and Octave Linux binaries may end up with different glibc/libstdc++ floors.

Octave outputs should live under an Octave-specific artifact directory even if the file extension is simply `.mex`, to prevent accidental loading of the wrong runtime's binary.

## Build manifest

Replace the current dependency discovery based on external `grep` with a deterministic manifest shared by MATLAB and Octave build drivers.

The manifest should describe, for every top-level MEX target:

- target name
- source language
- entry-point source
- companion `src_dep` sources
- whether BLAS is required
- whether OpenMP is supported
- any per-target compile definitions

The current `build.m` behavior of translating `#include "src_dep/X.h"` into `src_dep/X.c` or `.cpp` is clever but fragile and depends on Unix `grep`, including on Windows. A manifest makes CI deterministic and removes shell parsing from MATLAB.

Use one source of truth. MATLAB and Octave build scripts should consume the same manifest rather than maintaining two lists.

Suggested files:

```text
build.m                         MATLAB entry point
build_octave.m                  Octave entry point
build_manifest.m                target/dependency manifest
test/smoke_mex.m                shared functional smoke tests
ci/check_linux_abi.py           ELF symbol/dependency audit
ci/check_macos_binary.sh        Mach-O architecture/deployment audit
ci/check_windows_binary.ps1     PE dependency/architecture audit
.github/workflows/mex-ci.yml    pull-request CI
.github/workflows/mex-release.yml full compatibility/release matrix
```

If MATLAB versions this old cannot parse newer MATLAB syntax, keep `build.m`, the manifest, and smoke tests compatible with R2011a syntax. Avoid strings, arguments blocks, modern table APIs, `contains`, and other post-R2011a language/library features.

## MATLAB build driver changes

Refactor `build.m` so it:

1. creates the output directory when missing;
2. consumes the explicit build manifest;
3. supports building one target or all targets;
4. supports `api='legacy'` as the default;
5. uses `-largeArrayDims` under old MATLAB;
6. uses `-R2017b` when running under MATLAB versions that support the flag;
7. never selects `-R2018a` for the existing source;
8. supports `openmp=false` as the release default;
9. reports the full compiler/linker command in CI logs;
10. writes build metadata next to the artifacts.

Preserve optional custom MEX options files only where they are still useful. Do not let a locally present `opt/` configuration silently change release-build ABI characteristics.

## OpenMP policy

The baseline release binaries should be serial builds.

Reasons:

- Windows OpenMP can add `vcomp` or `libiomp` dependencies.
- GCC builds can add `libgomp` and potentially newer glibc/libpthread requirements.
- macOS usually requires an additional `libomp` runtime.
- runtime redistribution requirements make old-version portability harder.

After serial artifacts pass the complete compatibility matrix, an optional second artifact family may be added:

```text
matlab-<platform>-openmp
octave-<platform>-openmp
```

OpenMP artifacts must have separate dependency audits and must never replace the portable serial artifacts.

## Smoke tests

Every release artifact must first load and run on the environment that built it. The test suite should then be reused unchanged for forward-runtime validation.

Minimum tests:

1. `chkmex` loads and returns the expected scalar.
2. `earrind`/`eindarr` produce the same result as equivalent MATLAB/Octave indexing.
3. `findsp` or `fsparse` is tested on a deterministic small sparse matrix, including a complex case for `fsparse` so `mxGetPi` is exercised.
4. `spsetd` is tested against an equivalent interpreted implementation.
5. `iluk_Cmex` is tested on a small sparse matrix and compared with expected L/U behavior.
6. one representative assembler MEX is invoked with a small valid fixture if a compact stable fixture can be maintained.

Tests should compare numerical results with a tolerance where floating-point ordering can vary. A successful `load` alone is insufficient.

## GitHub Actions structure

Use two workflows.

### `mex-ci.yml`

Runs on pull requests and ordinary pushes.

Keep it relatively fast:

- current Linux MATLAB source build and smoke test.
- current Windows MATLAB source build and smoke test.
- current Linux Octave build and smoke test.
- current macOS arm64 Octave or MATLAB smoke build when minutes permit.
- syntax/manifest checks.

This workflow proves that source changes remain buildable. It does not produce compatibility release artifacts.

### `mex-release.yml`

Runs on version tags and `workflow_dispatch`.

Stages:

1. legacy compatibility builds on self-hosted/preserved runners;
2. hosted modern architecture builds where no legacy runtime exists, especially Apple silicon;
3. binary ABI inspection;
4. same-runtime smoke tests;
5. artifact upload;
6. forward-runtime test jobs which download those artifacts without rebuilding;
7. release bundle assembly;
8. GitHub Release attachment after all mandatory jobs pass.

Use artifact dependencies so a validation job cannot accidentally rebuild the source. The forward test must consume the exact SHA256-identified artifact produced by the compatibility job.

## Runner strategy

Use GitHub-hosted runners for modern validation and self-hosted or preserved VM runners only where an old runtime/OS is required.

Suggested labels:

```text
self-hosted, matlab-r2011a, windows, x64
self-hosted, matlab-r2011a, linux, x64, glibc-2.5
self-hosted, matlab-r2011a, macos, x64
```

Modern hosted jobs can use currently supported labels such as:

```text
windows-2022
ubuntu-22.04
macos-15-intel
macos-15
```

Pin release workflows to explicit OS labels. Avoid `*-latest` because runner-image migrations can alter compiler, SDK, and deployment-target behavior without a repository change.

The legacy runner images should be treated as build appliances:

- no automatic OS package upgrades;
- no automatic MATLAB upgrades;
- fixed compiler installation;
- fixed license configuration method;
- runner itself can update only after a verification build;
- snapshot/hash the VM image used for each release.

## MATLAB licensing in CI

Legacy self-hosted runners will need a valid noninteractive MATLAB license arrangement appropriate for the organization's license. Keep license secrets outside the repository and inject them using GitHub Actions secrets or runner-local protected configuration.

Do not bake user credentials or reusable license secrets into VM images or uploaded artifacts.

Modern `matlab-actions` jobs can use the supported MathWorks CI licensing mechanism for releases supported by those actions. Since `setup-matlab` does not provision R2011a, legacy builders remain separate.

## Artifact layout

Use runtime and architecture in the directory structure rather than relying on extension alone:

```text
dist/
  matlab/
    windows-x86_64/
    linux-x86_64/
    macos-x86_64/
    macos-arm64/
  octave/
    windows-x86_64/
    linux-x86_64/
    macos-x86_64/
    macos-arm64/
```

Each platform directory should include:

- MEX binaries
- required `.m` wrappers such as `iluk.m`
- `BUILD-INFO.json` or equivalent metadata
- `SHA256SUMS`
- a compact compatibility statement generated from validated jobs

Example compatibility metadata for Linux:

```json
{
  "runtime": "matlab",
  "arch": "x86_64",
  "built_with": "R2011a",
  "mex_extension": "mexa64",
  "glibc_floor": "2.5",
  "glibcxx_floor": "measured-value",
  "openmp": false,
  "source_sha": "..."
}
```

Only write `glibc_floor: 2.5` after the symbol audit and runtime matrix prove it.

## Release acceptance criteria

A platform artifact is releasable when all of the following are true:

- every expected MEX target was produced;
- architecture matches the intended target;
- baseline smoke tests pass on the build runtime;
- forward-runtime smoke tests pass on the configured newer runtimes;
- no unexpected dynamic library dependencies are present;
- Linux imported symbol versions satisfy the declared ABI floor;
- macOS deployment target is no newer than intended;
- Windows compiler runtime dependencies are either system-provided, redistributable, or intentionally bundled/documented;
- OpenMP is absent from the baseline build;
- metadata and checksums are present.

If a single MEX target requires a newer ABI than the others, do not silently raise the floor for the entire project. First investigate whether the dependency comes from compiler defaults or one source file. If it cannot be avoided, allow per-target compatibility metadata or split that target into a newer compatibility tier.

## Implementation phases

### Phase 1: deterministic local build

- Add `build_manifest.m`.
- Refactor `build.m` to remove the `grep` dependency.
- Add `build_octave.m` using the same manifest.
- Keep release builds serial.
- Add deterministic smoke tests.
- Confirm all current sources build on one modern MATLAB and one modern Octave installation before adding CI complexity.

### Phase 2: modern hosted CI

- Add current Windows/Linux/macOS jobs.
- Verify MATLAB and Octave source builds.
- Add binary inspection scripts.
- Establish artifact naming and metadata.

### Phase 3: R2011a legacy builders

- Provision reproducible Windows x64, Linux x64, and Intel macOS legacy environments.
- Build with R2011a and its supported compilers.
- Run same-runtime smoke tests.
- On Linux, measure GLIBC/GLIBCXX/CXXABI/GCC symbol floors.
- Iterate compiler flags/toolchain only when the measured ABI floor is unnecessarily high.

### Phase 4: forward compatibility matrix

- Download R2011a-built artifacts on newer MATLAB workers.
- Test without rebuilding.
- Include a pre-R2018a release, a post-R2018a release, and a current release where infrastructure permits.
- Test Intel macOS through R2025b, the final Intel MATLAB release.
- Test Apple silicon from the earliest native release through current MATLAB.

### Phase 5: older-than-R2011a experiment

After R2011a is stable, test R2010b and then R2009b on x86-64 where a reproducible toolchain can be preserved.

Adopt an older baseline only when:

- all MEX targets compile without invasive source forks;
- the resulting binaries pass the same forward test matrix;
- the older compiler does not introduce a worse runtime dependency problem;
- maintaining the build image is practical.

R2011a remains the default baseline until an older release proves objectively better.

### Phase 6: release automation

- Require the full compatibility matrix on release tags.
- Assemble platform bundles.
- Publish checksums and build metadata.
- Attach artifacts to GitHub Releases.
- Keep CI logs or generated reports that show the ABI floors used for each release.

## Risks to resolve experimentally

### Old glibc vs old libstdc++

`iluk_Cmex*.cpp` may import C++ runtime symbols newer than the target glibc floor. The release claim must include both libc and C++ ABI requirements. An old-enough GCC/libstdc++ or careful static linking of `libstdc++`/`libgcc` may help, but static C++ runtime linking should only be adopted after confirming there are no exception/allocator/ABI interactions with MATLAB.

### MATLAB-provided BLAS

Sources include MATLAB `blas.h`. Prefer linking through MATLAB's MEX configuration so BLAS symbol naming and library selection match the target MATLAB. Direct compiler/linker builds should be treated as a fallback requiring extra validation.

### Complex Matrix API transition

`fsparse.c` uses `mxGetPi`. Keep the legacy separate-complex API for maximum compatibility. A future source modernization to interleaved complex should be a separate project and would likely require maintaining dual source/API paths if old MATLAB remains supported.

### Old macOS preservation

Old Intel MATLAB cannot be installed on current GitHub macOS images. Long-term reproducibility may require preserved physical Intel hardware or a legally and technically viable macOS VM setup. Treat the legacy Intel build image as infrastructure that needs its own backup/export process.

### EOL Linux package repositories

Do not make release builds fetch CentOS/RHEL 5-era packages from arbitrary live mirrors. Once the toolchain is validated, archive the exact packages or preserve a complete VM/container image so the build can be reproduced after mirrors disappear.

## References

- MathWorks R2011a Linux system requirements: https://www.mathworks.com/content/dam/mathworks/mathworks-dot-com/support/sysreq/files/SystemRequirements-Release2011a_Linux.pdf
- MathWorks previous release requirements/compiler index: https://www.mathworks.com/support/requirements/previous-releases.html
- MathWorks MEX documentation: https://www.mathworks.com/help/matlab/ref/mex.html
- MathWorks Apple silicon information: https://www.mathworks.com/support/requirements/apple-silicon.html
- GitHub-hosted runner labels: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- PEP 600, perennial manylinux/glibc compatibility model: https://peps.python.org/pep-0600/
- PEP 513, rationale for old-glibc builds and avoiding static glibc: https://peps.python.org/pep-0513/

