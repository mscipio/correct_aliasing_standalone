function result = run(inputPath, outputPath, doAlias, doCenter, doOverwrite)
%RUN Non-interactive alias correction and centering.
%   result = alias.api.run(inputPath, outputPath, doAlias, doCenter, doOverwrite)
%
%   This function never creates UI. The source file is never modified.
%
%   Input:
%     inputPath   — path to NIfTI or DICOM file
%     outputPath  — path for corrected output (NIfTI)
%     doAlias     — logical, perform alias correction
%     doCenter    — logical, perform centering
%     doOverwrite — logical, allow overwriting existing output
%
%   Output:
%     result      — struct per the result schema

rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
result = alias.result.create('failed');
result.input = inputPath;
result.provenance = alias.provenance.capture('unknown', rootDir);

% --- Early validation ---
if ~ischar(inputPath) || isempty(strtrim(inputPath))
    result.error.identifier = 'alias:InvalidInputPath';
    result.error.message = 'Input path must be a nonempty character vector.';
    return;
end
inputPath = absolutePath(strtrim(inputPath));

if ~ischar(outputPath) || isempty(strtrim(outputPath))
    result.error.identifier = 'alias:InvalidOutputPath';
    result.error.message = 'Output path must be a nonempty character vector.';
    return;
end
outputPath = absolutePath(strtrim(outputPath));

if exist(inputPath, 'file') ~= 2
    result.error.identifier = 'alias:InputNotFound';
    result.error.message = sprintf('Input file does not exist: %s', inputPath);
    return;
end

if sameFile(inputPath, outputPath)
    result.error.identifier = 'alias:InputOutputSame';
    result.error.message = 'Input and output are the same file. The source will not be modified.';
    return;
end

if ~doOverwrite && exist(outputPath, 'file') == 2
    result.error.identifier = 'alias:OutputExists';
    result.error.message = sprintf( ...
        'Output already exists and Overwrite is false: %s', outputPath);
    return;
end

% --- SPM preflight ---
config = alias_config();
try
    spmInfo = alias.spm.preflight(config);
catch ME
    result.error.identifier = strrep(ME.identifier, 'alias:', 'alias:Spm');
    result.error.message = ME.message;
    return;
end

% Add SPM to path for processing
spmCleanup = onCleanup(@() path(path));

addpath(config.spm_root, '-begin');
result.provenance.spm_version = spmInfo.spm_version;

% --- Load input (NIfTI or DICOM) ---
[volData, affine, hdr] = loadInput(inputPath);
if isempty(volData)
    result.error.identifier = 'alias:LoadFailed';
    result.error.message = 'Failed to load input volume.';
    return;
end

% --- Engine ---
ops = struct('AliasCorrection', doAlias, 'Centering', doCenter);
engResult = alias.core.engine(volData, affine, ops);

% --- Write output ---
tempOutput = [outputPath '.tmp_' generateToken() '.nii'];
try
    writeVolume(tempOutput, engResult.volData, engResult.affine, hdr);
    % Atomic promotion
    if doOverwrite && exist(outputPath, 'file') == 2
        delete(outputPath);
    end
    [ok, msg] = movefile(tempOutput, outputPath, 'f');
    if ~ok
        result.error.identifier = 'alias:WriteFailed';
        result.error.message = sprintf('Could not promote output: %s', msg);
        return;
    end
catch ME
    result.error.identifier = 'alias:WriteFailed';
    result.error.message = ME.message;
    if exist(tempOutput, 'file') == 2
        delete(tempOutput);
    end
    return;
end

% --- Build success result ---
result.status = 'success';
result.output = outputPath;
result.changed = engResult.alias_corrected || engResult.centered;

if engResult.alias_corrected
    result.alias_correction.performed = true;
    result.alias_correction.translation_mm = engResult.translation_mm;
end
if engResult.centered
    result.centering.performed = true;
    result.centering.shift_mm = engResult.shift_mm;
end

result.transform = engResult.affine;
result.error = struct('identifier', '', 'message', '');
end


function [volData, affine, hdr] = loadInput(inputPath)
% Load input volume, routing NIfTI directly and DICOM through SPM conversion.
if isNiftiExt(inputPath)
    [volData, affine, hdr] = loadVolume(inputPath);
elseif isDicomExt(inputPath)
    [volData, affine, hdr] = loadDicom(inputPath);
else
    % Unknown type: try NIfTI first, then DICOM
    [volData, affine, hdr] = loadVolume(inputPath);
    if isempty(volData)
        [volData, affine, hdr] = loadDicom(inputPath);
    end
end
end


function [volData, affine, hdr] = loadVolume(inputPath)
% Load a NIfTI volume using SPM spm_vol/spm_read_vols.
try
    V = spm_vol(inputPath);
    volData = spm_read_vols(V);
    affine = V.mat;
    hdr = V;
catch ME
    warning('alias:LoadWarning', 'spm_vol failed for %s: %s', inputPath, ME.message);
    volData = [];
    affine = [];
    hdr = [];
end
end


function [volData, affine, hdr] = loadDicom(inputPath)
% Load a DICOM file using SPM spm_dicom_headers/spm_dicom_convert.
% Converts to temp NIfTI, then loads the result.
tmpDir = fullfile(tempdir, ['alias_dicom_' generateToken()]);
if exist(tmpDir, 'dir') == 7, rmdir(tmpDir, 's'); end
mkdir(tmpDir);
cleanup = onCleanup(@() rmdir(tmpDir, 's'));
outputDir = tmpDir;

try
    hdrs = spm_dicom_headers(inputPath);
    if isempty(hdrs)
        volData = []; affine = []; hdr = [];
        return;
    end
    out = spm_dicom_convert(hdrs, 'all', 'flat', 'nii', outputDir);
    % Find the produced NIfTI file
    listing = dir(fullfile(outputDir, '*.nii'));
    if isempty(listing)
        volData = []; affine = []; hdr = [];
        return;
    end
    convertedPath = fullfile(outputDir, listing(1).name);
    [volData, affine, hdr] = loadVolume(convertedPath);
catch ME
    warning('alias:DicomWarning', 'spm_dicom_convert failed: %s', ME.message);
    volData = [];
    affine = [];
    hdr = [];
end
end


function writeVolume(outputPath, volData, affine, hdr)
% Write a NIfTI volume using SPM with temp-staged atomic promote.
% The caller handles the staging and promotion to keep the API contract.
hdr.fname = outputPath;
hdr.mat = affine;
hdr = spm_create_vol(hdr);
spm_write_vol(hdr, volData);
end


function token = generateToken()
% Generate a short random token for temp file naming.
token = char(randi([97 122], 1, 8));  % 8 random lowercase letters
end


function pathValue = absolutePath(pathValue)
% Resolve relative paths to absolute.
if isempty(pathValue), return; end
if isunix && pathValue(1) == '~'
    pathValue = fullfile(getenv('HOME'), pathValue(2:end));
end
if isempty(fileparts(pathValue))
    pathValue = fullfile(pwd, pathValue);
end
end


function result = sameFile(first, second)
% Cross-platform same-file comparison.
if ispc
    result = strcmpi(first, second);
else
    result = strcmp(first, second);
end
end


function result = isNiftiExt(filePath)
% Check if file has a NIfTI extension (.nii or .nii.gz).
[~, ~, ext] = fileparts(filePath);
result = strcmpi(ext, '.nii');
if ~result && length(filePath) > 7
    result = strcmpi(filePath(end-6:end), '.nii.gz');
end
end


function result = isDicomExt(filePath)
% Check if file has a DICOM extension (.dcm or .ima).
[~, ~, ext] = fileparts(filePath);
result = any(strcmpi(ext, {'.dcm', '.ima'}));
end


function config = alias_config()
% Load deployer configuration for the standalone application.
% We resolve the path relative to +alias/+api/run.m location.
apiDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(apiDir));
configPath = fullfile(projectRoot, 'config', 'defaults.m');
if exist(configPath, 'file') == 2
    oldPath = path;
    restore = onCleanup(@() path(oldPath));
    configDir = fullfile(projectRoot, 'config');
    addpath(configDir, '-begin');
    config = defaults();
else
    config = struct('spm_root', '', 'log_level', 'info');
end
end
