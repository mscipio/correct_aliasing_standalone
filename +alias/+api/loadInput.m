function [niiPath, cleanup, converterResult] = loadInput(inputPath, config)
%LOADINPUT Convert any accepted input to an SPM-readable NIfTI via the
%   verified public dicom2nifti contract.
%   [niiPath, cleanup, converterResult] = alias.api.loadInput(inputPath, config)
%
%   Sends every input (.nii, .nii.gz, .dcm, .ima, folder, and any other
%   type the dependency accepts) through the structured public API
%   dicom2nifti.api.run, requesting uncompressed .nii output suitable
%   for SPM processing.
%
%   The adapter owns a temporary workspace that stays alive through the
%   caller's SPM read and is cleaned via the returned onCleanup handle.
%   Dependency-owned staging artifacts are never deleted by the adapter.
%
%   Input:
%     inputPath  — absolute path to any accepted input source (file or dir)
%     config     — validated config struct with .d2n_root, .d2n_entrypoint
%
%   Output:
%     niiPath    — absolute path to the dependency-produced uncompressed
%                  .nii file (alias-owned temp location), or '' if the
%                  converter returned failed/cancelled/partial without
%                  producing output.
%     cleanup    — onCleanup handle; keep alive through SPM read, then
%                  let it go out of scope (or clear) to clean the
%                  alias-owned temp workspace. Always returned (never [])
%                  so the caller can clear it on all paths.
%     converterResult — the full structured result from the converter
%                  (status, message, details, outputs). Empty struct if
%                  the converter threw before returning.
%
%   Throws:
%     alias:ConverterMissing    — converter not found on path
%     alias:ConverterShadowed   — converter entrypoint is shadowed

% Initialize outputs so they are always defined
niiPath = '';
converterResult = struct();

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
    % Converter threw — preserve what we can in the result
    converterResult = struct();
    converterResult.status = 'failed';
    converterResult.message = sprintf('Converter threw: %s — %s', ...
        ME.identifier, ME.message);
    converterResult.outputs = {};
    converterResult.details = struct();
    % restoreCleanup fires on return, restoring caller path/CWD.
    % cleanup survives — caller controls its lifetime.
    return;
end

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
