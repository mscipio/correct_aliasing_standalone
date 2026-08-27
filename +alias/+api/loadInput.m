function [niiPath, cleanup, converterResult] = loadInput(inputPath, config)
%LOADINPUT Convert any accepted input to an SPM-readable NIfTI.
%   [niiPath, cleanup, converterResult] = alias.api.loadInput(inputPath, config)
%
%   Conditional routing:
%     * If inputPath is an existing file whose final extension is exactly
%       '.nii' (case-insensitive), the adapter takes a pass-through path:
%       no alias_convert_* workspace is created, no converter is invoked,
%       and niiPath is the original inputPath. The source file is never
%       modified or deleted.
%     * Every other accepted input (.nii.gz, .dcm, .ima, folder, etc.) is
%       sent through the structured public API dicom2nifti.api.run,
%       requesting uncompressed .nii output suitable for SPM processing.
%
%   The adapter owns a temporary workspace (conversion path only) that
%   stays alive through the caller's SPM read and is cleaned via the
%   returned onCleanup handle. Dependency-owned staging artifacts are
%   never deleted by the adapter.
%
%   Input:
%     inputPath  — absolute path to any accepted input source (file or dir)
%     config     — validated config struct with .d2n_root, .d2n_entrypoint
%
%   Output:
%     niiPath    — absolute path to an uncompressed .nii file. For the
%                  pass-through branch this is inputPath itself; for the
%                  conversion branch this is the dependency-produced file
%                  in an alias-owned temp location, or '' if the converter
%                  returned failed/cancelled/partial without output.
%     cleanup    — onCleanup handle; keep alive through SPM read, then
%                  let it go out of scope (or clear) to clean the
%                  alias-owned temp workspace (conversion path) or to
%                  satisfy the nonempty-handle invariant (pass-through).
%                  Always returned (never []) so the caller can clear it
%                  on all paths.
%     converterResult — the full structured result from the converter
%                  (status, message, details, outputs). Always a
%                  structured result: when the converter throws, this
%                  is a failed result with full diagnostics (including
%                  details.failure.stack and details.failure.cause),
%                  never an empty struct. The details struct carries a
%                  converter_route tag: 'nifti-passthrough' for the
%                  pass-through branch, 'dicom2nifti-conversion' for the
%                  conversion branch.
%
%   Throws:
%     alias:ConverterMissing    — converter not found on path
%     alias:ConverterShadowed   — converter entrypoint is shadowed

% Initialize outputs so they are always defined
niiPath = '';
converterResult = struct();

% -------------------------------------------------------------------------
% 0. Pass-through: existing uncompressed .nii file used directly
%    Detect BEFORE any alias_convert_* mkdir, addpath, or converter call.
%    Match is case-insensitive and requires the final extension to be
%    exactly '.nii' — '.nii.gz', directories, substring matches, and
%    missing files must NOT take this branch.
% -------------------------------------------------------------------------
if isNiftiPassthrough(inputPath)
    niiPath = inputPath;
    converterResult = struct();
    converterResult.status  = 'success';
    converterResult.outputs = {inputPath};
    converterResult.message = 'NIfTI pass-through: existing uncompressed .nii used directly without conversion';
    converterResult.details = struct();
    converterResult.details.converter_route = 'nifti-passthrough';
    converterResult.details.input_path      = inputPath;
    % Nonempty no-op cleanup: does not delete or modify the source.
    cleanup = onCleanup(@() noopCleanup());
    return;
end

% -------------------------------------------------------------------------
% 1. Create alias-owned temporary workspace for the converter output
% -------------------------------------------------------------------------
token = char(randi([97 122], 1, 8));
tmpDir = fullfile(tempdir, ['alias_convert_' token]);
if exist(tmpDir, 'dir') == 7, rmdir(tmpDir, 's'); end
mkdir(tmpDir);
cleanup = onCleanup(@() rmdir(tmpDir, 's'));

stagedOutput = fullfile(tmpDir, 'converted.nii');

% -------------------------------------------------------------------------
% 2. Snapshot path/CWD, scope the dependency, restore on exit
% -------------------------------------------------------------------------
originalPath = path;
originalDir = pwd;
restoreCleanup = onCleanup(@() doRestore(originalPath, originalDir));

addpath(config.d2n_root, '-begin');

% -------------------------------------------------------------------------
% 3. Verify the structured API resolves under the configured root
%    (shadowing guard — same safeguard pattern as the legacy facade)
% -------------------------------------------------------------------------
apiResolved = which('dicom2nifti.api.run');
if isempty(apiResolved)
    error('alias:ConverterMissing', ...
        'dicom2nifti.api.run not found after adding d2n_root to path.');
end
apiParent = fileparts(fileparts(fileparts(apiResolved)));
if ~alias.util.sameCanonicalPath(apiParent, config.d2n_root)
    error('alias:ConverterShadowed', ...
        'dicom2nifti.api.run resolves outside the configured d2n_root.');
end

% Also verify the legacy facade resolves (config invariant)
entrypointResolved = which(config.d2n_entrypoint);
if ~isempty(entrypointResolved)
    entrypointParent = fileparts(entrypointResolved);
    if ~alias.util.sameCanonicalPath(entrypointParent, config.d2n_root)
        error('alias:ConverterShadowed', ...
            'Converter entrypoint ''%s'' is shadowed.', config.d2n_entrypoint);
    end
end

% -------------------------------------------------------------------------
% 4. Invoke the structured public API — uncompressed .nii for SPM
% -------------------------------------------------------------------------
try
    converterResult = dicom2nifti.api.run(inputPath, stagedOutput, ...
        'Compression', 'none', 'Overwrite', true);
catch ME
    % Converter threw — preserve full MException diagnostics in the result
    converterResult = struct();
    converterResult.status = 'failed';
    converterResult.message = sprintf('Converter threw: %s — %s', ...
        ME.identifier, ME.message);
    converterResult.outputs = {};
    converterResult.details = struct();
    converterResult.details.failure = struct();
    converterResult.details.failure.identifier = ME.identifier;
    converterResult.details.failure.message = ME.message;
    % Stack: preserve as struct array with file/name/line
    if ~isempty(ME.stack)
        st = struct('file', {}, 'name', {}, 'line', {});
        for k = 1:numel(ME.stack)
            st(k).file = ME.stack(k).file;
            st(k).name = ME.stack(k).name;
            st(k).line = ME.stack(k).line;
        end
        converterResult.details.failure.stack = st;
    else
        converterResult.details.failure.stack = struct('file',{},'name',{},'line',{});
    end
    % Cause: preserve as cell array of structs (recursive)
    if ~isempty(ME.cause)
        cc = cell(1, numel(ME.cause));
        for k = 1:numel(ME.cause)
            cc{k} = serializeCauseLocal(ME.cause{k});
        end
        converterResult.details.failure.cause = cc;
    else
        converterResult.details.failure.cause = {};
    end
    converterResult.details.converter_route = 'dicom2nifti-conversion';
    % restoreCleanup fires on return, restoring caller path/CWD.
    % cleanup survives — caller controls its lifetime.
    return;
end

% Tag the conversion route for non-pass-through inputs
if ~isfield(converterResult, 'details') || ~isstruct(converterResult.details)
    converterResult.details = struct();
end
converterResult.details.converter_route = 'dicom2nifti-conversion';

% -------------------------------------------------------------------------
% 5. Validate the structured result
% -------------------------------------------------------------------------
if ~isfield(converterResult, 'status')
    converterResult.status = 'failed';
    converterResult.message = 'Converter did not return a result with a status field.';
    % restoreCleanup fires on return, restoring caller path/CWD.
    return;
end

% For failed/cancelled: return empty niiPath, caller handles the status
if isequal(converterResult.status, 'failed') || ...
   isequal(converterResult.status, 'cancelled')
    % niiPath stays '' — caller checks converterResult.status
    % restoreCleanup fires on return, restoring caller path/CWD.
    return;
end

% For partial: check if output was actually produced
if isequal(converterResult.status, 'partial')
    if exist(stagedOutput, 'file') == 2
        niiPath = stagedOutput;
        % Caller may decide to use partial output or not
    end
    % restoreCleanup fires on return, restoring caller path/CWD.
    return;
end

% -------------------------------------------------------------------------
% 6. Verify the dependency-produced output exists (success case)
% -------------------------------------------------------------------------
if exist(stagedOutput, 'file') ~= 2
    converterResult.status = 'failed';
    if ~isfield(converterResult, 'message') || isempty(converterResult.message)
        converterResult.message = sprintf('Converter did not produce output at %s', stagedOutput);
    end
    % restoreCleanup fires on return, restoring caller path/CWD.
    return;
end

niiPath = stagedOutput;
% restoreCleanup fires on return, restoring caller path/CWD.
% cleanup survives — caller controls its lifetime.
end


function doRestore(originalPath, originalDir)
path(originalPath);
if exist(originalDir, 'dir') == 7
    cd(originalDir);
end
end


function s = serializeCauseLocal(ME)
% Serialize a single MException from a cause chain into a struct.
s = struct();
s.identifier = ME.identifier;
s.message = ME.message;
if ~isempty(ME.stack)
    st = struct('file', {}, 'name', {}, 'line', {});
    for k = 1:numel(ME.stack)
        st(k).file = ME.stack(k).file;
        st(k).name = ME.stack(k).name;
        st(k).line = ME.stack(k).line;
    end
    s.stack = st;
else
    s.stack = struct('file',{},'name',{},'line',{});
end
if ~isempty(ME.cause)
    cc = cell(1, numel(ME.cause));
    for k = 1:numel(ME.cause)
        cc{k} = serializeCauseLocal(ME.cause{k});
    end
    s.cause = cc;
else
    s.cause = {};
end
end


function tf = isNiftiPassthrough(p)
%ISNIFTIPASSTHROUGH True when p is an existing file with final extension
%   exactly '.nii' (case-insensitive). Returns false for directories,
%   missing files, '.nii.gz', and any path whose final extension is not
%   '.nii'.
tf = false;
if ~ischar(p) || isempty(p)
    return;
end
if exist(p, 'file') ~= 2
    return;
end
[~, ~, ext] = fileparts(p);
if isempty(ext)
    return;
end
tf = strcmpi(ext, '.nii');
end


function noopCleanup()
%NOOPCLEANUP Intentionally empty — used as the callback for the
%   pass-through onCleanup handle so the handle is nonempty but clearing
%   it does not delete or modify the source file.
end
