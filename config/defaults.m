function c = defaults()
%DEFAULTS Deployer-owned configuration for correct_aliasing_standalone.
%   Edit this file to set the SPM and dcm2nii installation roots.
%
%   Fields:
%     spm_root        — absolute path to SPM installation directory
%                       (fallback used when no caller-owned core-5 markers)
%     d2n_root        — absolute path to dcm2nii standalone installation
%     d2n_entrypoint  — converter entrypoint function name (fixed)
%     log_level       — 'none' | 'info' | 'verbose'

c = struct();
c.spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/spm8-r6313';
c.d2n_root = '/usr/pubsw/packages/mrpet/standalone_apps/dcm2nii/dicom2nifti_standalone-latest';
c.d2n_entrypoint = 'dcm2nii';
c.log_level = 'info';
end
