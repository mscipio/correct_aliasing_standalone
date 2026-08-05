function info = preflight(config)
%PREFLIGHT Validate SPM runtime and capture provenance.
%   info = alias.spm.preflight(config)
%
%   Validates the configured spm_root and confirms all required SPM functions
%   are available. Captures the SPM version string. On exit, the MATLAB path
%   and CWD are always restored to their pre-call state via onCleanup.
%   The caller is responsible for adding the validated SPM root to the path
%   for the duration of actual processing.
%
%   Input:
%     config  — struct with at least .spm_root (char) and .log_level (char)
%
%   Output:
%     info    — struct with .spm_root and .spm_version
%
%   Throws:
%     alias:SpmRootMissing  — spm_root empty or directory nonexistent
%     alias:SpmIncomplete   — required SPM functions missing

originalPath = path;
originalDir = pwd;
cleanup = onCleanup(@() doRestore(originalPath, originalDir));

% --- Validate spm_root ---
if ~isfield(config, 'spm_root') || ~ischar(config.spm_root) || isempty(config.spm_root)
    error('alias:SpmRootMissing', ...
        'SPM root must be a nonempty character vector.');
end
if exist(config.spm_root, 'dir') ~= 7
    error('alias:SpmRootMissing', ...
        'Configured SPM root does not exist: %s', config.spm_root);
end

% --- Scoped path addition (reverted by onCleanup) ---
addpath(config.spm_root, '-begin');

% --- Verify required SPM functions ---
required = {'spm_vol', 'spm_read_vols', 'spm_write_vol', ...
            'spm_dicom_headers', 'spm_dicom_convert'};
missing = {};
for i = 1:numel(required)
    w = which(required{i});
    if isempty(w)
        missing{end + 1} = required{i}; %#ok<AGROW>
    end
end
if ~isempty(missing)
    error('alias:SpmIncomplete', ...
        'SPM root %s does not contain: %s', ...
        config.spm_root, strjoin(missing, ', '));
end

% --- Capture SPM version ---
versionStr = discoverSpmVersion(config.spm_root);

% --- Build output ---
info = struct();
info.spm_root = config.spm_root;
info.spm_version = versionStr;
end

function doRestore(originalPath, originalDir)
% Restore path and CWD on scope exit.
path(originalPath);
if exist(originalDir, 'dir') == 7
    cd(originalDir);
end
end

function versionStr = discoverSpmVersion(spmRoot)
% Try to extract an SPM version string from the root directory.

contentsFile = fullfile(spmRoot, 'Contents.m');
if exist(contentsFile, 'file') == 2
    fid = fopen(contentsFile, 'r');
    firstLine = fgetl(fid);
    fclose(fid);
    if ischar(firstLine) && length(firstLine) > 2
        cleaned = strtrim(regexprep(firstLine, '^%+\s*', ''));
        if ~isempty(cleaned)
            versionStr = cleaned;
            return;
        end
    end
end

try
    verOutput = spm('Ver');
    if ischar(verOutput) && ~isempty(verOutput)
        versionStr = verOutput;
        return;
    end
catch
end

listing = dir(fullfile(spmRoot, 'spm_*.m'));
if ~isempty(listing)
    versionStr = sprintf('SPM (detected in %s)', spmRoot);
else
    versionStr = 'SPM (unknown version)';
end
end
