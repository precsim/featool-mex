# Known limitations of the frozen source

The `v0.1.x` release line intentionally preserves the complete `src/` directory
byte-for-byte from the original source import at commit
`e752f56bb6a122b75a0562f4085ab2840d2a6e8d`.

Build-system portability fixes may be made outside `src/`, but source-level
behavior is not changed in this release line. As a result, the published MEX
binaries inherit the original implementation's edge cases as well as its
intended behavior.

The limitations below were identified during later source review and testing.
They are documented here rather than applied to `v0.1.x` so that the source
freeze remains meaningful. This is not intended to be an exhaustive list of
all possible invalid-input behavior.

## Input validation and indexing

- `earrind` and `eindarr` perform limited validation of indices and related
  inputs. Later review added checks for out-of-range, non-integer, non-finite,
  and otherwise incompatible index data, as well as additional handling for
  empty and complex inputs. Callers of the frozen implementation should
  validate indices before invoking these MEX functions.
- `assemble_f` and `assemble_s` do not contain the later connectivity-index
  guards. Element connectivity supplied to the frozen implementation should be
  finite, integer-valued, in range, and consistent with the supplied arrays.
- `fsparse` does not contain the later guards for oversized indices and thread
  counts near the limits of the implementation's integer types.

## Sparse-matrix behavior

- `spsetd` retains its historical no-output, in-place mutation behavior. The
  `v0.1.x` smoke test deliberately exercises that original contract. Later
  hardening changed the interface to return a modified sparse matrix and
  rejected unsafe no-output mutation, complex sparse input, invalid rows, and
  rows without a usable diagonal entry. Code using `v0.1.x` should therefore
  treat `spsetd` as a legacy mutating operation and validate row selections.
- Later review of `findsp` added stricter handling of complex sparse input,
  output-count validation, empty sparse matrices, and index-output typing.
- Later review of `fsetop` addressed edge cases involving signed zero, empty
  rows and cells, and preservation of classes such as `single`, `char`, and
  `logical`.
- Later review of `fsparse` also improved behavior for complex full-array
  conversion and several boundary cases.

## ILU factorization

The frozen `iluk`, `iluk_Cmex`, and `iluk_Cmex_nosymb` implementations predate
later validation for several malformed or incompatible inputs. Subsequent
review added checks for input type, finite and representable fill levels,
missing or zero pivots, argument/output counts, and reuse of level structures
whose sparsity pattern does not match the matrix being factored.

For `v0.1.x`, callers should provide sparse double matrices with a compatible
sparsity pattern, valid diagonal pivots, and conservative nonnegative integer
fill levels.

## Assembly model restrictions and numerical correction

- The nonlinear `NeoHookean_*` and `RaghavanVorp_*` paths in `assemble_s` were
  later guarded as three-dimensional-only models. The frozen source does not
  enforce that restriction at the MEX boundary; do not use those model paths
  with two-dimensional input.
- Later review corrected density scaling in the `SUPG_SemiImplicit` path of
  `assemble_f`. That numerical correction is intentionally **not** present in
  the frozen `v0.1.x` source. Users relying on that formulation should account
  for this when evaluating results.

## Release scope

The GitHub Actions release pipeline verifies that the frozen source builds,
loads, and passes its baseline smoke tests on the documented MATLAB and GNU
Octave configurations. Those checks establish build/runtime compatibility;
they do not remove or supersede the source-level limitations listed above.

Source-level corrections should be introduced only in a future development
line that explicitly ends the `src/` freeze, rather than being mixed into
`v0.1.x`.
