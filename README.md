# FEATool MEX

Cross-platform build and release infrastructure for the original FEATool MEX source tree.

The complete `src/` directory is intentionally kept byte-for-byte identical to commit
`e752f56bb6a122b75a0562f4085ab2840d2a6e8d`. Portability and release support live
outside `src/` so the imported source remains unchanged.

Prebuilt binaries are produced and tested entirely on standard GitHub-hosted Actions runners. MATLAB and Octave artifacts are published separately for Linux, Windows, Intel macOS, and Apple-silicon macOS.

## Download a release

Use the [latest GitHub Release](https://github.com/precsim/featool-mex/releases/latest).

Choose exactly one ZIP for your runtime and platform:

| Runtime | Platform | Release asset |
| --- | --- | --- |
| MATLAB | Linux x86-64 | `matlab-linux-x86_64.zip` |
| MATLAB | Windows x86-64 | `matlab-windows-x86_64.zip` |
| MATLAB | macOS Intel | `matlab-macos-x86_64.zip` |
| MATLAB | macOS Apple silicon | `matlab-macos-arm64.zip` |
| GNU Octave | Linux x86-64 | `octave-linux-x86_64.zip` |
| GNU Octave | Windows x86-64 | `octave-windows-x86_64.zip` |
| GNU Octave | macOS Intel | `octave-macos-x86_64.zip` |
| GNU Octave | macOS Apple silicon | `octave-macos-arm64.zip` |

Do not mix MATLAB and Octave bundles. MATLAB uses platform-specific MEX extensions such as `.mexa64`, `.mexw64`, `.mexmaci64`, and `.mexmaca64`; the Octave bundles contain Octave `.mex` binaries.

## Installation

1. Download the ZIP that matches your runtime and architecture.
2. Download the release-level `SHA256SUMS` file and verify the ZIP before extracting it.
3. Extract the ZIP. It contains one top-level directory named after the bundle, for example `matlab-linux-x86_64`.
4. Keep the complete extracted directory together. In particular, `iluk.m` is shipped alongside its compiled MEX helpers.
5. Add the extracted directory to the MATLAB or Octave search path.

For MATLAB:

```matlab
addpath('/path/to/matlab-linux-x86_64')
savepath
```

For GNU Octave:

```octave
addpath('/path/to/octave-linux-x86_64')
savepath
```

Replace the example directory with the bundle you downloaded. If you do not want to modify the persistent search path, omit `savepath` and call `addpath` when starting a session instead.

You can confirm that MATLAB or Octave resolves a shipped function from the extracted directory, for example:

```matlab
which fsparse
which iluk
```

### Verify the release ZIP

The GitHub Release contains a `SHA256SUMS` file with the SHA-256 digest of every published ZIP. Compare the digest of your downloaded file with the matching line in that file.

Linux:

```sh
sha256sum matlab-linux-x86_64.zip
```

macOS:

```sh
shasum -a 256 matlab-macos-arm64.zip
```

Windows PowerShell:

```powershell
Get-FileHash .\matlab-windows-x86_64.zip -Algorithm SHA256
```

Each extracted bundle also contains its own `SHA256SUMS`, covering the files inside that bundle.

## What is in each bundle

Each release bundle contains the 13 compiled targets defined by `build_manifest.m`:

`assemble_f`, `assemble_m`, `assemble_s`, `assemble_se`, `chkmex`, `earrind`, `eindarr`, `findsp`, `fsetop`, `fsparse`, `iluk_Cmex`, `iluk_Cmex_nosymb`, and `spsetd`.

The `iluk.m` MATLAB/Octave wrapper is included with the binaries. Release bundles also contain build and validation metadata:

- `BUILD-INFO.json` — source SHA, runtime used for the build, compiler information, target list, and binary-audit results.
- `COMPATIBILITY.txt` — build compatibility statement.
- `HOSTED-VALIDATION.txt` — records the GitHub-hosted fresh-runner validation for the published artifact.
- `SHA256SUMS` — checksums for the files inside the extracted bundle.
- A platform ABI report such as `linux-ABI.json`, `windows-ABI.txt`, or `macos-ABI.txt`.

Release binaries are serial builds; OpenMP is disabled for the published baseline.

## Tested release configurations

The table below describes what the release pipeline actually executes. These are tested configurations, not a claim that every older, newer, or intermediate runtime is supported.

### MATLAB

| Platform | Release build environment | Fresh-runner validation environment |
| --- | --- | --- |
| Linux x86-64 | MATLAB R2023a on `ubuntu-22.04`, with GCC/G++ executed inside `manylinux2014` (glibc 2.17) | MATLAB R2026b on `ubuntu-24.04` |
| Windows x86-64 | MATLAB R2023a on `windows-2022`, MinGW 8.1 | MATLAB R2026b on `windows-2025` |
| macOS Intel | MATLAB R2024b on `macos-15-intel` | MATLAB R2025b on `macos-15-intel` |
| macOS Apple silicon | MATLAB R2024b on `macos-15` | MATLAB R2026b on `macos-15` |

The MATLAB release build uses the legacy Matrix API compatibility path. On Linux, MATLAB itself runs on the GitHub-hosted Ubuntu runner while every GCC/G++ compile and link command is executed inside the `manylinux2014` container. The Linux ABI audit rejects any MEX binary that imports a `GLIBC_*` symbol newer than `GLIBC_2.17`. This is a manylinux-style ABI target for ordinary `.mexa64` files; the artifacts are not Python wheels and do not carry a formal manylinux tag.

The source intentionally keeps conservative MATLAB syntax, but the published release does **not** claim that MATLAB R2011a was built or tested. R2011a is not provisioned by the GitHub-hosted MATLAB setup used by this repository.

### GNU Octave

| Platform | Release build environment | Fresh-runner validation environment |
| --- | --- | --- |
| Linux x86-64 | Octave 6.4.0 on `ubuntu-22.04` | Fresh `ubuntu-24.04` runner with repository Octave package |
| Windows x86-64 | Octave 11.3.0 on `windows-2022` | Fresh `windows-2025` runner with Chocolatey Octave |
| macOS Intel | Octave 11.3.0 on `macos-15-intel` | Fresh `macos-15-intel` runner with Homebrew Octave |
| macOS Apple silicon | Octave 11.3.0 on `macos-15` | Fresh `macos-15` runner with Homebrew Octave |

For every platform, the release workflow first builds and smoke-tests the MEX files on the release builder, performs a platform-specific binary/ABI audit, uploads the exact artifact, then downloads that same artifact onto a fresh GitHub-hosted runner and smoke-tests it again **without rebuilding**. Checksums are verified before and after the fresh-runner test.

The exact source commit, compiler information, runtime used for the build, and ABI audit are preserved inside each bundle in `BUILD-INFO.json`.

## Release process

Version tags matching `v*` trigger `.github/workflows/mex-release.yml`. A successful tagged release performs the complete MATLAB and Octave build matrix, same-runtime smoke tests, ABI audits, fresh-runner downloaded-artifact tests, checksum verification, bundle assembly, and GitHub Release publication.

Normal pull requests use the hosted MEX CI workflow before changes are merged. No self-hosted build machine is required by the active build or release path.

## License

This repository is licensed under the GNU Affero General Public License, version 3. See [`LICENSE`](LICENSE).
