# Known limitations and release-specific behavior

The original FEATool MEX source was imported at commit
`e752f56bb6a122b75a0562f4085ab2840d2a6e8d`. Release `v0.1.0` preserved that
complete `src/` tree byte-for-byte. Starting with `v0.1.1`, the project
intentionally introduced reviewed source-level correctness, validation, and
portability fixes. Later releases therefore do not share the `v0.1.0` source
freeze.

The sections below record important release-specific behavior discovered during
subsequent review. This is not intended to be an exhaustive list of every
possible malformed-input or numerical edge case.

## `v0.1.0`: original frozen source

The following limitations apply to the original imported implementation and the
`v0.1.0` binaries.

### Input validation and indexing

- `earrind` and `eindarr` perform limited validation of indices and related
  inputs. Callers should validate that index data is finite, integer-valued,
  in range, and otherwise compatible before invoking these MEX functions.
- `assemble_f` and `assemble_s` do not contain the later connectivity-index
  guards. Element connectivity should be finite, integer-valued, in range, and
  consistent with the supplied arrays.
- `fsparse` does not contain the later guards for oversized indices and thread
  counts near the limits of the implementation's integer types.

### Sparse-matrix behavior

- `spsetd` uses its historical no-output, in-place mutation behavior. Later
  hardening changed the interface to return a modified sparse matrix and added
  validation for complex sparse input, invalid rows, and rows without a usable
  diagonal entry.
- `findsp` predates later validation for complex sparse input, output counts,
  empty sparse matrices, and index-output handling.
- `fsetop` predates fixes for edge cases involving signed zero, empty rows and
  cells, and preservation of classes such as `single`, `char`, and `logical`.
- `fsparse` predates later fixes for complex full-array conversion and several
  boundary cases.

### ILU factorization

The original `iluk`, `iluk_Cmex`, and `iluk_Cmex_nosymb` implementations
predate later validation for malformed or incompatible inputs. Users of
`v0.1.0` should provide sparse double matrices with a compatible sparsity
pattern, valid diagonal pivots, and conservative nonnegative integer fill
levels.

### Assembly model restrictions and numerical behavior

- The nonlinear `NeoHookean_*` and `RaghavanVorp_*` paths in `assemble_s` do
  not enforce their three-dimensional restriction at the MEX boundary in
  `v0.1.0`; do not use those model paths with two-dimensional input.
- The `SUPG_SemiImplicit` path of `assemble_f` contains the original density
  scaling expression. The corrected density scaling is not present in
  `v0.1.0`.

## `v0.1.1`: broad source hardening

`v0.1.1` no longer matches the original `src/` tree. It incorporates broad MEX
hardening developed after `v0.1.0`, including stronger index and connectivity
validation, sparse-input checks, safer `spsetd` behavior, `fsetop` edge-case
handling, `fsparse` boundary handling, and related portability fixes.

These changes address many of the original-source limitations listed above.
They do not include all fixes introduced in subsequent releases.

## `v0.1.2`: numerical, model, and ILU corrections

`v0.1.2` adds further source-level corrections, including:

- corrected density scaling in `assemble_f`'s `SUPG_SemiImplicit` path;
- explicit three-dimensional guards for the nonlinear `NeoHookean_*` and
  `RaghavanVorp_*` assembly paths; and
- stronger `iluk`, `iluk_Cmex`, and `iluk_Cmex_nosymb` validation for input
  types, fill levels, pivots, argument/output counts, and reused level
  structures.

The `v0.1.2` source tree therefore also differs intentionally from the original
import and from `v0.1.1`.

## `v0.2.0`: additional index and `findsp` hardening

`v0.2.0` adds further validation for complex index and related inputs in
`earrind` and `eindarr`. It also removes `findsp`'s assumption that `mwIndex`
is always 64 bits by converting sparse index values explicitly to the
documented `uint64` outputs.

## Release scope

The GitHub Actions release pipeline verifies that each release builds, loads,
and passes its smoke tests on the documented MATLAB and GNU Octave
configurations. Those checks establish the tested build/runtime behavior; they
are not a claim that every unsupported runtime, malformed MEX input, or
numerical edge case has been exhaustively tested.

When reproducing historical behavior, use the documentation and source from the
specific release tag rather than treating all `v0.1.x` releases as one frozen
source line.
