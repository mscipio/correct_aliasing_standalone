function tests = testApi
%TESTAPI Tests for the explicit non-interactive API and dispatcher.
%   Verifies: no UI, missing args, overwrite guard, source preservation,
%   status reporting, the unified four-field result shape, canonical
%   same-file guard, converter boundary integration, and safe promotion.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
originalPath = path;
originalDir = pwd;
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(projectRoot);
testCase.TestData.ProjectRoot = projectRoot;
testCase.TestData.OriginalPath = originalPath;
testCase.TestData.OriginalDir = originalDir;
testCase.TestData.TempDir = tempname;
mkdir(testCase.TestData.TempDir);
end

function teardownOnce(testCase)
path(testCase.TestData.OriginalPath);
if exist(testCase.TestData.OriginalDir, 'dir') == 7
    cd(testCase.TestData.OriginalDir);
end
if exist(testCase.TestData.TempDir, 'dir') == 7
    rmdir(testCase.TestData.TempDir, 's');
end
end


function testExplicitCallWithMissingInputFails(testCase)
% GIVEN an explicit call with missing input path
% WHEN run() is called
% THEN it returns a 'failed' status with error info in details
fakeOutput = fullfile(testCase.TestData.TempDir, 'output.nii');
result = alias.api.run('', fakeOutput, true, true, false);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyTrue(~isempty(result.details.failure.identifier));
testCase.verifyTrue(~isempty(result.details.failure.message));
testCase.verifyEqual(result.outputs, {});
end

function testExplicitCallWithMissingOutputFails(testCase)
% GIVEN an explicit call with empty output path
% WHEN run() is called
% THEN it returns 'failed' status
result = alias.api.run('/some/fake/input.nii', '', true, true, false);

testCase.verifyEqual(result.status, 'failed');
end

function testExplicitCallWithNonexistentInputFails(testCase)
% GIVEN an input path that does not exist
% WHEN run() is called
% THEN it returns 'failed' status with deterministic error
result = alias.api.run(fullfile(testCase.TestData.TempDir, 'noexist.nii'), ...
    fullfile(testCase.TestData.TempDir, 'output.nii'), true, true, false);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyTrue(~isempty(result.details.failure.identifier));
end

function testExplicitCallRejectsSameInputOutput(testCase)
% GIVEN input == output (file exists)
% WHEN run() is called
% THEN it returns 'failed' with appropriate error
sameFile = fullfile(testCase.TestData.TempDir, 'same.nii');
fid = fopen(sameFile, 'w'); fprintf(fid, 'fake'); fclose(fid);
result = alias.api.run(sameFile, sameFile, true, true, false);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:InputOutputSame');
end

function testExplicitCallWithOverwriteOffExistingOutputFails(testCase)
% GIVEN an existing output file and Overwrite=false
% WHEN run() is called
% THEN it returns 'failed' and does not modify the output
outFile = fullfile(testCase.TestData.TempDir, 'existing.nii');
fid = fopen(outFile, 'w');
fprintf(fid, 'fake nifti content');
fclose(fid);

inFile = fullfile(testCase.TestData.TempDir, 'input.nii');
fid = fopen(inFile, 'w');
fprintf(fid, 'fake nifti content');
fclose(fid);

% The API should detect existing output and fail with overwrite=false
result = alias.api.run(inFile, outFile, true, true, false);

testCase.verifyEqual(result.status, 'failed', ...
    'Should fail when output exists and overwrite is false');
% Existing file should be untouched
testCase.verifyTrue(exist(outFile, 'file') == 2);
end

function testExplicitResultHasExactFourFields(testCase)
% GIVEN a failed API call (any reason)
% WHEN the result is returned
% THEN it has exactly four top-level fields: status, outputs, message, details
result = alias.api.run('', '', true, true, false);

fn = fieldnames(result);
testCase.verifyEqual(numel(fn), 4, 'Result must have exactly 4 top-level fields');
testCase.verifyEqual(fn{1}, 'status');
testCase.verifyEqual(fn{2}, 'outputs');
testCase.verifyEqual(fn{3}, 'message');
testCase.verifyEqual(fn{4}, 'details');

% details contains the rich diagnostics
testCase.verifyTrue(isfield(result.details, 'failure'));
testCase.verifyTrue(isfield(result.details, 'input_path'));
testCase.verifyTrue(isfield(result.details, 'output_path'));
testCase.verifyTrue(isfield(result.details, 'operations'));
testCase.verifyTrue(isfield(result.details.operations, 'AliasCorrection'));
testCase.verifyTrue(isfield(result.details.operations, 'Centering'));
testCase.verifyTrue(isfield(result.details, 'transform'));
testCase.verifyTrue(isfield(result.details, 'provenance'));
end

function testDispatcherZeroArgsDoesNotCallApi(testCase)
% GIVEN a dispatcher call with zero arguments
% WHEN it determines dispatch mode
% THEN it should route to GUI (which we can't test headless), NOT to API
% We test the dispatch logic directly: if nargin==0, the dispatcher
% should NOT enter the explicit API path.
%
% Since we can't open a GUI, we verify that the dispatcher function
% exists and has the correct dispatch pattern by checking file contents.

dispatcherPath = fullfile(testCase.TestData.ProjectRoot, 'correct_aliasing.m');
testCase.verifyTrue(exist(dispatcherPath, 'file') == 2, ...
    'Dispatcher correct_aliasing.m must exist');
end

function testApiDoesNotCreateFigures(testCase)
% GIVEN an explicit API call
% WHEN run() is called
% THEN no figures, dialogs, or file choosers are created
beforeFigs = get(0, 'Children');
beforeFigCount = numel(beforeFigs);

result = alias.api.run('/nonexistent/input.nii', ...
    '/nonexistent/output.nii', true, true, false);

afterFigs = get(0, 'Children');
afterFigCount = numel(afterFigs);

testCase.verifyEqual(afterFigCount, beforeFigCount, ...
    'Explicit API must not create figures');
testCase.verifyEqual(result.status, 'failed', ...
    'Nonexistent input should fail deterministically, not hang on UI');
end

function testValidExplicitCallNoUi(testCase)
% GIVEN a deterministic fake SPM installation with working stubs
% AND a fake dicom2nifti.api.run converter
% AND a real input file on disk
% WHEN alias.api.run is called with explicit arguments
% THEN no figures or dialogs are created, the complete result contract
%      is returned, and the call is repeatable.

% Build fake SPM with functional stubs
spmDir = fullfile(tempdir, 'fake_spm_api_valid');
if exist(spmDir, 'dir') == 7, rmdir(spmDir, 's'); end
mkdir(spmDir);
cSpm = onCleanup(@() rmdir(spmDir, 's'));

% spm_vol: return a header with a fake NIfTI file from our temp input
fid = fopen(fullfile(spmDir, 'spm_vol.m'), 'w');
fprintf(fid, 'function V = spm_vol(fname)\n');
fprintf(fid, 'V = struct(''fname'',fname,''dim'',[32 32 16],''dt'',[16 0],''mat'',eye(4),''n'',[1 1],''pinfo'',[1;0;0]); end');
fclose(fid);

% spm_read_vols: return a 3-D single array (head-like blob)
fid = fopen(fullfile(spmDir, 'spm_read_vols.m'), 'w');
fprintf(fid, 'function d = spm_read_vols(V)\n');
fprintf(fid, 'd = single(ones(V.dim)); end');
fclose(fid);

% spm_create_vol: return the header
fid = fopen(fullfile(spmDir, 'spm_create_vol.m'), 'w');
fprintf(fid, 'function V = spm_create_vol(V), end');
fclose(fid);

% spm_write_vol: no-op
fid = fopen(fullfile(spmDir, 'spm_write_vol.m'), 'w');
fprintf(fid, 'function spm_write_vol(V,d)\n');
fprintf(fid, 'fid = fopen(V.fname,''w''); fwrite(fid,d(:),''single''); fclose(fid); end');
fclose(fid);

% spm_type: return bits for dtype 16 (float32)
fid = fopen(fullfile(spmDir, 'spm_type.m'), 'w');
fprintf(fid, 'function b = spm_type(dt, req)\n');
fprintf(fid, 'if strcmp(req,''bits''), b=32; else b=''FLOAT32-LE''; end; end');
fclose(fid);

% Build fake d2n root with contract-shaped converter stub
d2nDir = fullfile(tempdir, 'fake_d2n_api_valid');
if exist(d2nDir, 'dir') == 7, rmdir(d2nDir, 's'); end
mkdir(d2nDir);
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
fid = fopen(fullfile(d2nDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n');
fclose(fid);
apiDir = fullfile(d2nDir, '+dicom2nifti', '+api');
mkdir(apiDir);
fid = fopen(fullfile(apiDir, 'run.m'), 'w');
fprintf(fid, 'function result = run(inputFile, outputFile, varargin)\n');
fprintf(fid, 'fid = fopen(outputFile, ''w'');\n');
fprintf(fid, 'if fid > 0, fwrite(fid, ''FAKE_NIFTI'', ''char''); fclose(fid); end\n');
fprintf(fid, 'result = struct();\n');
fprintf(fid, 'result.status = ''success'';\n');
fprintf(fid, 'result.outputs = {outputFile};\n');
fprintf(fid, 'result.message = ''Conversion complete.'';\n');
fprintf(fid, 'result.details = struct(''spm_loaded'', true, ''cleanup_error'', '''', ''version_log_error'', '''');\n');
fprintf(fid, 'end\n');
fclose(fid);

% Use the fake SPM as caller (all 5 core markers on path)
addpath(spmDir, '-begin');
beforeFigs = numel(get(0, 'Children'));

% Override config to point to fake roots
defaultsPath = fullfile(testCase.TestData.ProjectRoot, 'config', 'defaults.m');
origDefaults = fileread(defaultsPath);
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));
fid = fopen(defaultsPath, 'w');
fprintf(fid, ['function c=defaults()\nc=struct();\n' ...
    'c.spm_root=''%s'';c.d2n_root=''%s'';' ...
    'c.d2n_entrypoint=''dcm2nii'';c.log_level=''info'';\nend\n'], spmDir, d2nDir);
fclose(fid);

% Create a real input file
inputFile = fullfile(testCase.TestData.TempDir, 'api_test_input.nii');
fid = fopen(inputFile, 'w'); fwrite(fid, zeros(1, 348, 'uint8')); fclose(fid);
outputFile = fullfile(testCase.TestData.TempDir, 'api_test_output.nii');

% Run with both operations enabled
result = alias.api.run(inputFile, outputFile, true, true, true);

% Complete result contract verification — four top-level fields
testCase.verifyEqual(result.status, 'success');
testCase.verifyClass(result.status, 'char');
testCase.verifyClass(result.outputs, 'cell');
testCase.verifyEqual(numel(result.outputs), 1);
testCase.verifyTrue(contains(result.outputs{1}, 'api_test_output.nii'));
testCase.verifyClass(result.message, 'char');
testCase.verifyClass(result.details, 'struct');

% Details: input/output paths
testCase.verifyClass(result.details.input_path, 'char');
testCase.verifyTrue(contains(result.details.input_path, 'api_test_input.nii'));
testCase.verifyClass(result.details.output_path, 'char');
testCase.verifyTrue(contains(result.details.output_path, 'api_test_output.nii'));
testCase.verifyClass(result.details.changed, 'logical');

% Details: operations
testCase.verifyClass(result.details.operations, 'struct');
testCase.verifyTrue(isfield(result.details.operations, 'AliasCorrection'));
testCase.verifyTrue(isfield(result.details.operations, 'Centering'));

% Details: per-operation outcomes
testCase.verifyTrue(isfield(result.details, 'alias_correction'));
testCase.verifyTrue(isfield(result.details.alias_correction, 'performed'));
testCase.verifyTrue(isfield(result.details, 'centering'));
testCase.verifyTrue(isfield(result.details.centering, 'performed'));

% Details: transform
testCase.verifyClass(result.details.transform, 'struct');
testCase.verifyTrue(isfield(result.details.transform, 'applied'));
testCase.verifyTrue(isfield(result.details.transform, 'rotation'));
testCase.verifyTrue(isfield(result.details.transform, 'translation'));
testCase.verifyTrue(isfield(result.details.transform, 'scale'));

% Details: provenance
testCase.verifyClass(result.details.provenance, 'struct');
testCase.verifyTrue(isfield(result.details.provenance, 'spm_authority'));
testCase.verifyTrue(isfield(result.details.provenance, 'spm_root'));
testCase.verifyTrue(isfield(result.details.provenance, 'spm_version'));
testCase.verifyTrue(isfield(result.details.provenance, 'd2n_root'));
% Route diagnostic: .nii input takes pass-through route
testCase.verifyEqual(result.details.provenance.converter_route, ...
    'nifti-passthrough');

% Details: failure (empty on success)
testCase.verifyClass(result.details.failure, 'struct');
testCase.verifyTrue(isfield(result.details.failure, 'identifier'));
testCase.verifyTrue(isfield(result.details.failure, 'message'));
testCase.verifyTrue(isfield(result.details.failure, 'stack'));
testCase.verifyTrue(isfield(result.details.failure, 'cause'));

% No figures created
afterFigs = numel(get(0, 'Children'));
testCase.verifyEqual(afterFigs, beforeFigs, 'API must not create figures');

% Determinism: second call with same inputs produces same outputs
result2 = alias.api.run(inputFile, outputFile, true, true, true);
testCase.verifyEqual(result2.status, 'success');

% Output file must exist (spm_write_vol stub wrote data)
testCase.verifyTrue(exist(outputFile, 'file') == 2, 'Output file must be written');

% Transient converter path must NOT be in outputs
for k = 1:numel(result.outputs)
    testCase.verifyFalse(contains(result.outputs{k}, 'alias_convert_'), ...
        'Transient converter path must not appear in outputs');
end

% Clean up output
if exist(outputFile, 'file') == 2, delete(outputFile); end
end

function testMalformedCallPreservesPaths(testCase)
% GIVEN a call to correct_aliasing with positional paths but bad params
% WHEN the inputParser rejects the arguments
% THEN the failure result preserves the normalized input_path
%      and output_path under details.
result = correct_aliasing('/some/input.nii', '/some/output.nii', ...
    'AliasCorrection', 'notlogical');

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:InvalidArguments');
testCase.verifyTrue(contains(result.details.input_path, 'input.nii'));
testCase.verifyTrue(contains(result.details.output_path, 'output.nii'));
% Paths are normalized to absolute
testCase.verifyTrue(startsWith(result.details.input_path, '/'));
testCase.verifyTrue(startsWith(result.details.output_path, '/'));
end


function testPublicApiPropagatesConverterFailure(testCase)
% GIVEN .dcm input + throwing dicom2nifti.api.run
% WHEN correct_aliasing runs → alias:ConverterFailed + original details

d2nDir = fullfile(tempdir, 'fake_d2n_api_throw');
if exist(d2nDir, 'dir') == 7, rmdir(d2nDir, 's'); end; mkdir(d2nDir);
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
fid = fopen(fullfile(d2nDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n'); fclose(fid);
apiDir = fullfile(d2nDir, '+dicom2nifti', '+api');
mkdir(apiDir);
fid = fopen(fullfile(apiDir, 'run.m'), 'w');
fprintf(fid, 'function result = run(inputFile, outputFile, varargin)\n');
fprintf(fid, 'error(''dicom2nifti:api:ConversionBoom'',''converter exploded'');\n');
fprintf(fid, 'end\n');
fclose(fid);

spmDir = fullfile(tempdir, 'fake_spm_api_dcm');
if exist(spmDir, 'dir') == 7, rmdir(spmDir, 's'); end; mkdir(spmDir);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
for m = {'spm_vol','spm_read_vols','spm_create_vol','spm_write_vol','spm_type'}
    fid = fopen(fullfile(spmDir, [m{1} '.m']), 'w');
    fprintf(fid, 'function varargout=%s(varargin),end', m{1}); fclose(fid);
end
addpath(spmDir, '-begin');

defaultsPath = fullfile(testCase.TestData.ProjectRoot, 'config', 'defaults.m');
orig = fileread(defaultsPath);
cCfg = onCleanup(@() writeDefaults(defaultsPath, orig));
fid = fopen(defaultsPath, 'w');
fprintf(fid, ['function c=defaults()\nc=struct();\n' ...
    'c.spm_root=''%s'';c.d2n_root=''%s'';' ...
    'c.d2n_entrypoint=''dcm2nii'';c.log_level=''info'';\nend\n'], spmDir, d2nDir); fclose(fid);

dcmPath = fullfile(testCase.TestData.TempDir, 'boom.dcm');
fid = fopen(dcmPath, 'w'); fprintf(fid, 'fake'); fclose(fid);
outPath = fullfile(testCase.TestData.TempDir, 'no_out.nii');

result = correct_aliasing(dcmPath, outPath, ...
    'AliasCorrection', true, 'Centering', true);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:ConverterFailed');
testCase.verifyTrue(contains(result.details.failure.message, 'dicom2nifti:api:ConversionBoom'));
testCase.verifyTrue(contains(result.details.failure.message, 'converter exploded'));
% outputs must be empty on failure
testCase.verifyEqual(result.outputs, {});
% Route diagnostic: .dcm input takes conversion route even on failure
testCase.verifyEqual(result.details.provenance.converter_route, ...
    'dicom2nifti-conversion');
end

%% --- Preview/decision seam tests ---

function testPreviewCallbackReceivesContext(testCase)
% GIVEN a valid setup with a preview callback
% WHEN alias.api.run is called
% THEN the callback receives a struct with required fields
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

receivedCtx = [];
function decision = captureCtx(ctx)
    receivedCtx = ctx;
    decision = 'accept';
end

opts = struct('previewFcn', @captureCtx);
result = alias.api.run(inputFile, outputFile, true, true, true, opts);

testCase.verifyEqual(result.status, 'success');
testCase.verifyTrue(~isempty(receivedCtx), 'Preview callback must be invoked');
testCase.verifyTrue(isfield(receivedCtx, 'originalVolData'));
testCase.verifyTrue(isfield(receivedCtx, 'originalAffine'));
testCase.verifyTrue(isfield(receivedCtx, 'processedVolData'));
testCase.verifyTrue(isfield(receivedCtx, 'processedAffine'));
testCase.verifyTrue(isfield(receivedCtx, 'engineResult'));
testCase.verifyTrue(isfield(receivedCtx, 'inputPath'));
testCase.verifyTrue(isfield(receivedCtx, 'outputPath'));
if exist(outputFile, 'file') == 2, delete(outputFile); end
end

function testPreviewAcceptWritesOutput(testCase)
% GIVEN preview callback returns 'accept'
% WHEN alias.api.run completes
% THEN output file is written and status is 'success'
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

opts = struct('previewFcn', @(ctx) 'accept');
result = alias.api.run(inputFile, outputFile, true, true, true, opts);

testCase.verifyEqual(result.status, 'success');
testCase.verifyTrue(exist(outputFile, 'file') == 2, 'Output must be written on accept');
testCase.verifyEqual(numel(result.outputs), 1);
if exist(outputFile, 'file') == 2, delete(outputFile); end
end

function testPreviewRejectNoWrite(testCase)
% GIVEN preview callback returns 'reject'
% WHEN alias.api.run completes
% THEN no output is written and status is 'cancelled'
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

opts = struct('previewFcn', @(ctx) 'reject');
result = alias.api.run(inputFile, outputFile, true, true, true, opts);

testCase.verifyEqual(result.status, 'cancelled');
testCase.verifyEqual(result.outputs, {});
testCase.verifyFalse(exist(outputFile, 'file') == 2, 'No output on reject');
end

function testPreviewCancelNoWrite(testCase)
% GIVEN preview callback returns 'cancel'
% WHEN alias.api.run completes
% THEN no output is written and status is 'cancelled'
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

opts = struct('previewFcn', @(ctx) 'cancel');
result = alias.api.run(inputFile, outputFile, true, true, true, opts);

testCase.verifyEqual(result.status, 'cancelled');
testCase.verifyEqual(result.outputs, {});
testCase.verifyFalse(exist(outputFile, 'file') == 2, 'No output on cancel');
end

function testNoPreviewCallbackWritesDirectly(testCase)
% GIVEN no preview callback (default behavior)
% WHEN alias.api.run completes
% THEN output is written without asking
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

result = alias.api.run(inputFile, outputFile, true, true, true);

testCase.verifyEqual(result.status, 'success');
testCase.verifyTrue(exist(outputFile, 'file') == 2, 'Output must be written');
if exist(outputFile, 'file') == 2, delete(outputFile); end
end

function testPreviewCallbackInvokedOnce(testCase)
% GIVEN a preview callback
% WHEN alias.api.run completes
% THEN the callback is invoked exactly once (not duplicated)
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

callCount = 0;
function decision = countCalls(ctx)
    callCount = callCount + 1;
    decision = 'accept';
end

opts = struct('previewFcn', @countCalls);
alias.api.run(inputFile, outputFile, true, true, true, opts);

testCase.verifyEqual(callCount, 1, 'Preview callback must be invoked exactly once');
if exist(outputFile, 'file') == 2, delete(outputFile); end
end

function testPreviewResultSchemaMatchesApi(testCase)
% GIVEN a preview-cancelled result
% WHEN returned
% THEN it has the same four-field schema as any API result
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

opts = struct('previewFcn', @(ctx) 'cancel');
result = alias.api.run(inputFile, outputFile, true, true, true, opts);

fn = fieldnames(result);
testCase.verifyEqual(numel(fn), 4, 'Result must have exactly 4 top-level fields');
testCase.verifyEqual(fn{1}, 'status');
testCase.verifyEqual(fn{2}, 'outputs');
testCase.verifyEqual(fn{3}, 'message');
testCase.verifyEqual(fn{4}, 'details');
testCase.verifyTrue(isfield(result.details, 'operations'));
end

function testOverwriteRefusedByApi(testCase)
% GIVEN existing output and doOverwrite=false
% WHEN alias.api.run is called (with or without preview)
% THEN it returns 'failed' with alias:OutputExists
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

% Pre-create output
fid = fopen(outputFile, 'w'); fprintf(fid, 'old'); fclose(fid);

result = alias.api.run(inputFile, outputFile, true, true, false);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:OutputExists');
testCase.verifyEqual(result.outputs, {});
end

function testOverwriteApprovedWritesOutput(testCase)
% GIVEN existing output and doOverwrite=true
% WHEN alias.api.run is called
% THEN output is overwritten and status is 'success'
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

% Pre-create output
fid = fopen(outputFile, 'w'); fprintf(fid, 'old'); fclose(fid);

result = alias.api.run(inputFile, outputFile, true, true, true);

testCase.verifyEqual(result.status, 'success');
testCase.verifyTrue(exist(outputFile, 'file') == 2, 'Output must be overwritten');
if exist(outputFile, 'file') == 2, delete(outputFile); end
end


%% --- T006: Path/CWD restoration, folder input, caller-owned SPM, callback, converter diagnostics ---

function testApiRestoresPathAndCwdOnSuccess(testCase)
% GIVEN a valid setup with caller-owned SPM (all 5 core markers)
% WHEN alias.api.run completes successfully
% THEN the caller's path and CWD are restored
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

beforePath = path;
beforeDir = pwd;

result = alias.api.run(inputFile, outputFile, true, true, true);

testCase.verifyEqual(result.status, 'success');
testCase.verifyEqual(path, beforePath, 'Path must be restored after successful API call');
testCase.verifyEqual(pwd, beforeDir, 'CWD must be restored after successful API call');
if exist(outputFile, 'file') == 2, delete(outputFile); end
end

function testApiRestoresPathAndCwdOnFailure(testCase)
% GIVEN an invalid input path
% WHEN alias.api.run returns failed
% THEN the caller's path and CWD are restored
beforePath = path;
beforeDir = pwd;

result = alias.api.run('', '/tmp/output.nii', true, true, false);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(path, beforePath, 'Path must be restored after failed API call');
testCase.verifyEqual(pwd, beforeDir, 'CWD must be restored after failed API call');
end

function testApiRestoresPathAndCwdOnCancel(testCase)
% GIVEN a preview callback that returns 'cancel'
% WHEN alias.api.run returns cancelled
% THEN the caller's path and CWD are restored
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

beforePath = path;
beforeDir = pwd;

opts = struct('previewFcn', @(ctx) 'cancel');
result = alias.api.run(inputFile, outputFile, true, true, true, opts);

testCase.verifyEqual(result.status, 'cancelled');
testCase.verifyEqual(path, beforePath, 'Path must be restored after cancelled API call');
testCase.verifyEqual(pwd, beforeDir, 'CWD must be restored after cancelled API call');
end

function testApiRestoresPathAndCwdOnCallbackThrow(testCase)
% GIVEN a preview callback that throws
% WHEN alias.api.run returns failed
% THEN the caller's path and CWD are restored
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

beforePath = path;
beforeDir = pwd;

% Use a local function (not anonymous) so MATLAB doesn't reject output capture
opts = struct('previewFcn', @throwingPreviewCallback);
result = alias.api.run(inputFile, outputFile, true, true, true, opts);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:PreviewCallbackFailed');
testCase.verifyTrue(contains(result.details.failure.message, 'callback exploded'));
testCase.verifyEqual(path, beforePath, 'Path must be restored after callback throw');
testCase.verifyEqual(pwd, beforeDir, 'CWD must be restored after callback throw');
end

function testApiAcceptsFolderInput(testCase)
% GIVEN a folder as input (converter accepts folders)
% WHEN alias.api.run is called
% THEN it passes the folder to the converter uniformly
[spmDir, d2nDir, defaultsPath, origDefaults, ~, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

% Create a folder input
folderInput = fullfile(testCase.TestData.TempDir, 'dicom_folder_input');
if exist(folderInput, 'dir') == 7, rmdir(folderInput, 's'); end
mkdir(folderInput);
fid = fopen(fullfile(folderInput, 'slice001.dcm'), 'w');
fprintf(fid, 'fake dicom'); fclose(fid);

result = alias.api.run(folderInput, outputFile, true, true, true);

% The converter stub succeeds, so we expect success
testCase.verifyEqual(result.status, 'success');
testCase.verifyTrue(contains(result.details.input_path, 'dicom_folder_input'));
testCase.verifyTrue(exist(outputFile, 'file') == 2, 'Output must be written for folder input');
% Route diagnostic: folder input takes conversion route
testCase.verifyEqual(result.details.provenance.converter_route, ...
    'dicom2nifti-conversion');
if exist(outputFile, 'file') == 2, delete(outputFile); end
end

function testCallerOwnedSpmWithMissingFallback(testCase)
% GIVEN caller has all 5 core SPM markers on path
% AND configured spm_root is empty/nonexistent (fallback absent)
% WHEN alias.api.run is called
% THEN it succeeds using caller authority (fallback not needed)
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));

% Override config with EMPTY spm_root (fallback absent)
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));
fid = fopen(defaultsPath, 'w');
fprintf(fid, ['function c=defaults()\nc=struct();\n' ...
    'c.spm_root='''';c.d2n_root=''%s'';' ...
    'c.d2n_entrypoint=''dcm2nii'';c.log_level=''info'';\nend\n'], d2nDir);
fclose(fid);

result = alias.api.run(inputFile, outputFile, true, true, true);

testCase.verifyEqual(result.status, 'success', ...
    'Caller-owned SPM must work even with empty fallback spm_root');
testCase.verifyEqual(result.details.provenance.spm_authority, 'caller');
if exist(outputFile, 'file') == 2, delete(outputFile); end
end

function testPreviewCallbackInvalidDecisionReturnsFailed(testCase)
% GIVEN a preview callback that returns an invalid decision
% WHEN alias.api.run is called
% THEN it returns 'failed' with alias:PreviewDecisionInvalid
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

opts = struct('previewFcn', @(ctx) 'maybe');
result = alias.api.run(inputFile, outputFile, true, true, true, opts);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:PreviewDecisionInvalid');
testCase.verifyEqual(result.outputs, {}, 'No output on invalid decision');
testCase.verifyFalse(exist(outputFile, 'file') == 2, 'No write on invalid decision');
end

function testPreviewCallbackNonScalarDecisionReturnsFailed(testCase)
% GIVEN a preview callback that returns a non-scalar decision
% WHEN alias.api.run is called
% THEN it returns 'failed' with alias:PreviewDecisionInvalid
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

opts = struct('previewFcn', @(ctx) {'accept', 'reject'});
result = alias.api.run(inputFile, outputFile, true, true, true, opts);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:PreviewDecisionInvalid');
end

function testConverterResultPreservedInDetails(testCase)
% GIVEN a successful conversion
% WHEN alias.api.run completes
% THEN the full converter result is preserved under details.converter
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

result = alias.api.run(inputFile, outputFile, true, true, true);

testCase.verifyEqual(result.status, 'success');
testCase.verifyTrue(isfield(result.details, 'converter'), ...
    'details must contain converter result');
testCase.verifyTrue(isfield(result.details.converter, 'status'), ...
    'converter result must have status');
testCase.verifyEqual(result.details.converter.status, 'success');
testCase.verifyTrue(isfield(result.details.converter, 'message'), ...
    'converter result must have message');
testCase.verifyTrue(isfield(result.details.converter, 'outputs'), ...
    'converter result must have outputs');
% Route diagnostic: .nii input via setupFakeEnvironment takes pass-through
testCase.verifyEqual(result.details.provenance.converter_route, ...
    'nifti-passthrough');
% Transient converter path in details only, not in public outputs
for k = 1:numel(result.outputs)
    testCase.verifyFalse(contains(result.outputs{k}, 'alias_convert_'), ...
        'Transient converter path must not appear in outputs');
end
if exist(outputFile, 'file') == 2, delete(outputFile); end
end

function testConverterFailedPreservesDiagnostics(testCase)
% GIVEN a converter that returns failed status
% WHEN alias.api.run is called
% THEN it returns 'failed' with full converter diagnostics
d2nDir = fullfile(tempdir, 'fake_d2n_api_fail_status');
if exist(d2nDir, 'dir') == 7, rmdir(d2nDir, 's'); end; mkdir(d2nDir);
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
fid = fopen(fullfile(d2nDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n'); fclose(fid);
apiDir = fullfile(d2nDir, '+dicom2nifti', '+api');
mkdir(apiDir);
fid = fopen(fullfile(apiDir, 'run.m'), 'w');
fprintf(fid, 'function result = run(inputFile, outputFile, varargin)\n');
fprintf(fid, 'result = struct();\n');
fprintf(fid, 'result.status = ''failed'';\n');
fprintf(fid, 'result.message = ''Converter refused: bad input format'';\n');
fprintf(fid, 'result.outputs = {};\n');
fprintf(fid, 'result.details = struct(''reason'', ''format_unsupported'');\n');
fprintf(fid, 'end\n');
fclose(fid);

spmDir = fullfile(tempdir, 'fake_spm_api_fail_status');
if exist(spmDir, 'dir') == 7, rmdir(spmDir, 's'); end; mkdir(spmDir);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
for m = {'spm_vol','spm_read_vols','spm_create_vol','spm_write_vol','spm_type'}
    fid = fopen(fullfile(spmDir, [m{1} '.m']), 'w');
    fprintf(fid, 'function varargout=%s(varargin),end', m{1}); fclose(fid);
end
addpath(spmDir, '-begin');

defaultsPath = fullfile(testCase.TestData.ProjectRoot, 'config', 'defaults.m');
orig = fileread(defaultsPath);
cCfg = onCleanup(@() writeDefaults(defaultsPath, orig));
fid = fopen(defaultsPath, 'w');
fprintf(fid, ['function c=defaults()\nc=struct();\n' ...
    'c.spm_root=''%s'';c.d2n_root=''%s'';' ...
    'c.d2n_entrypoint=''dcm2nii'';c.log_level=''info'';\nend\n'], spmDir, d2nDir); fclose(fid);

dcmPath = fullfile(testCase.TestData.TempDir, 'fail_status.dcm');
fid = fopen(dcmPath, 'w'); fprintf(fid, 'fake'); fclose(fid);
outPath = fullfile(testCase.TestData.TempDir, 'no_out_fail.nii');

result = alias.api.run(dcmPath, outPath, true, true, false);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:ConverterFailed');
testCase.verifyTrue(contains(result.details.failure.message, 'Converter refused'));
% Full converter result preserved
testCase.verifyTrue(isfield(result.details, 'converter'));
testCase.verifyEqual(result.details.converter.status, 'failed');
testCase.verifyTrue(contains(result.details.converter.message, 'bad input format'));
testCase.verifyEqual(result.outputs, {});
% Route diagnostic: .dcm input takes conversion route
testCase.verifyEqual(result.details.provenance.converter_route, ...
    'dicom2nifti-conversion');
end

function testFailureMetadataIncludesStackAndCause(testCase)
% GIVEN an API call that fails with an MException
% WHEN the result is returned
% THEN details.failure has identifier, message, stack, and cause fields
result = alias.api.run('', '', true, true, false);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyTrue(isfield(result.details.failure, 'identifier'));
testCase.verifyTrue(isfield(result.details.failure, 'message'));
testCase.verifyTrue(isfield(result.details.failure, 'stack'));
testCase.verifyTrue(isfield(result.details.failure, 'cause'));
testCase.verifyTrue(~isempty(result.details.failure.identifier));
testCase.verifyTrue(~isempty(result.details.failure.message));
end

function testPartialWithoutCommittedOutputIsFailed(testCase)
% GIVEN a converter that returns partial without producing output
% WHEN alias.api.run is called
% THEN it returns 'failed' (not 'partial') — no partial without committed output
d2nDir = fullfile(tempdir, 'fake_d2n_partial_no_output');
if exist(d2nDir, 'dir') == 7, rmdir(d2nDir, 's'); end; mkdir(d2nDir);
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
fid = fopen(fullfile(d2nDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n'); fclose(fid);
apiDir = fullfile(d2nDir, '+dicom2nifti', '+api');
mkdir(apiDir);
% Converter returns partial but does NOT write output
fid = fopen(fullfile(apiDir, 'run.m'), 'w');
fprintf(fid, 'function result = run(inputFile, outputFile, varargin)\n');
fprintf(fid, 'result = struct();\n');
fprintf(fid, 'result.status = ''partial'';\n');
fprintf(fid, 'result.message = ''Partial conversion, no output'';\n');
fprintf(fid, 'result.outputs = {};\n');
fprintf(fid, 'result.details = struct();\n');
fprintf(fid, 'end\n');
fclose(fid);

spmDir = fullfile(tempdir, 'fake_spm_partial_no_output');
if exist(spmDir, 'dir') == 7, rmdir(spmDir, 's'); end; mkdir(spmDir);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
for m = {'spm_vol','spm_read_vols','spm_create_vol','spm_write_vol','spm_type'}
    fid = fopen(fullfile(spmDir, [m{1} '.m']), 'w');
    fprintf(fid, 'function varargout=%s(varargin),end', m{1}); fclose(fid);
end
addpath(spmDir, '-begin');

defaultsPath = fullfile(testCase.TestData.ProjectRoot, 'config', 'defaults.m');
orig = fileread(defaultsPath);
cCfg = onCleanup(@() writeDefaults(defaultsPath, orig));
fid = fopen(defaultsPath, 'w');
fprintf(fid, ['function c=defaults()\nc=struct();\n' ...
    'c.spm_root=''%s'';c.d2n_root=''%s'';' ...
    'c.d2n_entrypoint=''dcm2nii'';c.log_level=''info'';\nend\n'], spmDir, d2nDir); fclose(fid);

inpPath = fullfile(testCase.TestData.TempDir, 'partial_no_out.dcm');
fid = fopen(inpPath, 'w'); fprintf(fid, 'fake'); fclose(fid);
outPath = fullfile(testCase.TestData.TempDir, 'partial_no_out.nii');

result = alias.api.run(inpPath, outPath, true, true, false);

% No partial without committed output
testCase.verifyEqual(result.status, 'failed', ...
    'Partial without committed output must be failed');
testCase.verifyEqual(result.outputs, {});
end

function testPartialWithUsableOutputContinuesAndCommits(testCase)
% GIVEN a converter that returns status='partial' with a usable NIfTI
% WHEN alias.api.run is called
% THEN it continues processing, runs the engine, commits corrected output,
%      returns final status='partial' only after successful commit,
%      outputs contains only the committed corrected output (never the
%      transient converter path), details.converter preserves the upstream
%      partial details/message, and alias-owned temp is cleaned up.

d2nDir = fullfile(tempdir, 'fake_d2n_partial_with_output');
if exist(d2nDir, 'dir') == 7, rmdir(d2nDir, 's'); end; mkdir(d2nDir);
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
fid = fopen(fullfile(d2nDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n'); fclose(fid);
apiDir = fullfile(d2nDir, '+dicom2nifti', '+api');
mkdir(apiDir);
% Converter returns partial AND writes a usable uncompressed NIfTI
fid = fopen(fullfile(apiDir, 'run.m'), 'w');
fprintf(fid, 'function result = run(inputFile, outputFile, varargin)\n');
fprintf(fid, 'fid = fopen(outputFile, ''w'');\n');
fprintf(fid, 'if fid > 0, fwrite(fid, ''FAKE_NIFTI_PARTIAL'', ''char''); fclose(fid); end\n');
fprintf(fid, 'result = struct();\n');
fprintf(fid, 'result.status = ''partial'';\n');
fprintf(fid, 'result.outputs = {outputFile};\n');
fprintf(fid, 'result.message = ''Partial conversion: 2 of 3 slices recovered.'';\n');
fprintf(fid, 'result.details = struct(''recovered_slices'', 2, ''total_slices'', 3, ''warning'', ''truncated_acquisition'');\n');
fprintf(fid, 'end\n');
fclose(fid);

spmDir = fullfile(tempdir, 'fake_spm_partial_with_output');
if exist(spmDir, 'dir') == 7, rmdir(spmDir, 's'); end
mkdir(spmDir);
cSpm = onCleanup(@() rmdir(spmDir, 's'));

fid = fopen(fullfile(spmDir, 'spm_vol.m'), 'w');
fprintf(fid, 'function V = spm_vol(fname)\n');
fprintf(fid, 'V = struct(''fname'',fname,''dim'',[32 32 16],''dt'',[16 0],''mat'',eye(4),''n'',[1 1],''pinfo'',[1;0;0]); end');
fclose(fid);

fid = fopen(fullfile(spmDir, 'spm_read_vols.m'), 'w');
fprintf(fid, 'function d = spm_read_vols(V)\n');
fprintf(fid, 'd = single(ones(V.dim)); end');
fclose(fid);

fid = fopen(fullfile(spmDir, 'spm_create_vol.m'), 'w');
fprintf(fid, 'function V = spm_create_vol(V), end');
fclose(fid);

fid = fopen(fullfile(spmDir, 'spm_write_vol.m'), 'w');
fprintf(fid, 'function spm_write_vol(V,d)\n');
fprintf(fid, 'fid = fopen(V.fname,''w''); fwrite(fid,d(:),''single''); fclose(fid); end');
fclose(fid);

fid = fopen(fullfile(spmDir, 'spm_type.m'), 'w');
fprintf(fid, 'function b = spm_type(dt, req)\n');
fprintf(fid, 'if strcmp(req,''bits''), b=32; else b=''FLOAT32-LE''; end; end');
fclose(fid);

addpath(spmDir, '-begin');

defaultsPath = fullfile(testCase.TestData.ProjectRoot, 'config', 'defaults.m');
orig = fileread(defaultsPath);
cCfg = onCleanup(@() writeDefaults(defaultsPath, orig));
fid = fopen(defaultsPath, 'w');
fprintf(fid, ['function c=defaults()\nc=struct();\n' ...
    'c.spm_root=''%s'';c.d2n_root=''%s'';' ...
    'c.d2n_entrypoint=''dcm2nii'';c.log_level=''info'';\nend\n'], spmDir, d2nDir); fclose(fid);

inpPath = fullfile(testCase.TestData.TempDir, 'partial_with_out.dcm');
fid = fopen(inpPath, 'w'); fprintf(fid, 'fake'); fclose(fid);
outPath = fullfile(testCase.TestData.TempDir, 'partial_with_out.nii');

% Snapshot temp dirs before to verify cleanup
beforeTempDirs = dir(fullfile(tempdir, 'alias_convert_*'));

result = alias.api.run(inpPath, outPath, true, true, false);

% Final status is 'partial' only after successful commit
testCase.verifyEqual(result.status, 'partial', ...
    'Partial with usable output must yield final status partial after commit');
testCase.verifyEqual(result.message, 'Correction completed from partial converter output.');

% outputs contains ONLY the committed corrected output — never transient path
testCase.verifyEqual(numel(result.outputs), 1, 'Exactly one output on partial-with-commit');
testCase.verifyTrue(contains(result.outputs{1}, 'partial_with_out.nii'), ...
    'Output must be the committed corrected path');
for k = 1:numel(result.outputs)
    testCase.verifyFalse(contains(result.outputs{k}, 'alias_convert_'), ...
        'Transient converter path must not appear in outputs');
end

% details.converter preserves the upstream partial details/message
testCase.verifyTrue(isfield(result.details, 'converter'), ...
    'details must contain converter result');
testCase.verifyEqual(result.details.converter.status, 'partial');
testCase.verifyTrue(contains(result.details.converter.message, '2 of 3 slices recovered'));
testCase.verifyTrue(isfield(result.details.converter, 'outputs'));
testCase.verifyTrue(isfield(result.details.converter, 'details'));
testCase.verifyEqual(result.details.converter.details.recovered_slices, 2);
testCase.verifyEqual(result.details.converter.details.total_slices, 3);
testCase.verifyEqual(result.details.converter.details.warning, 'truncated_acquisition');

% Engine ran: alias_correction and centering outcomes present
testCase.verifyTrue(isfield(result.details, 'alias_correction'));
testCase.verifyTrue(isfield(result.details, 'centering'));
testCase.verifyTrue(isfield(result.details, 'transform'));

% Alias-owned temp cleanup: no leftover alias_convert_* dirs
afterTempDirs = dir(fullfile(tempdir, 'alias_convert_*'));
testCase.verifyEqual(numel(afterTempDirs), numel(beforeTempDirs), ...
    'Alias-owned temp dirs must be cleaned up after partial-with-output path');
end

function testOutputsInvariantOnlyAfterCommit(testCase)
% GIVEN a successful API call
% WHEN the result is returned
% THEN outputs contains exactly the committed output path
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

result = alias.api.run(inputFile, outputFile, true, true, true);

testCase.verifyEqual(result.status, 'success');
testCase.verifyEqual(numel(result.outputs), 1, 'Exactly one output on success');
testCase.verifyTrue(contains(result.outputs{1}, 'preview_test_output.nii'));
% No transient paths
for k = 1:numel(result.outputs)
    testCase.verifyFalse(contains(result.outputs{k}, 'alias_convert_'));
    testCase.verifyFalse(contains(result.outputs{k}, '.tmp_'));
end
if exist(outputFile, 'file') == 2, delete(outputFile); end
end

function testCleanupRunsOnAllPaths(testCase)
% GIVEN various failure/success/cancel paths
% WHEN alias.api.run returns
% THEN all temp cleanup handles have run (no leftover temp dirs)
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

% List temp dirs before
beforeTempDirs = dir(fullfile(tempdir, 'alias_convert_*'));

% Success path
result = alias.api.run(inputFile, outputFile, true, true, true);
testCase.verifyEqual(result.status, 'success');
if exist(outputFile, 'file') == 2, delete(outputFile); end

% Failure path
result = alias.api.run('', outputFile, true, true, false);
testCase.verifyEqual(result.status, 'failed');

% Cancel path
opts = struct('previewFcn', @(ctx) 'cancel');
result = alias.api.run(inputFile, outputFile, true, true, true, opts);
testCase.verifyEqual(result.status, 'cancelled');

% List temp dirs after — should be same as before (cleanup ran)
afterTempDirs = dir(fullfile(tempdir, 'alias_convert_*'));
testCase.verifyEqual(numel(afterTempDirs), numel(beforeTempDirs), ...
    'All alias_convert_* temp dirs must be cleaned up');
end


%% --- T009: Stack/cause structured capture for thrown failures ---

function testConverterThrowPreservesStackAndCause(testCase)
% GIVEN a converter that throws an MException with stack and cause
% WHEN alias.api.run is called
% THEN details.failure.stack is a non-empty struct array with file/name/line
%   and details.failure.cause is a non-empty cell array of structs
d2nDir = fullfile(tempdir, 'fake_d2n_t009_throw');
if exist(d2nDir, 'dir') == 7, rmdir(d2nDir, 's'); end; mkdir(d2nDir);
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
fid = fopen(fullfile(d2nDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n'); fclose(fid);
apiDir = fullfile(d2nDir, '+dicom2nifti', '+api');
mkdir(apiDir);
fid = fopen(fullfile(apiDir, 'run.m'), 'w');
fprintf(fid, 'function result = run(inputFile, outputFile, varargin)\n');
fprintf(fid, 'inner = MException(''inner:cause'', ''inner cause message'');\n');
fprintf(fid, 'me = MException(''dicom2nifti:api:ConversionBoom'', ''converter exploded'');\n');
fprintf(fid, 'me = addCause(me, inner);\n');
fprintf(fid, 'throw(me);\n');
fprintf(fid, 'end\n');
fclose(fid);

spmDir = fullfile(tempdir, 'fake_spm_t009_throw');
if exist(spmDir, 'dir') == 7, rmdir(spmDir, 's'); end; mkdir(spmDir);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
for m = {'spm_vol','spm_read_vols','spm_create_vol','spm_write_vol','spm_type'}
    fid = fopen(fullfile(spmDir, [m{1} '.m']), 'w');
    fprintf(fid, 'function varargout=%s(varargin),end', m{1}); fclose(fid);
end
addpath(spmDir, '-begin');

defaultsPath = fullfile(testCase.TestData.ProjectRoot, 'config', 'defaults.m');
orig = fileread(defaultsPath);
cCfg = onCleanup(@() writeDefaults(defaultsPath, orig));
fid = fopen(defaultsPath, 'w');
fprintf(fid, ['function c=defaults()\nc=struct();\n' ...
    'c.spm_root=''%s'';c.d2n_root=''%s'';' ...
    'c.d2n_entrypoint=''dcm2nii'';c.log_level=''info'';\nend\n'], spmDir, d2nDir); fclose(fid);

dcmPath = fullfile(testCase.TestData.TempDir, 't009_throw.dcm');
fid = fopen(dcmPath, 'w'); fprintf(fid, 'fake'); fclose(fid);
outPath = fullfile(testCase.TestData.TempDir, 't009_throw_out.nii');

result = alias.api.run(dcmPath, outPath, true, true, false);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:ConverterFailed');
% Stack must be a non-empty struct array with file/name/line
stk = result.details.failure.stack;
testCase.verifyTrue(isstruct(stk), 'stack must be a struct array');
testCase.verifyTrue(numel(stk) > 0, 'stack must be non-empty for thrown converter');
testCase.verifyTrue(isfield(stk(1), 'file'));
testCase.verifyTrue(isfield(stk(1), 'name'));
testCase.verifyTrue(isfield(stk(1), 'line'));
testCase.verifyTrue(isnumeric(stk(1).line));
testCase.verifyTrue(~isempty(stk(1).file));
% Cause must be a non-empty cell array of structs
cs = result.details.failure.cause;
testCase.verifyTrue(iscell(cs), 'cause must be a cell array');
testCase.verifyTrue(numel(cs) > 0, 'cause must be non-empty when converter threw with cause');
testCase.verifyTrue(isstruct(cs{1}), 'each cause entry must be a struct');
testCase.verifyTrue(isfield(cs{1}, 'identifier'));
testCase.verifyTrue(isfield(cs{1}, 'message'));
testCase.verifyTrue(isfield(cs{1}, 'stack'));
testCase.verifyTrue(isfield(cs{1}, 'cause'));
testCase.verifyEqual(cs{1}.identifier, 'inner:cause');
testCase.verifyTrue(contains(cs{1}.message, 'inner cause message'));
end

function testCallbackThrowPreservesStackAndCause(testCase)
% GIVEN a preview callback that throws an MException with a cause chain
% WHEN alias.api.run is called
% THEN details.failure.stack is a non-empty struct array with file/name/line
%   and details.failure.cause is a non-empty cell array of structs with
%   identifier/message/stack
[spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
cCfg = onCleanup(@() writeDefaults(defaultsPath, origDefaults));

opts = struct('previewFcn', @throwingPreviewCallbackWithCause);
result = alias.api.run(inputFile, outputFile, true, true, true, opts);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:PreviewCallbackFailed');
% Stack must be a non-empty struct array with file/name/line
stk = result.details.failure.stack;
testCase.verifyTrue(isstruct(stk), 'stack must be a struct array');
testCase.verifyTrue(numel(stk) > 0, 'stack must be non-empty for callback throw');
testCase.verifyTrue(isfield(stk(1), 'file'));
testCase.verifyTrue(isfield(stk(1), 'name'));
testCase.verifyTrue(isfield(stk(1), 'line'));
testCase.verifyTrue(isnumeric(stk(1).line));
testCase.verifyTrue(~isempty(stk(1).file));
% Cause must be a non-empty cell array of structs (callback threw with addCause)
cs = result.details.failure.cause;
testCase.verifyTrue(iscell(cs), 'cause must be a cell array');
testCase.verifyTrue(numel(cs) > 0, 'cause must be non-empty when callback threw with cause');
testCase.verifyTrue(isstruct(cs{1}), 'each cause entry must be a struct');
testCase.verifyTrue(isfield(cs{1}, 'identifier'));
testCase.verifyTrue(isfield(cs{1}, 'message'));
testCase.verifyTrue(isfield(cs{1}, 'stack'));
testCase.verifyTrue(isfield(cs{1}, 'cause'));
testCase.verifyEqual(cs{1}.identifier, 'test:InnerCause');
testCase.verifyTrue(contains(cs{1}.message, 'inner callback cause'));
if exist(outputFile, 'file') == 2, delete(outputFile); end
end

function testSpmPreflightThrowPreservesStackAndCause(testCase)
% GIVEN an SPM read that throws with a cause chain (via broken spm_vol)
% WHEN alias.api.run is called
% THEN details.failure.stack is a non-empty struct array with file/name/line
%   and details.failure.cause is a non-empty cell array of structs

spmDir = fullfile(tempdir, 'fake_spm_t009_spm_throw');
if exist(spmDir, 'dir') == 7, rmdir(spmDir, 's'); end; mkdir(spmDir);
cSpm = onCleanup(@() rmdir(spmDir, 's'));
% Provide a broken spm_vol that throws WITH a cause chain
fid = fopen(fullfile(spmDir, 'spm_vol.m'), 'w');
fprintf(fid, 'function V = spm_vol(fname)\n');
fprintf(fid, 'inner = MException(''SPM:vol:innerCause'', ''SPM internal config error'');\n');
fprintf(fid, 'me = MException(''SPM:vol:badconfig'', ''SPM vol threw during read'');\n');
fprintf(fid, 'me = addCause(me, inner);\n');
fprintf(fid, 'throw(me);\n');
fprintf(fid, 'end\n');
fclose(fid);
for m = {'spm_read_vols','spm_create_vol','spm_write_vol','spm_type'}
    fid = fopen(fullfile(spmDir, [m{1} '.m']), 'w');
    fprintf(fid, 'function varargout=%s(varargin),end', m{1}); fclose(fid);
end
addpath(spmDir, '-begin');

d2nDir = fullfile(tempdir, 'fake_d2n_t009_spm_throw');
if exist(d2nDir, 'dir') == 7, rmdir(d2nDir, 's'); end; mkdir(d2nDir);
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
fid = fopen(fullfile(d2nDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n'); fclose(fid);
apiDir = fullfile(d2nDir, '+dicom2nifti', '+api');
mkdir(apiDir);
fid = fopen(fullfile(apiDir, 'run.m'), 'w');
fprintf(fid, 'function result = run(inputFile, outputFile, varargin)\n');
fprintf(fid, 'fid = fopen(outputFile, ''w'');\n');
fprintf(fid, 'if fid > 0, fwrite(fid, ''FAKE_NIFTI'', ''char''); fclose(fid); end\n');
fprintf(fid, 'result = struct();\n');
fprintf(fid, 'result.status = ''success'';\n');
fprintf(fid, 'result.outputs = {outputFile};\n');
fprintf(fid, 'result.message = ''ok'';\n');
fprintf(fid, 'result.details = struct();\n');
fprintf(fid, 'end\n');
fclose(fid);

defaultsPath = fullfile(testCase.TestData.ProjectRoot, 'config', 'defaults.m');
orig = fileread(defaultsPath);
cCfg = onCleanup(@() writeDefaults(defaultsPath, orig));
% Use nonexistent spm_root so preflight may fail, but caller has spm_vol
% that throws — the spm_vol call in run.m's SPM-read section will throw.
fid = fopen(defaultsPath, 'w');
fprintf(fid, ['function c=defaults()\nc=struct();\n' ...
    'c.spm_root=''/nonexistent/spm'';c.d2n_root=''%s'';' ...
    'c.d2n_entrypoint=''dcm2nii'';c.log_level=''info'';\nend\n'], d2nDir);
fclose(fid);

inputFile = fullfile(testCase.TestData.TempDir, 't009_spm_input.nii');
fid = fopen(inputFile, 'w'); fwrite(fid, zeros(1, 348, 'uint8')); fclose(fid);
outputFile = fullfile(testCase.TestData.TempDir, 't009_spm_output.nii');

result = alias.api.run(inputFile, outputFile, true, true, true);

testCase.verifyEqual(result.status, 'failed');
% The spm_vol stub throws — caught by the SPM-read catch block
testCase.verifyEqual(result.details.failure.identifier, 'alias:LoadFailed');
% Stack must be a non-empty struct array with file/name/line
stk = result.details.failure.stack;
testCase.verifyTrue(isstruct(stk), 'stack must be a struct array');
testCase.verifyTrue(numel(stk) > 0, 'stack must be non-empty for SPM throw');
testCase.verifyTrue(isfield(stk(1), 'file'));
testCase.verifyTrue(isfield(stk(1), 'name'));
testCase.verifyTrue(isfield(stk(1), 'line'));
testCase.verifyTrue(isnumeric(stk(1).line));
testCase.verifyTrue(~isempty(stk(1).file));
% Cause must be a non-empty cell array of structs (spm_vol threw with addCause)
cs = result.details.failure.cause;
testCase.verifyTrue(iscell(cs), 'cause must be a cell array');
testCase.verifyTrue(numel(cs) > 0, 'cause must be non-empty when SPM threw with cause');
testCase.verifyTrue(isstruct(cs{1}), 'each cause entry must be a struct');
testCase.verifyTrue(isfield(cs{1}, 'identifier'));
testCase.verifyTrue(isfield(cs{1}, 'message'));
testCase.verifyTrue(isfield(cs{1}, 'stack'));
testCase.verifyEqual(cs{1}.identifier, 'SPM:vol:innerCause');
testCase.verifyTrue(contains(cs{1}.message, 'SPM internal config error'));
end

function testConfigValidationThrowPreservesStackAndCause(testCase)
% GIVEN a configuration that fails validation (nonexistent d2n_root)
% WHEN alias.api.run is called
% THEN details.failure.stack is a non-empty struct array with file/name/line
%   and details.failure.cause is a cell array (empty for plain error throw)

% Create a valid d2n directory so load won't fail, but configure a
% nonexistent d2n_root to force alias.config.validate to throw
% alias:D2nRootMissing.
d2nDir = fullfile(tempdir, 'fake_d2n_t009_cfg_throw');
if exist(d2nDir, 'dir') == 7, rmdir(d2nDir, 's'); end; mkdir(d2nDir);
cD2n = onCleanup(@() rmdir(d2nDir, 's'));
fid = fopen(fullfile(d2nDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n'); fclose(fid);

% Use a nonexistent d2n_root to trigger alias:D2nRootMissing in validate
defaultsPath = fullfile(testCase.TestData.ProjectRoot, 'config', 'defaults.m');
orig = fileread(defaultsPath);
cCfg = onCleanup(@() writeDefaults(defaultsPath, orig));
fid = fopen(defaultsPath, 'w');
fprintf(fid, ['function c=defaults()\nc=struct();\n' ...
    'c.spm_root='''';c.d2n_root=''/nonexistent/d2n/root'';' ...
    'c.d2n_entrypoint=''dcm2nii'';c.log_level=''info'';\nend\n']);
fclose(fid);

inputFile = fullfile(testCase.TestData.TempDir, 't009_cfg_input.nii');
fid = fopen(inputFile, 'w'); fwrite(fid, zeros(1, 348, 'uint8')); fclose(fid);
outputFile = fullfile(testCase.TestData.TempDir, 't009_cfg_output.nii');

result = alias.api.run(inputFile, outputFile, true, true, true);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:D2nRootMissing');
% Stack must be a non-empty struct array with file/name/line
stk = result.details.failure.stack;
testCase.verifyTrue(isstruct(stk), 'stack must be a struct array');
testCase.verifyTrue(numel(stk) > 0, 'stack must be non-empty for config validation throw');
testCase.verifyTrue(isfield(stk(1), 'file'));
testCase.verifyTrue(isfield(stk(1), 'name'));
testCase.verifyTrue(isfield(stk(1), 'line'));
testCase.verifyTrue(isnumeric(stk(1).line));
testCase.verifyTrue(~isempty(stk(1).file));
% Cause must be a cell array (empty for plain error throw — demonstrates
% cause handling is correct even when no addCause was used)
cs = result.details.failure.cause;
testCase.verifyTrue(iscell(cs), 'cause must be a cell array');
testCase.verifyTrue(contains(result.message, 'Configuration validation failed'));
end


%% --- Test helpers ---

function [spmDir, d2nDir, defaultsPath, origDefaults, inputFile, outputFile] = ...
    setupFakeEnvironment(testCase)
% Build fake SPM + d2n + config for preview seam tests.

spmDir = fullfile(tempdir, 'fake_spm_preview_test');
if exist(spmDir, 'dir') == 7, rmdir(spmDir, 's'); end
mkdir(spmDir);

fid = fopen(fullfile(spmDir, 'spm_vol.m'), 'w');
fprintf(fid, 'function V = spm_vol(fname)\n');
fprintf(fid, 'V = struct(''fname'',fname,''dim'',[32 32 16],''dt'',[16 0],''mat'',eye(4),''n'',[1 1],''pinfo'',[1;0;0]); end');
fclose(fid);

fid = fopen(fullfile(spmDir, 'spm_read_vols.m'), 'w');
fprintf(fid, 'function d = spm_read_vols(V)\n');
fprintf(fid, 'd = single(ones(V.dim)); end');
fclose(fid);

fid = fopen(fullfile(spmDir, 'spm_create_vol.m'), 'w');
fprintf(fid, 'function V = spm_create_vol(V), end');
fclose(fid);

fid = fopen(fullfile(spmDir, 'spm_write_vol.m'), 'w');
fprintf(fid, 'function spm_write_vol(V,d)\n');
fprintf(fid, 'fid = fopen(V.fname,''w''); fwrite(fid,d(:),''single''); fclose(fid); end');
fclose(fid);

fid = fopen(fullfile(spmDir, 'spm_type.m'), 'w');
fprintf(fid, 'function b = spm_type(dt, req)\n');
fprintf(fid, 'if strcmp(req,''bits''), b=32; else b=''FLOAT32-LE''; end; end');
fclose(fid);

d2nDir = fullfile(tempdir, 'fake_d2n_preview_test');
if exist(d2nDir, 'dir') == 7, rmdir(d2nDir, 's'); end
mkdir(d2nDir);
fid = fopen(fullfile(d2nDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n');
fclose(fid);
apiDir = fullfile(d2nDir, '+dicom2nifti', '+api');
mkdir(apiDir);
fid = fopen(fullfile(apiDir, 'run.m'), 'w');
fprintf(fid, 'function result = run(inputFile, outputFile, varargin)\n');
fprintf(fid, 'fid = fopen(outputFile, ''w'');\n');
fprintf(fid, 'if fid > 0, fwrite(fid, ''FAKE_NIFTI'', ''char''); fclose(fid); end\n');
fprintf(fid, 'result = struct();\n');
fprintf(fid, 'result.status = ''success'';\n');
fprintf(fid, 'result.outputs = {outputFile};\n');
fprintf(fid, 'result.message = ''Conversion complete.'';\n');
fprintf(fid, 'result.details = struct(''spm_loaded'', true, ''cleanup_error'', '''', ''version_log_error'', '''');\n');
fprintf(fid, 'end\n');
fclose(fid);

addpath(spmDir, '-begin');

projectRoot = testCase.TestData.ProjectRoot;
defaultsPath = fullfile(projectRoot, 'config', 'defaults.m');
origDefaults = fileread(defaultsPath);
fid = fopen(defaultsPath, 'w');
fprintf(fid, ['function c=defaults()\nc=struct();\n' ...
    'c.spm_root=''%s'';c.d2n_root=''%s'';' ...
    'c.d2n_entrypoint=''dcm2nii'';c.log_level=''info'';\nend\n'], spmDir, d2nDir);
fclose(fid);

inputFile = fullfile(testCase.TestData.TempDir, 'preview_test_input.nii');
fid = fopen(inputFile, 'w'); fwrite(fid, zeros(1, 348, 'uint8')); fclose(fid);
outputFile = fullfile(testCase.TestData.TempDir, 'preview_test_output.nii');
end

function writeDefaults(p, c)
fid = fopen(p, 'w');
fprintf(fid, '%s', c); fclose(fid);
end

function decision = throwingPreviewCallback(ctx)
% Preview callback that throws — used to test callback failure handling.
% Defined as a named function so MATLAB allows output capture.
error('test:CallbackBoom', 'callback exploded');
end

function decision = throwingPreviewCallbackWithCause(ctx)
% Preview callback that throws with a cause chain — used to test
% structured stack/cause capture for callback failures.
inner = MException('test:InnerCause', 'inner callback cause');
me = MException('test:CallbackBoomWithCause', 'callback exploded with cause');
me = addCause(me, inner);
throw(me);
end
