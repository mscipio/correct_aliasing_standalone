function p = capture(spmVersion, projectRoot)
%CAPTURE Build a provenance struct capturing the execution environment.
%   p = alias.provenance.capture(spmVersion, projectRoot)
%
%   Input:
%     spmVersion   — SPM version string (from alias.spm.preflight)
%     projectRoot  — absolute path to the standalone project root
%
%   Output:
%     p  — struct with version, matlab_release, spm_version,
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

% Algorithm identifier
p.algorithm_id = 'correct-aliasing-standalone/v1';

% Validation status (always 'unvalidated' until coordinated review)
p.validation_status = 'unvalidated';
end
