function p = capture(spmVersion, projectRoot, spmInfo, config)
%CAPTURE Build a provenance struct capturing the execution environment.
%   p = alias.provenance.capture(spmVersion, projectRoot)
%   p = alias.provenance.capture(spmVersion, projectRoot, spmInfo, config)
%
%   Input:
%     spmVersion   — SPM version string (from alias.spm.preflight)
%     projectRoot  — absolute path to the standalone project root
%     spmInfo      — (optional) struct from alias.spm.preflight with
%                    .spm_authority, .spm_override_path
%     config       — (optional) deployer config struct with .d2n_root
%
%   Output:
%     p  — struct with version, matlab_release, spm_version,
%          spm_authority, spm_override_path, d2n_root,
%          algorithm_id, and validation_status

p = struct();

% Standalone version from VERSION file
versionFile = fullfile(projectRoot, 'VERSION');
if exist(versionFile, 'file') == 2
    fid = fopen(versionFile, 'r');
    verStr = strtrim(fgetl(fid));
    fclose(fid);
    p.version = verStr;
else
    p.version = 'unknown';
end

% MATLAB release
v = ver('MATLAB');
if ~isempty(v)
    p.matlab_release = v.Release;
else
    p.matlab_release = version();
end

% SPM version
p.spm_version = spmVersion;

% SPM authority, root, and override (from preflight)
if nargin >= 3 && isstruct(spmInfo)
    if isfield(spmInfo, 'spm_authority')
        p.spm_authority = spmInfo.spm_authority;
    else
        p.spm_authority = 'unknown';
    end
    if isfield(spmInfo, 'spm_root')
        p.spm_root = spmInfo.spm_root;
    else
        p.spm_root = '';
    end
    if isfield(spmInfo, 'spm_override_path') && ~isempty(spmInfo.spm_override_path)
        p.spm_override_path = spmInfo.spm_override_path;
    else
        p.spm_override_path = '';
    end
else
    p.spm_authority = 'unknown';
    p.spm_root = '';
    p.spm_override_path = '';
end

% d2n root (from config)
if nargin >= 4 && isstruct(config) && isfield(config, 'd2n_root')
    p.d2n_root = config.d2n_root;
else
    p.d2n_root = '';
end

% Algorithm identifier
p.algorithm_id = 'correct-aliasing-standalone/v1';

% Validation status (always 'unvalidated' until coordinated review)
p.validation_status = 'unvalidated';
end
