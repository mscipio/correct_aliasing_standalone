# Correct MR Aliasing — Standalone Application

Standalone MATLAB R2019+ application for MR alias correction and centering.
Uses SPM for NIfTI I/O with caller-owned authority and the `dicom2nifti_standalone`
v1.2.0 public structured API (`dicom2nifti.api.run`) as the sole input I/O boundary
for all supported source types. Not a wrapper around pseudoCT or legacy Aether.

## Architecture

One public facade (`correct_aliasing.m`) dispatches to:

- **Operator GUI** (`alias.gui.mainWindow`) — chooser presentation, preview
  rendering, and operator decisions. Delegates all processing to `alias.api.run`.
- **Explicit API** (`alias.api.run`) — non-interactive orchestration: conversion
  through `dicom2nifti.api.run`, SPM loading, engine execution, output writing
  via `alias.util.safePromote`, result construction, and cleanup.

The GUI never calls `alias.core.engine`, SPM read/write functions, the converter,
or the input adapter directly. Both modes return the identical four-field result
schema and restore caller path/CWD.

## Deployment Dependencies

| Dependency | Role | Configured Root |
|---|---|---|
| SPM (r6313 fallback) | NIfTI I/O and processing | `config/defaults.m` → `spm_root` |
| dicom2nifti_standalone v1.2.0 | Input conversion (all types) | `config/defaults.m` → `d2n_root` |

The deployer must edit `config/defaults.m` and verify both roots exist.

### Configuration Boundary

`alias.config.load` and `alias.config.validate` load `config/defaults.m` through
a scoped path/CWD-safe boundary and validate deployer-owned SPM and dicom2nifti
roots plus the fixed facade identity (`dcm2nii`) before any processing.

### SPM Authority (core-5 marker inspection)

At every invocation the application inspects the caller MATLAB path for
exactly **5 core processing markers**:

`spm_vol`, `spm_read_vols`, `spm_create_vol`, `spm_write_vol`, `spm_type`

| Caller state | Behavior |
|---|---|
| All 5 core markers resolve to one root | **Caller authority** — reused unchanged; no fallback added |
| Any subset (1–4 markers) | **`alias:SpmIncomplete`** — fail closed, never mix installations |
| No core markers | **Fallback** — configured `spm_root` (default `spm8-r6313`) |

### Override policy

The configured SPM fallback `spm8-r6313` does not ship `spm_vol_nifti.m`.
When the selected SPM (caller or fallback) lacks this function, the
application conditionally adds only `vers/spm_vol_nifti.m` — an app-owned
compatibility shim with documented provenance. It **never**:

- Shadows a valid caller `spm_vol_nifti`
- Modifies, writes into, or deploys into the installed SPM tree
- Persists on the MATLAB path after processing completes

### dicom2nifti Boundary

All accepted input types (`.nii`, `.nii.gz`, `.dcm`, `.ima`, folder) are routed
through the `dicom2nifti.api.run` public structured API. The adapter
(`alias.api.loadInput`):

- Invokes `dicom2nifti.api.run(inputPath, stagedOutput, 'Compression', 'none', 'Overwrite', true)`
- Consumes only the dependency-produced uncompressed NIfTI output
- Keeps an alias-owned staging workspace alive through SPM reading
- Cleans the staging workspace via `onCleanup` when processing completes
- Does not delete dependency-owned artifacts
- Does not expose transient converter paths through `result.outputs`

The standalone application **never** calls `spm_dicom_headers`, `spm_dicom_convert`,
or implements its own conversion/decompression. See `docs/dicom2nifti-public-contract.md`
for the verified dependency contract.

## Requirements

- MATLAB R2019 or newer
- SPM (configured in `config/defaults.m`; fallback is `spm8-r6313`)
- dicom2nifti_standalone v1.2.0 (configured in `config/defaults.m`)

## Setup

1. Edit `config/defaults.m` and set `spm_root`, `d2n_root` to your
   installation paths.
2. Add the `correct_aliasing_standalone/` root to your MATLAB path.

## Usage

### Operator GUI

```matlab
correct_aliasing()
```

Launches an interactive GUI with Java `JFileChooser` for file or folder
selection (the chooser accepts both files and directories; the converter
adapter handles folder inputs uniformly), preview display of proposed
corrections, and Accept/Reject/Cancel decisions. All processing is delegated
exactly once to `alias.api.run` through a preview/decision callback seam
(`previewFcn`). The API owns conversion, SPM loading, engine execution,
output writing, and cleanup; the GUI owns only chooser presentation, preview
rendering, and operator decisions.

**Decision and overwrite semantics**:
- Chooser Cancel, Reject, or decision-dialog Cancel → `cancelled`, no write.
- Refusal to authorize overwrite of an existing output → `failed`
  (`alias:OverwriteRefused`), no write.
- Accept → one staged write + atomic promotion via `alias.util.safePromote`.

### Explicit API (non-interactive)

```matlab
result = correct_aliasing(inputPath, outputPath, ...
    'AliasCorrection', true, 'Centering', true, 'Overwrite', false);
```

Explicit calls never create UI. The source file is never modified.

### Result Schema

Every public result is a scalar struct with exactly four top-level fields:

| Field | Type | Description |
|-------|------|-------------|
| `status` | char | `'success'`, `'partial'`, `'failed'`, `'cancelled'` |
| `outputs` | cell | Committed output paths (empty if unwritten) |
| `message` | char | Human-readable summary |
| `details` | struct | Rich diagnostics (see below) |

**Status policy**:
- `success` — correction output committed
- `partial` — accepted vocabulary but not emitted by current workflow unless a correction output was actually committed
- `failed` — processing/config/output refusal (overwrite refused, invalid input, converter error, etc.)
- `cancelled` — operator decision (Reject, Cancel, chooser cancellation)

**Details sub-fields** (rich diagnostics preserved under `details`):
- `input_path`, `output_path` — normalized paths
- `changed` — logical, whether any correction was applied
- `operations` — struct with `.AliasCorrection`, `.Centering` (requested switches)
- `alias_correction`, `centering` — structs with `.performed` (engine actual outcomes)
- `transform` — struct with `.applied`, `.rotation`, `.translation`, `.scale`
- `provenance` — struct with `.version`, `.matlab_release`, `.spm_version`, `.spm_authority`, `.spm_root`, `.spm_override_path`, `.d2n_root`, `.algorithm_id`, `.validation_status`
- `failure` — struct with `.identifier`, `.message`, `.stack`, `.cause` (empty on success)

## Input Types

All input types are routed through `dicom2nifti.api.run`:

- **NIfTI**: `.nii`, `.nii.gz` — converted to uncompressed `.nii` for processing
- **DICOM**: `.dcm`, `.DCM`, `.ima`, `.IMA` — converted via dicom2nifti
- **Folder** — series collection via dicom2nifti

See `docs/dicom2nifti-public-contract.md` for the full verified input contract.

## Safety Invariants

- **Source immutability**: input files are never modified
- **Committed-output-only**: `result.outputs` contains only paths that were successfully promoted
- **Overwrite/source/state safety**: overwrite refusal when `Overwrite=false` and output exists; canonical same-file guard; path/CWD restoration on all exits
- **Rollback-safe promotion**: output is written to a staging file then atomically promoted via `alias.util.safePromote`

## Provenance

The `details.provenance.spm_authority` field records `'caller'` or `'fallback'`.
The `details.provenance.spm_override_path` records `vers/spm_vol_nifti.m` only
when it was conditionally added. The `details.provenance.d2n_root` records the
configured converter root. `details.provenance.validation_status` is always
`'unvalidated'`. Parity and clinical suitability are NOT claimed.

## PseudoCT Handoff Contract

A future pseudoCT change may call the explicit API directly:

```matlab
result = correct_aliasing(inputPath, outputPath, ...
    'AliasCorrection', true, 'Centering', true, 'Overwrite', false);
```

The call MUST use explicit arguments (never GUI). The caller receives a
deterministic non-UI result. No Piano, pseudoCT, or Aether source changes are
made by this standalone slice.

## Testing

```matlab
runtests('tests')
```

Tests cover:
- **testEntrypoint**: facade GUI/API dispatch, identical four-field result shape, path/CWD restoration
- **testApi**: explicit no-UI behavior, overwrite refusal/approval, source preservation, status mapping, outputs, converter boundary integration, preview/decision seam (callback accept/reject/cancel/exception/invalid decision), path/CWD restoration, folder input
- **testConfig**: defaults load, invalid roots, SPM authority, d2n root, fixed facade identity, validation before processing
- **testEngine**: core numerical engine (alias detection, centering, identity pass-through)
- **testConverterBoundary**: all input types through dicom2nifti boundary, cleanup ownership, no transient outputs, source preservation, converter error diagnostics, path/CWD restoration, shadowing guard
- **testCanonicalPath**: symlink-equivalent paths, different files, slash normalization
- **testSafePromote**: rollback-safe output promotion (backup/restore)
- **testGui**: GUI delegation to API, no direct calls, preview/decision callback (accept/reject/cancel/exception/invalid), overwrite authorization vs refusal, folder input delegation, result schema, cancellation behavior
- **testResult**: exact four fields, status vocabulary (no `rejected`), details sub-fields, no shared state, failure metadata, provenance capture
- **testSpmPreflight**: core-5 caller passthrough, partial rejection, fallback selection, path/CWD restoration
- **testSpmOverride**: vers override behavior, never shadows valid caller helper

### Manual GUI Verification (MATLAB R2019+ Deployment Prerequisite)

The GUI Accept/Reject/Cancel decision flow relies on MATLAB `questdlg`,
which cannot be driven programmatically in R2019+ without Java robot
frameworks. Before any release, a human operator must verify on at
least one R2019+ installation:

1. Launch `correct_aliasing()` — JFileChooser opens.
2. Select a valid NIfTI input and a different output path.
3. Preview displays original and corrected axial MIPs.
4. Accept writes output, Reject writes nothing, Cancel writes nothing.
5. Selecting the same file as input and output shows an error dialog.

Callback-driven preview/decision tests use injected function handles to verify
accept, reject, cancel, exception, and invalid-decision paths without requiring
a live display.

## Fail-Closed Errors

| Error identifier | Trigger |
|-------|---------|
| `alias:SpmRootMissing` | `spm_root` empty or directory nonexistent |
| `alias:SpmIncomplete` | Partial core-5 markers on caller path |
| `alias:SpmShadowed` | Selected SPM markers shadowed or unresolvable |
| `alias:D2nRootMissing` | `d2n_root` empty or directory nonexistent |
| `alias:D2nEntrypointFixed` | `d2n_entrypoint` is not the fixed value `dcm2nii` |
| `alias:ConverterMissing` | `dicom2nifti.api.run` not found under `d2n_root` |
| `alias:ConverterFailed` | Converter threw an error |
| `alias:ConfigMissing` | `config/defaults.m` not found |
| `alias:ConfigInvalid` | Configuration missing required fields or non-scalar |
| `alias:InvalidArguments` | Malformed call to `correct_aliasing()` dispatcher |
| `alias:InvalidInputPath` | Input path empty or non-char |
| `alias:InvalidOutputPath` | Output path empty or non-char |
| `alias:InputNotFound` | Input file does not exist |
| `alias:InputOutputSame` | Input and output resolve to the same file |
| `alias:OutputExists` | Output exists and `Overwrite` is false |
| `alias:LoadFailed` | Input cannot be loaded after conversion |
| `alias:WriteFailed` | Output cannot be promoted atomically |
| `alias:PromoteFailed` | safePromote staging file missing or move failed |

## Limitations

- No batch, 4-D, or PET processing
- No DICOM output
- No clinical validation — output is **unvalidated**
- No Image Processing Toolbox dependency (gradient-based edge detection)
- SPM and dicom2nifti must be installed and configured by the deployer
- Dependency order: dicom2nifti → correct_aliasing → Piano (Piano not modified in this standalone slice)

## Version

`VERSION` is `0.1.0-dev`. This is a development release. No release tag has been created.
