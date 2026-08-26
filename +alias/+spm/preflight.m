function info = preflight(config)
%PREFLIGHT Resolve SPM authority via core-5 marker inspection.
%   info = alias.spm.preflight(config)
%
%   Inspects the caller environment for 5 core processing markers and
%   selects the authoritative SPM installation. On success, the selected
%   SPM root and any conditional vers/spm_vol_nifti.m override REMAIN
%   on the MATLAB path for subsequent processing. The CALLER must restore
%   the original path and CWD via its own onCleanup guard.
%
%   On error, the path is restored before the exception is thrown.
%
%   Core-5 processing markers:
%     spm_vol, spm_read_vols, spm_create_vol, spm_write_vol, spm_type
%
%   spm_dicom_headers and spm_dicom_convert are NOT inspected here
%   — they belong to dcm2nii's own setupSpm boundary.
%
%   Resolution rules:
%     - All 5 core markers resolve to one root → authority='caller',
%       caller installation reused unchanged. Selected root is on path.
%     - Partial core marker set → alias:SpmIncomplete, fail closed,
%       path restored before exception.
%     - No core markers → authority='fallback', configured spm_root.
%       Fallback root is added to path.
%     - If selected SPM lacks spm_vol_nifti → conditionally add only
%       app-owned vers/spm_vol_nifti.m; never shadow a valid caller helper.
%     - Verify resolution and reject shadowing.
%
%   Input:
%     config  — struct with at least .spm_root (char)
%
%   Output:
%     info    — struct with fields:
%                 .spm_root           — resolved absolute SPM root path
%                 .spm_authority      — 'caller' or 'fallback'
%                 .spm_version        — detected SPM version string
%                 .spm_override_path  — vers/spm_vol_nifti.m path ('' if unused)
%
%   Throws (path restored before throw):
%     alias:SpmRootMissing  — spm_root empty or directory nonexistent
%     alias:SpmIncomplete   — partial core-5 marker set on caller path
%     alias:SpmShadowed     — selected SPM root has shadowed markers

% -------------------------------------------------------------------------
% 1. Snapshot state (for error recovery only)
% -------------------------------------------------------------------------
originalPath = path;
originalDir = pwd;

% -------------------------------------------------------------------------
% 2. Inspect caller path for core-5 processing markers
% -------------------------------------------------------------------------
coreMarkers = {'spm_vol', 'spm_read_vols', 'spm_create_vol', ...
               'spm_write_vol', 'spm_type'};

markerResolutions = cell(1, numel(coreMarkers));
for i = 1:numel(coreMarkers)
    w = which(coreMarkers{i});
    if ~isempty(w)
        markerResolutions{i} = w;
    else
        markerResolutions{i} = '';
    end
end

resolvedMarkers = markerResolutions(~cellfun('isempty', markerResolutions));
numResolved = numel(resolvedMarkers);

% -------------------------------------------------------------------------
% 3. Determine authority (path NOT restored on success)
% -------------------------------------------------------------------------
if numResolved == numel(coreMarkers)
    % --- All 5 core markers: verify single-root passthrough ---
    roots = cellfun(@fileparts, resolvedMarkers, 'UniformOutput', false);
    uniqueRoots = unique(roots);
    if numel(uniqueRoots) > 1
        doRestore(originalPath, originalDir);
        error('alias:SpmIncomplete', ...
            'Core-5 markers resolve to mixed roots. Found %d distinct roots.', ...
            numel(uniqueRoots));
    end
    selectedRoot = uniqueRoots{1};
    authority = 'caller';
    % Caller root is already on the path; add it at begin for shadowing guard
    addpath(selectedRoot, '-begin');

elseif numResolved > 0
    % --- Partial 1-4 markers: fail closed ---
    foundList = coreMarkers(~cellfun('isempty', markerResolutions));
    missingList = coreMarkers(cellfun('isempty', markerResolutions));
    doRestore(originalPath, originalDir);
    error('alias:SpmIncomplete', ...
        ['Partial core marker set detected. Found: %s. Missing: %s. ' ...
         'Fail closed; never mixing installations.'], ...
        strjoin(foundList, ', '), strjoin(missingList, ', '));

else
    % --- No core markers: validate and use configured fallback ---
    if ~isfield(config, 'spm_root') || ~ischar(config.spm_root) || isempty(config.spm_root)
        doRestore(originalPath, originalDir);
        error('alias:SpmRootMissing', ...
            'SPM root must be a nonempty character vector.');
    end
    if exist(config.spm_root, 'dir') ~= 7
        doRestore(originalPath, originalDir);
        error('alias:SpmRootMissing', ...
            'Configured SPM root does not exist: %s', config.spm_root);
    end
    selectedRoot = config.spm_root;
    authority = 'fallback';
    addpath(selectedRoot, '-begin');
end

% -------------------------------------------------------------------------
% 4. Verify selected root resolves its own core markers (shadowing guard)
% -------------------------------------------------------------------------
for i = 1:numel(coreMarkers)
    w = which(coreMarkers{i});
    if isempty(w)
        doRestore(originalPath, originalDir);
        error('alias:SpmShadowed', ...
            'Selected SPM root %s does not provide %s', ...
            selectedRoot, coreMarkers{i});
    end
    markerParent = fileparts(w);
    if ~alias.util.sameCanonicalPath(markerParent, selectedRoot)
        % Shadowed: w resolves from a different canonical root.
        % Check all copies to see if any lives under selectedRoot.
        allCopies = which(coreMarkers{i}, '-all');
        foundUnderRoot = false;
        for a = 1:numel(allCopies)
            if alias.util.sameCanonicalPath(fileparts(allCopies{a}), selectedRoot)
                foundUnderRoot = true;
                break;
            end
        end
        if ~foundUnderRoot
            doRestore(originalPath, originalDir);
            error('alias:SpmShadowed', ...
                'Selected SPM marker %s is shadowed and does not resolve under %s', ...
                coreMarkers{i}, selectedRoot);
        end
    end
end

% -------------------------------------------------------------------------
% 5. Conditionally add vers/spm_vol_nifti.m override
% -------------------------------------------------------------------------
overridePath = '';
w = which('spm_vol_nifti');
if isempty(w)
    % Selected SPM lacks spm_vol_nifti — add app-owned override
    standaloneRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    versDir = fullfile(standaloneRoot, 'vers');
    if exist(versDir, 'dir') == 7 && exist(fullfile(versDir, 'spm_vol_nifti.m'), 'file') == 2
        addpath(versDir, '-begin');
        wv = which('spm_vol_nifti');
        if isempty(wv)
            doRestore(originalPath, originalDir);
            error('alias:SpmShadowed', ...
                'App-owned vers/spm_vol_nifti.m does not resolve after path addition.');
        end
        overridePath = wv;
    end
else
    % Caller/fallback already has spm_vol_nifti — NEVER shadow it
    overridePath = '';
end

% -------------------------------------------------------------------------
% 6. Capture version provenance
% -------------------------------------------------------------------------
versionStr = discoverSpmVersion(selectedRoot);

% -------------------------------------------------------------------------
% 7. Build output — paths REMAIN active for processing scope
% -------------------------------------------------------------------------
info = struct();
info.spm_root = selectedRoot;
info.spm_authority = authority;
info.spm_version = versionStr;
info.spm_override_path = overridePath;
end


% =========================================================================
%  Private helpers
% =========================================================================

function doRestore(originalPath, originalDir)
% Restore path and CWD (called only on error paths).
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
