function result = run(inputPath, outputPath, doAlias, doCenter, doOverwrite, options)
%RUN Alias correction and centering with optional preview/decision seam.
%   result = alias.api.run(inputPath, outputPath, doAlias, doCenter, doOverwrite)
%   result = alias.api.run(inputPath, outputPath, doAlias, doCenter, doOverwrite, options)
%
%   This function never creates UI. The source file is never modified.
%
%   Every accepted input type (file or directory) is passed through the
%   verified public dicom2nifti contract (dicom2nifti.api.run) via
%   alias.api.loadInput. SPM reads only the dependency-produced NIfTI.
%
%   This function snapshots and restores the full MATLAB path and CWD on
%   every return and exception path, including direct calls (not only
%   through the correct_aliasing facade).
%
%   Input:
%     inputPath   — path to any accepted input source (file or directory)
%     outputPath  — path for corrected output (NIfTI)
%     doAlias     — logical, perform alias correction
%     doCenter    — logical, perform centering
%     doOverwrite — logical, allow overwriting existing output
%     options     — (optional) struct with optional fields:
%       .previewFcn — function handle @(ctx) decision
%         ctx    — struct with fields:
%           originalVolData, originalAffine,
%           processedVolData, processedAffine,
%           engineResult, inputPath, outputPath
%         decision — char: 'accept', 'reject', or 'cancel'
%         If omitted or empty, the API writes without asking.
%         If provided, the API calls it exactly once after engine
%         execution. On 'reject' or 'cancel': cancelled, no write.
%         On 'accept': one staged write + safePromote.
%         If the callback throws or returns an invalid decision,
%         the result is 'failed' with diagnostics and no write.
%
%   Output:
%     result      — scalar struct with exactly four top-level fields:
%                   status, outputs, message, details

% -------------------------------------------------------------------------
% 0. Snapshot caller path/CWD — restored on every return and exception
% -------------------------------------------------------------------------
originalPath = path;
originalDir = pwd;
sessionCleanup = onCleanup(@() restoreSession(originalPath, originalDir));

rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
result = alias.result.create('failed');
% Preserve caller intent in operations switches on all exit paths
result.details.operations.AliasCorrection = doAlias;
result.details.operations.Centering = doCenter;

% --- Parse optional preview/decision seam ---
previewFcn = [];
if nargin >= 6 && ~isempty(options)
    if isstruct(options) && isfield(options, 'previewFcn')
        previewFcn = options.previewFcn;
    end
end

% --- Early validation (with path normalization) ---
if ~ischar(inputPath) || isempty(strtrim(inputPath))
    result.details.failure.identifier = 'alias:InvalidInputPath';
    result.details.failure.message = 'Input path must be a nonempty character vector.';
    result.message = 'Invalid input path.';
    return;
end
inputPath = absolutePath(strtrim(inputPath));
result.details.input_path = inputPath;

if ~ischar(outputPath) || isempty(strtrim(outputPath))
    result.details.failure.identifier = 'alias:InvalidOutputPath';
    result.details.failure.message = 'Output path must be a nonempty character vector.';
    result.message = 'Invalid output path.';
    return;
end
outputPath = absolutePath(strtrim(outputPath));
result.details.output_path = outputPath;

% Accept existing file OR directory — converter handles both uniformly
inputExistsAsFile = (exist(inputPath, 'file') == 2);
inputExistsAsDir  = (exist(inputPath, 'dir')  == 7);
if ~inputExistsAsFile && ~inputExistsAsDir
    result.details.failure.identifier = 'alias:InputNotFound';
    result.details.failure.message = sprintf('Input does not exist: %s', inputPath);
    result.message = 'Input not found.';
    return;
end

if alias.util.sameCanonicalPath(inputPath, outputPath)
    result.details.failure.identifier = 'alias:InputOutputSame';
    result.details.failure.message = 'Input and output are the same file. The source will not be modified.';
    result.message = 'Input and output must differ.';
    return;
end

if ~doOverwrite && exist(outputPath, 'file') == 2
    result.details.failure.identifier = 'alias:OutputExists';
    result.details.failure.message = sprintf( ...
        'Output already exists and Overwrite is false: %s', outputPath);
    result.message = 'Output exists and Overwrite is false.';
    return;
end

% --- Load and validate config (scoped, path/CWD-safe) ---
try
    config = alias.config.load();
    config = alias.config.validate(config);
catch ME
    result = populateFailure(result, ME);
    result.message = 'Configuration validation failed.';
    return;
end

% --- SPM preflight (leaves selected SPM + override on path) ---
try
    spmInfo = alias.spm.preflight(config);
catch ME
    result = populateFailure(result, ME);
    result.message = 'SPM preflight failed.';
    return;
end

provenance = alias.provenance.capture(spmInfo.spm_version, rootDir, spmInfo, config);
result.details.provenance = provenance;

% --- Convert input via the public dicom2nifti contract ---
convertCleanup = [];
converterResult = struct();
try
    [niiPath, convertCleanup, converterResult] = alias.api.loadInput(inputPath, config);
catch ME
    % Structural error (converter missing/shadowed) — loadInput threw
    result = populateFailure(result, ME);
    result.message = 'Input conversion failed.';
    if ~isempty(converterResult)
        result.details.converter = converterResult;
    end
    return;
end

% Preserve full converter diagnostics under details (transient path never in outputs)
result.details.converter_processing_path = niiPath;
result.details.converter = converterResult;

% Handle converter failed/cancelled — no output to process
if isfield(converterResult, 'status') && ...
   (strcmp(converterResult.status, 'failed') || strcmp(converterResult.status, 'cancelled'))
    clear convertCleanup;
    result.status = 'failed';
    result.details.failure.identifier = 'alias:ConverterFailed';
    if isfield(converterResult, 'message')
        result.details.failure.message = converterResult.message;
    else
        result.details.failure.message = sprintf('Converter returned status ''%s''.', converterResult.status);
    end
    % Preserve converter failure diagnostics (stack/cause) if available
    if isfield(converterResult, 'details') && isstruct(converterResult.details) && ...
       isfield(converterResult.details, 'failure') && isstruct(converterResult.details.failure)
        cf = converterResult.details.failure;
        if isfield(cf, 'stack'), result.details.failure.stack = cf.stack;
        else, result.details.failure.stack = struct('file',{},'name',{},'line',{}); end
        if isfield(cf, 'cause'), result.details.failure.cause = cf.cause;
        else, result.details.failure.cause = {}; end
    else
        result.details.failure.stack = struct('file',{},'name',{},'line',{});
        result.details.failure.cause = {};
    end
    result.message = 'Input conversion failed.';
    return;
end

% Handle converter partial — only proceed if output was actually produced
if isfield(converterResult, 'status') && strcmp(converterResult.status, 'partial')
    if isempty(niiPath)
        clear convertCleanup;
        result.status = 'failed';
        result.details.failure.identifier = 'alias:ConverterPartial';
        result.details.failure.message = 'Converter returned partial without producing output.';
        result.details.failure.stack = struct('file',{},'name',{},'line',{});
        result.details.failure.cause = {};
        result.message = 'Input conversion produced no usable output.';
        return;
    end
    % Partial with output: continue processing; final status may be partial
    % only after correction output is committed.
end

% --- SPM read the dependency-produced NIfTI ---
try
    V = spm_vol(niiPath);
    volData = spm_read_vols(V);
    affine = V.mat;
catch ME
    clear convertCleanup;
    result = populateFailure(result, ME);
    result.details.failure.identifier = 'alias:LoadFailed';
    result.message = 'Failed to load converted volume.';
    return;
end

% Release the converter temp workspace — data is in memory
clear convertCleanup;

if isempty(volData)
    result.details.failure.identifier = 'alias:LoadFailed';
    result.details.failure.message = 'Converted volume is empty.';
    result.message = 'Input loading failed.';
    return;
end

% --- Engine ---
ops = struct('AliasCorrection', doAlias, 'Centering', doCenter);
engResult = alias.core.engine(volData, affine, ops);

% --- Optional preview/decision seam ---
if ~isempty(previewFcn)
    ctx = struct();
    ctx.originalVolData = volData;
    ctx.originalAffine = affine;
    ctx.processedVolData = engResult.volData;
    ctx.processedAffine = engResult.affine;
    ctx.engineResult = engResult;
    ctx.inputPath = inputPath;
    ctx.outputPath = outputPath;

    decision = '';
    try
        decision = previewFcn(ctx);
    catch ME
        % Callback threw — produce structured failed result, no write
        result.status = 'failed';
        result = populateFailure(result, ME);
        result.details.failure.identifier = 'alias:PreviewCallbackFailed';
        result.message = 'Preview callback threw an exception.';
        result.details.input_path = inputPath;
        result.details.output_path = outputPath;
        result.details.operations.AliasCorrection = doAlias;
        result.details.operations.Centering = doCenter;
        return;
    end

    % Validate the decision: must be a char vector, one of accept/reject/cancel
    if ~ischar(decision) || isempty(decision) || ...
       ~(strcmp(decision, 'accept') || strcmp(decision, 'reject') || strcmp(decision, 'cancel'))
        result.status = 'failed';
        result.details.failure.identifier = 'alias:PreviewDecisionInvalid';
        if ischar(decision)
            result.details.failure.message = sprintf( ...
                'Preview callback returned unrecognized decision: ''%s''. Valid: accept, reject, cancel.', decision);
        else
            result.details.failure.message = sprintf( ...
                'Preview callback returned a non-char decision of class %s. Valid: accept, reject, cancel.', class(decision));
        end
        result.details.failure.stack = struct('file',{},'name',{},'line',{});
        result.details.failure.cause = {};
        result.message = 'Preview callback returned an invalid decision.';
        result.details.input_path = inputPath;
        result.details.output_path = outputPath;
        result.details.operations.AliasCorrection = doAlias;
        result.details.operations.Centering = doCenter;
        return;
    end

    if ~strcmp(decision, 'accept')
        % Operator rejected or cancelled — no write
        result.status = 'cancelled';
        if strcmp(decision, 'reject')
            result.message = 'Operator rejected the correction.';
        else
            result.message = 'Operator cancelled.';
        end
        result.details.input_path = inputPath;
        result.details.output_path = outputPath;
        result.details.operations.AliasCorrection = doAlias;
        result.details.operations.Centering = doCenter;
        return;
    end
end

% --- Write staged corrected output via SPM, then promote ---
tempOutput = [outputPath '.tmp_' generateToken() '.nii'];
try
    writeVolume(tempOutput, engResult.volData, engResult.affine, V);
    alias.util.safePromote(tempOutput, outputPath);
catch ME
    result = populateFailure(result, ME);
    result.details.failure.identifier = 'alias:WriteFailed';
    result.message = 'Output write failed.';
    if exist(tempOutput, 'file') == 2
        delete(tempOutput);
    end
    return;
end

% --- Build result (success or partial if upstream converter was partial) ---
upstreamPartial = isfield(converterResult, 'status') && strcmp(converterResult.status, 'partial');
if upstreamPartial
    result.status = 'partial';
    result.message = 'Correction completed from partial converter output.';
else
    result.status = 'success';
    result.message = 'Correction completed.';
end
result.details.input_path = inputPath;
result.details.output_path = outputPath;
result.details.changed = engResult.alias_corrected || engResult.centered;
result.outputs = {outputPath};

% operations: requested switches per spec
result.details.operations.AliasCorrection = doAlias;
result.details.operations.Centering = doCenter;

% Per-operation engine outcomes
result.details.alias_correction.performed = engResult.alias_corrected;
result.details.centering.performed = engResult.centered;

result.details.transform = struct( ...
    'applied', result.details.changed, ...
    'rotation', 0, ...
    'translation', max(abs(engResult.translation_mm), abs(engResult.shift_mm)), ...
    'scale', 1);

result.details.failure = struct('identifier', '', 'message', '', 'stack', '', 'cause', '');
end


function writeVolume(outputPath, volData, affine, hdr)
hdr.fname = outputPath;
hdr.mat = affine;
hdr = spm_create_vol(hdr);
spm_write_vol(hdr, volData);
end


function token = generateToken()
token = char(randi([97 122], 1, 8));
end


function pathValue = absolutePath(pathValue)
% Resolve to an absolute path. Bare names and relative paths (./ , ../ ,
% nested) become absolute via pwd. Already-absolute paths are unchanged.
if isempty(pathValue), return; end
if isunix && pathValue(1) == '~'
    pathValue = fullfile(getenv('HOME'), pathValue(2:end));
end
if isunix && pathValue(1) == '/'
    return;  % already absolute
end
if ispc && length(pathValue) >= 2 && pathValue(2) == ':'
    return;  % already absolute (drive letter)
end
pathValue = fullfile(pwd, pathValue);
end


function result = populateFailure(result, ME)
% Populate the full failure metadata from a caught MException.
%   Stack is preserved as a struct array with fields file/name/line.
%   Cause is preserved as a cell array of structs (recursive).
%   MException is an object — access .stack and .cause directly (no isfield).
result.details.failure.identifier = ME.identifier;
result.details.failure.message = ME.message;
% Stack: preserve as struct array with file/name/line
result.details.failure.stack = serializeStack(ME.stack);
% Cause: preserve as cell array of structs (recursive)
result.details.failure.cause = serializeCause(ME.cause);
end


function s = serializeStack(stackArr)
% Serialize an MException.stack array into a struct array with file/name/line.
if isempty(stackArr)
    s = struct('file', {}, 'name', {}, 'line', {});
else
    s = struct('file', {}, 'name', {}, 'line', {});
    for k = 1:numel(stackArr)
        s(k).file = stackArr(k).file;
        s(k).name = stackArr(k).name;
        s(k).line = stackArr(k).line;
    end
end
end


function c = serializeCause(causeArr)
% Serialize an MException.cause cell array into a cell array of structs.
%   Each struct has: identifier, message, stack, cause (recursive).
if isempty(causeArr)
    c = {};
else
    c = cell(1, numel(causeArr));
    for k = 1:numel(causeArr)
        s = struct();
        s.identifier = causeArr{k}.identifier;
        s.message = causeArr{k}.message;
        s.stack = serializeStack(causeArr{k}.stack);
        s.cause = serializeCause(causeArr{k}.cause);
        c{k} = s;
    end
end
end


function restoreSession(originalPath, originalDir)
path(originalPath);
if exist(originalDir, 'dir') == 7
    cd(originalDir);
end
end
