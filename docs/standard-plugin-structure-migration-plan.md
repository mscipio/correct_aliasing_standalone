# correct_aliasing Standard Plugin Structure Migration Plan

correct_aliasing is migration step 3. Its current package is closest to the
target, but the working tree is active development at `0.3.0`; migration
builds on those bytes without conflating structural alignment with release
readiness.

## Status

**Migration implemented (T001–T008 complete).** All structural changes and
documentation reconciliation are in place. `VERSION` is `0.3.0`.

## Objective and Prerequisite

Align the existing facade, API, GUI, config, errors, and result with the minimal
shared contract after dicom2nifti publishes its stabilized compatibility
contract. Keep optional provenance and utility namespaces only where their
behavior remains useful.

**Prerequisite resolved:** dicom2nifti_standalone v1.2.0 public structured API
(`dicom2nifti.api.run`) verified and documented in `docs/dicom2nifti-public-contract.md`.

## Current-to-Target Mapping

| Current file or symbol | Target file or responsibility | Status |
|---|---|---|
| `correct_aliasing.m` | Remains the only public facade; return GUI and API results. | ✅ Done |
| `alias.api.run` | Retain as non-interactive orchestration; normalize its result. | ✅ Done |
| `alias.gui.mainWindow` | Retain interaction and preview; delegate accepted processing to `alias.api.run`. | ✅ Done |
| `alias.core.engine` | Retain plugin-specific, UI-free processing. | ✅ Unchanged |
| Direct `config/defaults.m` use and SPM checks | Add `alias.config.load` and `alias.config.validate`. | ✅ Done |
| `alias.spm.preflight` | Retain specialized SPM authority after common config validation. | ✅ Modified — fallback SPM-root existence now conditional for complete caller authority |
| `alias.result.create` | Simplify public result to four common fields; move current rich fields under `details`. | ✅ Done |
| `alias.provenance.capture` | Retain optionally under `details.provenance`; it is not mandatory shared schema. | ✅ Modified — now records `spm_root`, `spm_override_path`, `d2n_root` |
| `alias.util.sameCanonicalPath`, `safePromote` | Retain because canonical equivalence and rollback-safe promotion are substantive. | ✅ Unchanged |
| Existing tests | Reorganize required coverage around entrypoint, API, config, and core while retaining specialized GUI/SPM/promotion tests. | ✅ Done |

## Scope

In scope (all completed):

- ✅ Return the same minimal result from GUI and explicit facade modes.
- ✅ Align overwrite consent and normal processing outcomes across GUI and API.
- ✅ Move config loading and validation into `+alias/+config/`.
- ✅ Consume the stabilized dicom2nifti.api.run public structured API for inputs requiring conversion; existing uncompressed `.nii` files pass through directly (no converter call, `converter_route = 'nifti-passthrough'`).
- ✅ Add CHANGELOG and document migration status.
- ✅ API-scoped path/CWD restoration, folder input, conditional fallback SPM root,
  preview callback validation, full converter diagnostics.
- ✅ GUI folder selection, overwrite refusal → `failed`, cancellation → `cancelled`.
- ✅ Documentation reconciliation: all docs reflect implemented behavior.

Non-goals:

- No alias-correction algorithm rewrite.
- No removal of useful `+spm`, `+provenance`, or `+util` code merely to match a
  smaller diagram.
- No universal provenance schema or all-filesystem atomicity claim.
- No Piano changes in this repository.

## Phased Work Units (All Complete)

1. **Freeze current behavior:** ✅ characterized facade dispatch, rich result data,
   DICOM routing, overwrite behavior, state restoration, and safe promotion.
2. **Config boundary:** ✅ added `alias.config.load` and `validate`; pass validated
   config into SPM and dcm2nii resolution.
3. **Minimal result adapter:** ✅ mapped existing result information to `status`,
   `outputs`, `message`, and `details` without losing transforms, operation
   outcomes, failure diagnostics, or provenance.
4. **GUI delegation:** ✅ return `alias.gui.mainWindow` from `correct_aliasing()` and
   route accepted work through `alias.api.run` rather than duplicate processing.
5. **Behavior alignment:** ✅ GUI overwrite refusal → `failed`; chooser cancel,
   Reject, decision-dialog Cancel → `cancelled`. Folder input supported via
   dependency without local type routing.
6. **dicom2nifti adoption:** ✅ conditional boundary — existing uncompressed `.nii`
   files pass through directly (`converter_route = 'nifti-passthrough'`, no converter
   call, no `alias_convert_*` workspace, no-op cleanup); `.nii.gz`, DICOM, folder,
   and other supported inputs routed through `dicom2nifti.api.run` public structured
   API (`converter_route = 'dicom2nifti-conversion'`); adapter owns staging cleanup;
   no transient paths in outputs.
7. **API safety and result semantics:** ✅ API-scoped path/CWD restoration on all
   returns/exceptions; folder-or-file converter input; conditional fallback SPM
   root for complete caller authority; preview callback decision validation and
   exception-to-failed mapping; full converter diagnostics; partial-only-after-commit.
8. **Documentation reconciliation:** ✅ CHANGELOG, README, migration plan, and
    dependency contract updated to reflect implemented behavior. `VERSION` remains
    `0.3.0`.

## Compatibility Strategy

`correct_aliasing(inputPath, outputPath, options...)` accepted. Rich data preserved
under `result.details`; callers using fields such as `changed`, `transform`, or
`provenance` find them at `result.details.*`. GUI callers receive the same minimal
shape as explicit callers.

Only the documented `dicom2nifti.api.run` public structured API is used. No
converter internals are inspected or duplicated.

## Test and Evidence Plan (All Implemented)

- ✅ `testEntrypoint`: facade GUI/API dispatch and identical minimal shape.
- ✅ `testApi`: explicit no-UI behavior, overwrite refusal/approval, source
  preservation, status mapping, outputs, and cwd/path restoration.
- ✅ `testConfig`: defaults load, invalid roots, SPM authority, d2n root, and
  validation before processing.
- ✅ `testEngine`: retain numerical engine tests independently of SPM/UI.
- ✅ `testConverterBoundary`: all input types through dicom2nifti boundary,
  cleanup ownership, no transient outputs, source preservation, converter error
  diagnostics, path/CWD restoration, shadowing guard.
- ✅ Retained focused `testGui`, `testSpmPreflight`, `testSpmOverride`,
  `testCanonicalPath`, and `testSafePromote` coverage.
- ✅ Replaced source-pattern-only GUI claims with a mix of injected behavioral
  tests (callback accept/reject/cancel/exception/invalid, overwrite refusal vs
  approval, folder delegation, cancellation, no-write, schema) and source
  inspection (no direct engine/SPM/converter/input-adapter calls from GUI).
  Manual display verification (preview rendering, questdlg interaction) remains
  **UNVERIFIED** — requires MATLAB R2019+ with Java display.

Full suite: **147 passed, 0 failed**.

## Definition of Done (All Met)

- ✅ `correct_aliasing.m` is the only public entrypoint and returns a minimal
  result in both modes.
- ✅ GUI delegates processing to `alias.api.run`.
- ✅ Public statuses are `success|partial|failed|cancelled`; no public `rejected`.
- ✅ `outputs` contains only committed output paths; rich plugin data is in
  `details`.
- ✅ Config loading and validation live under `+alias/+config` and precede work.
- ✅ Explicit overwrite, input preservation, cwd/path restoration, and safe
  promotion remain tested. API-scoped path/CWD restoration on all paths.
- ✅ Preview callback validation: exceptions and invalid decisions produce
  structured `failed` results.
- ✅ README, CHANGELOG, migration plan, and dependency contract document the
    migration accurately. `VERSION` is `0.3.0`.

## Resolved Decisions

- **Status mapping:** operator Reject/Cancel/chooser cancellation → `cancelled`;
  processing/config/output refusal (including overwrite refusal) → `failed`.
  No public `rejected` status.
- **dicom2nifti integration:** conditional boundary — existing uncompressed `.nii`
  files pass through directly (`converter_route = 'nifti-passthrough'`); `.nii.gz`,
  DICOM, folder, and other supported inputs routed through `dicom2nifti.api.run`
  public structured API (`converter_route = 'dicom2nifti-conversion'`); adapter
  owns staging cleanup; no transient paths exposed.
- **API safety:** API-scoped path/CWD restoration on every return and exception;
  folder-or-file converter input; conditional fallback SPM root for complete
  caller core-5 authority; preview callback decision validation and
  exception-to-failed mapping; full converter diagnostics under `details`.
- **GUI overwrite:** refusal to authorize overwrite → `failed`
  (`alias:OverwriteRefused`); chooser cancel, Reject, decision-dialog Cancel →
  `cancelled`. Folder selection permitted without local type routing.

## Risks and Open Items

- Existing expected failures mostly return results while unexpected engine
  failures may throw; the boundary distinguishes normal processing from
  broken internal invariants.
- The repository is at `0.3.0`.

## Relevant Files and Symbols

- `correct_aliasing.m`.
- `+alias/+api/run.m`, `loadInput.m`.
- `+alias/+gui/mainWindow.m`.
- `+alias/+core/engine.m`.
- `+alias/+spm/preflight.m`.
- `+alias/+config/load.m`, `validate.m`.
- `+alias/+result/create.m`, `+alias/+provenance/capture.m`.
- `+alias/+util/sameCanonicalPath.m`, `safePromote.m`.
- `config/defaults.m`, `vers/spm_vol_nifti.m`.
- `tests/testEntrypoint.m`, `testApi.m`, `testConfig.m`, `testEngine.m`.
- `tests/testConverterBoundary.m`, `testCanonicalPath.m`, `testSafePromote.m`.
- `tests/testGui.m`, `testResult.m`, `testSpmPreflight.m`, `testSpmOverride.m`.
- `README.md`, `VERSION`, `CHANGELOG.md`.
- `docs/dicom2nifti-public-contract.md`.

## Cross-Repository Dependencies

Prerequisite: dicom2nifti_standalone v1.2.0 (resolved). Downstream
consumer: Piano's future explicit correct_aliasing adapter and UI capability.
Dependency order: dicom2nifti → correct_aliasing → Piano.
PseudoCT does not consume this standalone today; its internal anti-aliasing
option must not be silently redirected as part of this migration.
