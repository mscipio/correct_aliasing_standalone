# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-08-27

### Conditional .nii Pass-Through and Provenance Routing

#### Added
- **Conditional .nii pass-through** in `+alias/+api/loadInput.m`: existing
  uncompressed `.nii` files are used directly without invoking
  `dicom2nifti.api.run`, without creating an `alias_convert_*` workspace, and
  with a no-op `onCleanup` handle. Detection is case-insensitive exact `.nii`
  extension; `.nii.gz`, directories, and substring matches are excluded.
  `isNiftiPassthrough` helper encapsulates the detection. The synthetic result
  carries `converter_route = 'nifti-passthrough'`.
- **Provenance `converter_route` field** in `+alias/+result/create.m` and
  propagation in `+alias/+api/run.m`: records whether the input took the
  `nifti-passthrough` or `dicom2nifti-conversion` route, surfaced under
  `result.details.provenance.converter_route`.

#### Changed
- `+alias/+api/run.m` now consumes both routes (passthrough and conversion),
  preserves `converter_processing_path`, propagates provenance, and clears both
  cleanup types on exit.
- `README.md` and `docs/dicom2nifti-public-contract.md` boundary documentation
  updated to reflect conditional routing.
- `docs/standard-plugin-structure-migration-plan.md` updated to reflect
  conditional boundary and 147/147 tests (was 141); current version references
  updated to `0.3.0`.

#### Fixed
- Source immutability preserved for both routes: passthrough returns the
  original input path without modification; conversion continues to leave the
  source file untouched. Clearing the passthrough `onCleanup` handle does not
  delete or alter the source file (no-op callback).
- Path/CWD restoration verified for both routes: passthrough and conversion
  paths both snapshot and restore caller `path` and `pwd` on every return and
  exception path.
- Converter failure diagnostics unchanged: converter throws still produce
  structured `failed` results with full `details.failure.stack` and
  `details.failure.cause`; the `converter_route` tag is set to
  `dicom2nifti-conversion` even on failure paths.
- `converter_route` provenance field defaults to `''` in `+alias/+result/create.m`
  and is populated per-call by `+alias/+api/run.m` from the converter result.

#### Safety Invariants Preserved
- Source immutability: input files never modified or deleted, for both
  passthrough and conversion routes.
- No-op `onCleanup` for passthrough: clearing the handle does not delete the
  source file; no `alias_convert_*` workspace is created.
- Path/CWD restoration on all exits (success and error), for both routes.
- Converter failure diagnostics: structured `failed` results with full stack
  and cause unchanged from 0.2.0.
- Committed-output-only: `result.outputs` populated only after successful
  promotion; transient converter staging paths not exposed.
- Overwrite refusal when `Overwrite=false` and output exists.
- Canonical same-file guard via `alias.util.sameCanonicalPath`.
- Rollback-safe promotion via `alias.util.safePromote`.
- SPM authority: core-5 marker inspection with fail-closed partial rejection.
- Conditional `vers/spm_vol_nifti.m` override never shadows valid caller helper.

#### Test Results
- Full suite: **147 passed, 0 failed** across 12 test classes (was 146 in
  0.2.0; 141 before 0.2.0 test additions).
- Tests verify `nifti-passthrough` vs `dicom2nifti-conversion` route
  distinction: `testConverterBoundary` split into `testNiiPassthrough` (direct
  path, no converter call, no `alias_convert_*` workspace, source bytes
  unchanged after clearing cleanup) and `testNonNiiInputsUseConverter` (.nii.gz,
  .dcm, .ima, folder all take conversion route).
- Case-insensitive `.nii` detection: `.NII` extension also takes passthrough
  route.
- No `alias_convert_*` workspace created for passthrough inputs.
- Route diagnostics propagated to `result.details.provenance.converter_route`
  for both success and failure paths.
- Path/CWD restoration explicitly verified for both passthrough (.nii) and
  conversion (.dcm) routes in `testConverterBoundary`.
- MATLAB R2019b+ compatibility preserved: no R2020+-only syntax; `onCleanup`,
  `string`, and `struct` usage compatible with R2019b.

## [0.2.0] - 2026-08-26

### Migration — Unified Plugin Structure

Migrated `correct_aliasing` to Piano's unified plugin structure (migration step 3).

#### Added
- `+alias/+config/load.m` and `+alias/+config/validate.m` — scoped path/CWD-safe
  configuration loading and validation before processing.
- `+alias/+util/sameCanonicalPath.m` — canonical path equivalence for same-file guard.
- `+alias/+util/safePromote.m` — rollback-safe output promotion (backup/restore).
- `docs/dicom2nifti-public-contract.md` — verified public contract for
  dicom2nifti_standalone v1.2.0 dependency.
- `CHANGELOG.md` — this file.
- Test suite organized around `testEntrypoint`, `testApi`, `testConfig`, `testEngine`,
  with focused `testSpmPreflight`, `testSpmOverride`, `testConverterBoundary`,
  `testCanonicalPath`, `testSafePromote`, `testGui`, `testResult`.

#### Changed
- **Public result schema**: all public results are now scalar structs with exactly
  four top-level fields: `{status, outputs, message, details}`. Rich diagnostics
  (transforms, operations, provenance, failure metadata) preserved under `details`.
- **Status vocabulary**: normalized to `success|partial|failed|cancelled`. Removed
  public `rejected` status. Operator Reject/Cancel → `cancelled`; processing/config
  refusal → `failed`.
- **Input I/O boundary**: all accepted input types (`.nii`, `.nii.gz`, `.dcm`,
  `.ima`, folder) now routed through `dicom2nifti.api.run` public structured API.
  Removed direct `spm_vol`/`spm_read_vols` reads of raw input, extension-based
  routing, and manual DICOM conversion.
- **GUI delegation**: `alias.gui.mainWindow` now delegates all processing to
  `alias.api.run` through a preview/decision callback seam (`previewFcn`). GUI
  no longer calls `alias.core.engine`, SPM I/O, converter, or input adapter
  directly. Chooser accepts files and directories for dependency-supported
  folder inputs.
- **API preview/decision seam**: `alias.api.run` accepts an optional
  `previewFcn` callback for GUI integration. Callback exceptions and invalid
  decisions produce structured `failed` results with full diagnostics.
- **API path/CWD restoration**: `alias.api.run` snapshots and restores caller
  path/CWD on every return and exception path, including direct calls.
- **API folder input**: `alias.api.run` accepts existing files or directories
  as converter inputs; the converter adapter handles both uniformly.
- **GUI overwrite semantics**: refusal to authorize overwrite returns `failed`
  (`alias:OverwriteRefused`); chooser cancel, Reject, and decision-dialog
  Cancel remain `cancelled`.
- **Root facade**: `correct_aliasing()` zero-arg mode returns `alias.gui.mainWindow()`
  result (not `[]`) when `nargout > 0`.
- **Output policy**: `result.outputs` contains only committed output paths.
  Transient converter staging paths are not exposed.
- **Cleanup ownership**: alias-owned staging workspace cleaned via `onCleanup`;
  dependency-owned artifacts not deleted by adapter.
- **SPM preflight**: fallback SPM-root existence is now conditional — complete
  caller core-5 authority is reused without requiring the configured fallback
  root to exist.
- **Provenance capture**: now records `spm_root`, `spm_override_path`, and
  `d2n_root` from preflight and config.
- **README.md**: updated to document unified facade/API/GUI contract, dicom2nifti
  boundary, minimal result schema, status policy, safety invariants.
- **Migration plan**: updated to reflect implemented/resolved state.

#### Fixed
- `testCanonicalPath.m` — added missing `setupOnce` to add project root to path.

#### Safety Invariants Preserved
- Source immutability: input files never modified.
- Committed-output-only: `result.outputs` populated only after successful promotion.
- Overwrite refusal when `Overwrite=false` and output exists.
- Canonical same-file guard via `alias.util.sameCanonicalPath`.
- Path/CWD restoration on all exits (success and error).
- Rollback-safe promotion via `alias.util.safePromote`.
- SPM authority: core-5 marker inspection with fail-closed partial rejection.
- Conditional `vers/spm_vol_nifti.m` override never shadows valid caller helper.

#### Test Results
- Full suite: **146 passed, 0 failed** (5 new tests added for structured
  stack/cause capture on converter, callback, SPM, and config throws, plus
  partial-with-usable-output commit path).
- Manual GUI display flow: **UNVERIFIED** (requires MATLAB R2019+ with Java display).
- Live end-to-end DICOM/NIfTI conversion with real data: **UNVERIFIED** (no real
  test fixtures available in this environment).

#### Not Changed
- `alias.core.engine` — pure numerical processing unchanged.
- Piano host — not modified in this standalone slice.
- Dependency order: dicom2nifti → correct_aliasing → Piano.
