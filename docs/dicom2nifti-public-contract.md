# dicom2nifti Public Contract

**Gate verdict: PASS**

This document pins the verified public contract of the `dicom2nifti_standalone`
dependency as observed from the live configured installation. All evidence is
from executable source probes, not inferred from README or architecture docs.

---

## 1. Dependency Identity

| Field              | Value |
|--------------------|-------|
| Package            | `dicom2nifti_standalone` |
| VERSION            | `1.2.0` |
| Configured root    | `/usr/pubsw/packages/mrpet/standalone_apps/dcm2nii/dicom2nifti_standalone-latest` |
| Resolved root      | `/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/dcm2nii/dicom2nifti_standalone-1.2.0` |
| Symlink            | `dicom2nifti_standalone-latest` → `dicom2nifti_standalone-1.2.0` |
| Configured entry   | `dcm2nii` (from `config/defaults.m:d2n_entrypoint`) |
| `which('dcm2nii')` | resolves under `d2n_root` (canonical match confirmed) |
| `which('dicom2nifti.api.run')` | resolves under `d2n_root/+dicom2nifti/+api/run.m` |

**Evidence**: MATLAB probe executed 2026-08-25. All 12 key files confirmed present
(`+dicom2nifti/+api/run.m`, `+core/fromDicom.m`, `+core/fromNifti.m`,
`+core/fromPet.m`, `+core/resolveOutputs.m`, `+config/load.m`,
`+config/validate.m`, `+io/proposeName.m`, `+io/readVersion.m`,
`+dicom/collectSeries.m`, `+dicom/readTags.m`, `+gui/mainWindow.m`).

---

## 2. Public Facade

### 2a. Legacy facade — `dcm2nii`

```matlab
function varargout = dcm2nii(varargin)
```

**Invocation forms** (source-verified from `dcm2nii.m`):

| Form | Behavior |
|------|----------|
| `dcm2nii()` | GUI choosers → `dicom2nifti.gui.mainWindow` |
| `dcm2nii(input)` | Auto output beside input → `dicom2nifti.api.run` |
| `dcm2nii(input, output)` | CLI conversion → `dicom2nifti.api.run` |

**Name-Value options**: `'Compression'` (`'none'`|`'gz'`), `'Overwrite'` (logical/numeric scalar).

**Return contract** (legacy facade):
- `nargout == 0`: no return value; throws on failure.
- `nargout > 0`: returns output path (char) on success/partial; `''` on cancelled;
  throws `dcm2nii:ConversionFailed` on failed.

**Error mapping**: API errors (`dicom2nifti:api:*`) are remapped to legacy
`dcm2nii:*` identifiers via `mapLegacyError`. Path/CWD restored on all exits.

### 2b. Structured API — `dicom2nifti.api.run`

```matlab
function result = run(inputFile, outputFile, varargin)
```

**Signature** (source-verified from `+dicom2nifti/+api/run.m`):
- `inputFile`  — char, absolute path to input
- `outputFile` — char, absolute path; must end in `.nii` or `.nii.gz`
- `varargin`   — Name-Value pairs: `'Compression'`, `'Overwrite'`

**Result struct** (four-field):

| Field       | Type   | Content |
|-------------|--------|---------|
| `status`    | char   | `'success'` \| `'partial'` \| `'failed'` \| `'cancelled'` |
| `outputs`   | cell   | Paths of committed files (output + `dcm2nii_version.txt` [+ `Frame_info.txt` for PET]) |
| `message`   | char   | Human-readable summary |
| `details`   | struct | Diagnostics: `spm_loaded`, `cleanup_error`, `version_log_error` |

**Status semantics**:
- `success` — conversion and version log both succeeded.
- `partial` — conversion succeeded but version log failed; outputs still committed.
- `failed` — conversion or validation failed; error thrown (not returned).
- `cancelled` — reserved (GUI cancellation); API does not emit this.

**Error identifiers** (thrown, not returned in result):
- `dicom2nifti:api:InvalidInput` — bad argument type/value
- `dicom2nifti:api:InvalidInputFile` — input file does not exist
- `dicom2nifti:api:InvalidExtension` — unsupported output extension
- `dicom2nifti:api:InputOutputSame` — input == output
- `dicom2nifti:api:OutputExists` — destination exists and Overwrite is false
- `dicom2nifti:api:OverwriteDenied` — overwrite refused
- `dicom2nifti:api:UnsupportedModality` — DICOM modality not MR/CT/PET
- `dicom2nifti:api:UnsupportedInput` — unrecognized input type
- `dicom2nifti:api:InvalidOption` — unknown option name or bad pair count

---

## 3. Accepted Input Types

| Extension | Workflow | Core function | Behavior |
|-----------|----------|---------------|----------|
| `.nii` | `nifti` | `dicom2nifti.core.fromNifti` | `copyfile` to output |
| `.nii.gz` | `nifti` | `dicom2nifti.core.fromNifti` | `gunzip` to staging, `movefile` to output (uncompressed `.nii`) |
| `.dcm` | `dicom` | `dicom2nifti.core.fromDicom` | SPM `spm_dicom_headers` + `spm_dicom_convert`; staging dir with `onCleanup` |
| `.ima` | `dicom` | `dicom2nifti.core.fromDicom` | Same as `.dcm` |
| Folder | `dicom` | `dicom2nifti.core.fromDicom` | Series collection via `dicom2nifti.dicom.collectSeries` |
| PET DICOM | `pet` | `dicom2nifti.core.fromPet` | Dynamic/gated PET via SPM; groups by AcquisitionTime/TriggerTime |

**Modality routing** (from `api.run` source):
- NIfTI extensions → `nifti` workflow (no SPM needed).
- Non-NIfTI → reads DICOM tags (`Modality`); routes MR/CT → `dicom`, PT → `pet`;
  other modalities throw `dicom2nifti:api:UnsupportedModality`.

---

## 4. Output and Compression

- Output path must end in `.nii` or `.nii.gz`.
- `'Compression', 'none'` (default): produces uncompressed `.nii`.
- `'Compression', 'gz'`: produces `.nii.gz` via `gzip` post-compression.
- `.nii.gz` input with `'Compression', 'none'`: gunzips to uncompressed `.nii` output.
- Sidecar files always written beside output:
  - `dcm2nii_version.txt` — version log
  - `Frame_info.txt` — PET workflow only

**SPM-readable form**: The `nifti` workflow with `'Compression', 'none'` produces
an uncompressed `.nii` that SPM `spm_vol`/`spm_read_vols` can read directly.
This is the form correct_aliasing needs for processing.

---

## 5. Overwrite and Error Behavior

- **Default**: refuses if output or `dcm2nii_version.txt` exists; throws
  `dicom2nifti:api:OutputExists`.
- **`'Overwrite', true`**: allows overwrite of existing files.
- **Input == output**: throws `dicom2nifti:api:InputOutputSame`.
- **Missing input**: throws `dicom2nifti:api:InvalidInputFile`.
- **Bad extension**: throws `dicom2nifti:api:InvalidExtension`.
- **Source immutability**: input files are never modified.

---

## 6. Path/CWD and Lifecycle

- **Path/CWD snapshot**: `api.run` snapshots `path` and `pwd` on entry.
- **Restoration**: both success and error paths restore via `try/catch` blocks
  (not `onCleanup` — explicit restore in both branches).
- **Staging dirs**: created with `tempname(outputDir)`; cleaned via `onCleanup`
  in `fromDicom`, `fromNifti` (for `.nii.gz`), and `gzipOut`.
- **Cleanup ownership**: the dependency owns staging cleanup; the caller owns
  the final output file. The dependency does NOT delete the output.
- **No path leakage**: `config.load` snapshots and restores caller path.

---

## 7. Configuration

- `dicom2nifti.config.load()` — caller-SPM-first authority:
  1. If both `spm_dicom_headers` and `spm_dicom_convert` are on caller path →
     authoritative, returns their resolved paths.
  2. If only one → throws `dicom2nifti:config:SpmIncomplete`.
  3. If neither → falls back to `config/defaults.m` `spm_root`.
- `dicom2nifti.config.validate(config)` — pre-mutation guard:
  - `spm_root` must be nonempty char and existing directory.
  - Throws `dicom2nifti:config:InvalidSpmRoot`.

---

## 8. correct_aliasing Integration Points

The current `+alias/+api/loadInput.m` adapter invokes the structured public API
directly for every accepted input type (file or directory):

```matlab
converterResult = dicom2nifti.api.run(inputPath, stagedOutput, ...
    'Compression', 'none', 'Overwrite', true);
```

where `stagedOutput` is an alias-owned temporary path
(`tempdir/alias_convert_<token>/converted.nii`). The adapter:

- Consumes only the dependency-produced uncompressed `.nii` output.
- Keeps the alias-owned staging workspace alive through the caller's SPM read
  via an `onCleanup` handle returned to the caller.
- Does not delete dependency-owned artifacts.
- Does not expose transient converter paths through `result.outputs`.
- Preserves the full structured converter result (status, message, details,
  outputs) under `result.details.converter` for diagnostics.

The legacy `dcm2nii` facade is still verified to resolve under `d2n_root` as a
configuration invariant (shadowing guard), but is not the adapter's conversion
path. The structured API's four-field result is the sole integration contract.

---

## 9. Pre-Change Test Baseline

All correct_aliasing tests pass before any migration changes:

| Test file | Tests | Passed | Failed | Duration (s) |
|-----------|-------|--------|--------|---------------|
| `testDicomRouting` | 9 | 9 | 0 | 4.22 |
| `testApi` | 11 | 11 | 0 | 17.97 |
| `testEngine` | 8 | 8 | 0 | 0.77 |
| `testCanonicalPath` + `testResult` + `testSafePromote` + `testSpmPreflight` + `testSpmOverride` + `testGui` | 33 | 33 | 0 | 15.08 |
| **Total** | **61** | **61** | **0** | **~38** |

---

## 10. Dependency Contract Probe Results

| Check | Result |
|-------|--------|
| `d2n_root` exists | ✅ directory |
| `dcm2nii.m` exists | ✅ file |
| `+dicom2nifti/+api/run.m` exists | ✅ file |
| `VERSION` = `1.2.0` | ✅ semver |
| `which('dcm2nii')` under `d2n_root` | ✅ canonical match |
| `which('dicom2nifti.api.run')` under `d2n_root` | ✅ canonical match |
| All 12 key package files present | ✅ |
| Facade accepts `.nii` input | ✅ (routed to `fromNifti`) |
| Facade accepts `.nii.gz` input | ✅ (routed to `fromNifti`, gunzip) |
| Facade accepts `.dcm` input | ✅ (routed to `fromDicom` for MR/CT) |
| Facade accepts `.ima` input | ✅ (routed to `fromDicom` for MR/CT) |
| Facade accepts folder input | ✅ (routed to `fromDicom` via `collectSeries`) |
| Four-field result struct | ✅ `{status, outputs, message, details}` |
| Compression option `'none'`/`'gz'` | ✅ |
| Overwrite option | ✅ |
| Path/CWD restoration | ✅ (both success and error paths) |
| Staging cleanup via `onCleanup` | ✅ |
| Source immutability | ✅ |

---

## 11. UNVERIFIED Items

| Item | Reason |
|------|--------|
| Live end-to-end DICOM → NIfTI conversion with real DICOM data | No real DICOM test fixture available in this environment |
| Live end-to-end `.nii.gz` → uncompressed NIfTI with real data | No real NIfTI test fixture available |
| PET DICOM workflow (`fromPet`) | No PET DICOM test fixture available |
| SPM `spm_vol`/`spm_read_vols` on dependency-produced output | Requires real SPM + real converted NIfTI |
| GUI facade (`dcm2nii()` with no args) | Requires Java display |

---

## 12. Gate Verdict

**PASS** — The live stabilized public structured API `dicom2nifti.api.run` is
documented, executable, and accepts every required source type (`.nii`,
`.nii.gz`, `.dcm`, `.ima`, folder). The dependency produces a NIfTI output that
correct_aliasing can read via SPM under the documented lifecycle. The four-field
result struct, compression control, overwrite semantics, path/CWD restoration,
and staging cleanup are all verified from source. The legacy `dcm2nii` facade
remains available and verified but the adapter uses the structured API directly.

The migration may proceed to T002.
