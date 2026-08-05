# Correct MR Aliasing — Standalone Application

Standalone MATLAB R2019+ application for MR alias correction and centering.
Uses SPM for NIfTI/DICOM I/O and affine operations. Not a wrapper around
pseudoCT or legacy Aether.

## Requirements

- MATLAB R2019 or newer
- SPM12 (configured in `config/defaults.m`)

## Setup

1. Edit `config/defaults.m` and set `spm_root` to your SPM installation path.
2. Add the `correct_aliasing_standalone/` root to your MATLAB path.

## Usage

### Operator GUI

```matlab
correct_aliasing()
```

Launches an interactive GUI with Java `JFileChooser` for file selection,
preview display of proposed corrections, and Accept/Reject/Cancel decisions.
Matches the `dicom2nifti_standalone/dcm2nii.m` chooser pattern.

### Explicit API (non-interactive)

```matlab
result = correct_aliasing(inputPath, outputPath, ...
    'AliasCorrection', true, 'Centering', true, 'Overwrite', false);
```

Explicit calls never create UI. The source file is never modified.

### Result Schema

| Field | Type | Description |
|-------|------|-------------|
| `status` | char | `'success'`, `'failed'`, `'rejected'`, `'cancelled'` |
| `input` | char | Absolute input path (preserved) |
| `output` | char | Absolute output path (`''` if unwritten) |
| `changed` | logical | Whether any correction was applied |
| `alias_correction` | struct | `.performed`, `.detected_direction`, `.translation_mm` |
| `centering` | struct | `.performed`, `.shift_mm` |
| `transform` | 4×4 double | Updated affine matrix |
| `provenance` | struct | `.version`, `.matlab_release`, `.spm_version`, `.algorithm_id`, `.validation_status` |
| `error` | struct | `.identifier`, `.message` (empty on success) |

## Input Types

- **NIfTI**: `.nii`, `.nii.gz` — loaded directly via `spm_vol`/`spm_read_vols`
- **DICOM**: `.dcm`, `.DCM`, `.ima`, `.IMA` — converted via `spm_dicom_headers`/`spm_dicom_convert`

## Provenance

The `provenance.validation_status` field is always `'unvalidated'`. Parity and
clinical suitability are NOT claimed. The standalone application produces
adapted algorithmic output; numerical parity with legacy/pseudoCT requires
coordinated validation.

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

Tests cover: SPM preflight validation, result schemas, engine core (alias
detection, centering, identity pass-through, source preservation), explicit
API error paths, GUI callback verification, and DICOM routing logic.

## Limitations

- No batch, 4-D, or PET processing
- No DICOM output
- No clinical validation — output is **unvalidated**
- No Image Processing Toolbox dependency (gradient-based edge detection)
- SPM must be installed and configured by the deployer
