function tests = testConverterBoundary
%TESTCONVERTERBOUNDARY Tests for the thin public-contract adapter.
%   Verifies: existing .nii files pass through directly (no converter
%   call, no alias_convert_* workspace, source preserved); .nii.gz,
%   DICOM, and folder inputs traverse the dicom2nifti.api.run converter
%   route; cleanup ownership; source preservation; converter error
%   diagnostics; path/CWD restoration for both routes; shadowing guard;
%   route diagnostics distinguish pass-through from conversion.

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


%% --- Helpers ---

function markers = coreMarkers()
markers = {'spm_vol', 'spm_read_vols', 'spm_create_vol', ...
           'spm_write_vol', 'spm_type'};
end

function tmpDir = makeFakeSpmRoot(name, markerNames)
tmpDir = fullfile(tempdir, ['fake_cb_spm_' name]);
if exist(tmpDir, 'dir') == 7, rmdir(tmpDir, 's'); end
mkdir(tmpDir);
for i = 1:numel(markerNames)
    fid = fopen(fullfile(tmpDir, [markerNames{i} '.m']), 'w');
    fprintf(fid, 'function varargout = %s(varargin), end', markerNames{i});
    fclose(fid);
end
end

function tmpDir = makeFakeD2nRoot(name)
% Create a fake d2n root with a contract-shaped dicom2nifti.api.run stub.
% The stub logs its arguments and writes a marker file to the output path.
tmpDir = fullfile(tempdir, ['fake_cb_d2n_' name]);
if exist(tmpDir, 'dir') == 7, rmdir(tmpDir, 's'); end
mkdir(tmpDir);

% Legacy facade stub (for shadowing check)
fid = fopen(fullfile(tmpDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n');
fclose(fid);

% Structured API stub
apiDir = fullfile(tmpDir, '+dicom2nifti', '+api');
mkdir(apiDir);
writeConverterStub(fullfile(apiDir, 'run.m'));
end

function writeConverterStub(filePath)
fid = fopen(filePath, 'w');
fprintf(fid, 'function result = run(inputFile, outputFile, varargin)\n');
fprintf(fid, '%% Contract-shaped stub — logs args, writes output\n');
fprintf(fid, 'lf = fullfile(tempdir, ''alias_cb_invoke.log'');\n');
fprintf(fid, 'f = fopen(lf, ''a'');\n');
fprintf(fid, 'fprintf(f, ''INPUT:%%s\\n'', inputFile);\n');
fprintf(fid, 'fprintf(f, ''OUTPUT:%%s\\n'', outputFile);\n');
% Parse Name-Value pairs for logging
fprintf(fid, 'for k = 1:2:numel(varargin)\n');
fprintf(fid, '  if ischar(varargin{k})\n');
fprintf(fid, '    fprintf(f, ''NV:%%s'', varargin{k});\n');
fprintf(fid, '    if k+1 <= numel(varargin)\n');
fprintf(fid, '      v = varargin{k+1};\n');
fprintf(fid, '      if ischar(v), fprintf(f, ''=%%s'', v);\n');
fprintf(fid, '      elseif islogical(v), fprintf(f, ''=%%s'', mat2str(v));\n');
fprintf(fid, '      else fprintf(f, ''=%%s'', mat2str(v)); end\n');
fprintf(fid, '    end\n');
fprintf(fid, '    fprintf(f, ''\\n'');\n');
fprintf(fid, '  end\n');
fprintf(fid, 'end\n');
fprintf(fid, 'fclose(f);\n');
% Write a fake NIfTI to the output path
fprintf(fid, 'fid = fopen(outputFile, ''w'');\n');
fprintf(fid, 'if fid > 0\n');
fprintf(fid, '  fwrite(fid, ''CB_STUB_NIFTI'', ''char'');\n');
fprintf(fid, '  fclose(fid);\n');
fprintf(fid, 'end\n');
% Return contract-shaped result
fprintf(fid, 'result = struct();\n');
fprintf(fid, 'result.status = ''success'';\n');
fprintf(fid, 'result.outputs = {outputFile, fullfile(fileparts(outputFile), ''dcm2nii_version.txt'')};\n');
fprintf(fid, 'result.message = ''Conversion complete.'';\n');
fprintf(fid, 'result.details = struct(''spm_loaded'', true, ''cleanup_error'', '''', ''version_log_error'', '''');\n');
fprintf(fid, 'end\n');
fclose(fid);
end

function writeThrowingConverterStub(filePath)
fid = fopen(filePath, 'w');
fprintf(fid, 'function result = run(inputFile, outputFile, varargin)\n');
fprintf(fid, 'error(''dicom2nifti:api:ConversionFailed'', ''converter exploded'');\n');
fprintf(fid, 'end\n');
fclose(fid);
end

function cleanup = addCleanup(tmpDir)
cleanup = onCleanup(@() rmdir(tmpDir, 's'));
end

function cleanupLog()
logPath = fullfile(tempdir, 'alias_cb_invoke.log');
if exist(logPath, 'file') == 2, delete(logPath); end
end

function lines = readLog()
logPath = fullfile(tempdir, 'alias_cb_invoke.log');
if exist(logPath, 'file') ~= 2
    lines = {};
    return;
end
fid = fopen(logPath, 'r');
lines = textscan(fid, '%s', 'Delimiter', '\n');
fclose(fid);
lines = lines{1};
end


%% --- .nii pass-through: direct path, no converter, source preserved ---

function testNiiPassthrough(testCase)
% Existing .nii file returned directly, no converter call, no
% alias_convert_* directory, source preserved after clearing cleanup.
d2nDir = makeFakeD2nRoot('nii_passthrough');
c1 = addCleanup(d2nDir);

config = struct('d2n_root', d2nDir, 'd2n_entrypoint', 'dcm2nii', ...
    'spm_root', '', 'log_level', 'info');

% Create an existing .nii file
origContent = 'fake nifti content for passthrough test';
inpPath = fullfile(testCase.TestData.TempDir, 'passthrough_test.nii');
fid = fopen(inpPath, 'w'); fprintf(fid, '%s', origContent); fclose(fid);

% Count alias_convert_* dirs before
beforeDirs = dir(fullfile(tempdir, 'alias_convert_*'));
cleanupLog();

bp = path; bd = pwd;
[niiPath, cleanup, convResult] = alias.api.loadInput(inpPath, config);

% 1. Direct path: niiPath == inputPath
testCase.verifyEqual(niiPath, inpPath, ...
    'Pass-through must return input path directly');

% 2. Converter not called (log empty)
lines = readLog();
testCase.verifyEqual(numel(lines), 0, ...
    'Converter must not be called for .nii pass-through');

% 3. No new alias_convert_* directory
afterDirs = dir(fullfile(tempdir, 'alias_convert_*'));
testCase.verifyEqual(numel(afterDirs), numel(beforeDirs), ...
    'No alias_convert_* directory created for .nii pass-through');

% 4. Synthetic result with correct route
testCase.verifyEqual(convResult.status, 'success');
testCase.verifyEqual(convResult.details.converter_route, 'nifti-passthrough');
testCase.verifyEqual(convResult.outputs, {inpPath});

% 5. Clearing cleanup does not delete source and bytes unchanged
clear cleanup;
testCase.verifyTrue(exist(inpPath, 'file') == 2, ...
    'Source must exist after clearing cleanup');
fid = fopen(inpPath, 'r');
afterContent = fread(fid, inf, 'uint8=>char')';
fclose(fid);
testCase.verifyEqual(afterContent, origContent, ...
    'Source bytes must be unchanged after clearing cleanup');

% 6. Path/CWD restored
testCase.verifyEqual(path, bp, 'Path must be restored after pass-through');
testCase.verifyEqual(pwd, bd, 'CWD must be restored after pass-through');

% 7. Case-insensitive: .NII also passes through
inpUpper = fullfile(testCase.TestData.TempDir, 'passthrough_test.NII');
fid = fopen(inpUpper, 'w'); fprintf(fid, 'fake'); fclose(fid);
[niiPath2, cleanup2, convResult2] = alias.api.loadInput(inpUpper, config);
testCase.verifyEqual(niiPath2, inpUpper, ...
    'Case-insensitive .NII must also pass through');
testCase.verifyEqual(convResult2.details.converter_route, 'nifti-passthrough');
clear cleanup2;
if exist(inpUpper, 'file') == 2, delete(inpUpper); end

cleanupLog();
end


%% --- Non-.nii inputs use the converter route ---

function testNonNiiInputsUseConverter(testCase)
% .nii.gz, .dcm, .ima, and folder all go through dicom2nifti.api.run
d2nDir = makeFakeD2nRoot('non_nii_types');
c1 = addCleanup(d2nDir);

config = struct('d2n_root', d2nDir, 'd2n_entrypoint', 'dcm2nii', ...
    'spm_root', '', 'log_level', 'info');

inputTypes = { ...
    'test.nii.gz', ...
    'test.dcm', ...
    'test.ima', ...
    'test_folder'};

for i = 1:numel(inputTypes)
    cleanupLog();
    inpName = inputTypes{i};
    inpPath = fullfile(testCase.TestData.TempDir, inpName);
    if strcmp(inpName, 'test_folder')
        if exist(inpPath, 'dir') ~= 7, mkdir(inpPath); end
    else
        fid = fopen(inpPath, 'w'); fprintf(fid, 'fake'); fclose(fid);
    end

    bp = path; bd = pwd;
    [niiPath, cleanup, convResult] = alias.api.loadInput(inpPath, config);
    testCase.verifyTrue(~isempty(niiPath), ...
        sprintf('Type %s must produce a NIfTI path', inpName));
    testCase.verifyTrue(exist(niiPath, 'file') == 2, ...
        sprintf('Type %s: produced NIfTI must exist', inpName));
    testCase.verifyTrue(endsWith(niiPath, '.nii'), ...
        sprintf('Type %s: output must be .nii', inpName));
    testCase.verifyEqual(convResult.status, 'success', ...
        sprintf('Type %s: converter must succeed', inpName));

    % Converter route must be dicom2nifti-conversion
    testCase.verifyEqual(convResult.details.converter_route, ...
        'dicom2nifti-conversion', ...
        sprintf('Type %s: route must be dicom2nifti-conversion', inpName));

    % NIfTI path must be under alias_convert_* workspace
    testCase.verifyTrue(contains(niiPath, 'alias_convert_'), ...
        sprintf('Type %s: NIfTI must be in adapter temp workspace', inpName));

    clear cleanup;

    % Verify the converter was invoked
    lines = readLog();
    testCase.verifyTrue(numel(lines) > 0, ...
        sprintf('Type %s: converter must be invoked', inpName));

    % Verify Compression=none was requested
    hasCompNone = any(cellfun(@(l) contains(l, 'Compression') && contains(l, 'none'), lines));
    testCase.verifyTrue(hasCompNone, ...
        sprintf('Type %s: must request Compression=none', inpName));

    testCase.verifyEqual(path, bp, sprintf('Path leak for type %s', inpName));
    testCase.verifyEqual(pwd, bd, sprintf('CWD leak for type %s', inpName));
end

% Clean up folder
folderPath = fullfile(testCase.TestData.TempDir, 'test_folder');
if exist(folderPath, 'dir') == 7, rmdir(folderPath, 's'); end
cleanupLog();
end


%% --- Only dependency output reaches SPM ---

function testOnlyDependencyOutputReachesSpm(testCase)
% The adapter produces a NIfTI in its own temp workspace.
% The produced path is under tempdir/alias_convert_*, never the input path.
d2nDir = makeFakeD2nRoot('spm_only');
c1 = addCleanup(d2nDir);

config = struct('d2n_root', d2nDir, 'd2n_entrypoint', 'dcm2nii', ...
    'spm_root', '', 'log_level', 'info');

dcmPath = fullfile(testCase.TestData.TempDir, 'spm_test.dcm');
fid = fopen(dcmPath, 'w'); fprintf(fid, 'fake'); fclose(fid);

[niiPath, cleanup, ~] = alias.api.loadInput(dcmPath, config);

% The NIfTI path must be under the adapter's temp workspace
testCase.verifyTrue(contains(niiPath, 'alias_convert_'), ...
    'NIfTI must be in the adapter''s temp workspace');
testCase.verifyTrue(contains(niiPath, 'converted.nii'), ...
    'NIfTI must be named converted.nii');
% It must NOT be the input path
testCase.verifyFalse(strcmp(niiPath, dcmPath), ...
    'NIfTI path must differ from input path');

clear cleanup;
end


%% --- Cleanup ownership ---

function testCleanupOwnershipAliasOwned(testCase)
% The adapter's temp workspace is cleaned by the returned handle.
% The dependency-owned artifacts are not deleted by the adapter.
d2nDir = makeFakeD2nRoot('cleanup_own');
c1 = addCleanup(d2nDir);

config = struct('d2n_root', d2nDir, 'd2n_entrypoint', 'dcm2nii', ...
    'spm_root', '', 'log_level', 'info');

inpPath = fullfile(testCase.TestData.TempDir, 'cleanup_test.dcm');
fid = fopen(inpPath, 'w'); fprintf(fid, 'fake'); fclose(fid);

[niiPath, cleanup] = alias.api.loadInput(inpPath, config);
tmpWorkspace = fileparts(niiPath);
testCase.verifyTrue(exist(tmpWorkspace, 'dir') == 7, ...
    'Temp workspace must exist before cleanup');

% Clear the cleanup handle — temp workspace should be removed
clear cleanup;
testCase.verifyTrue(exist(tmpWorkspace, 'dir') ~= 7, ...
    'Temp workspace must be cleaned after handle is cleared');
end


%% --- No transient outputs exposure ---

function testNoTransientOutputsInResult(testCase)
% When called through alias.api.run, the converter's temp path must
% NOT appear in result.outputs — only the final corrected output.
% This is verified at the run.m level; here we verify the adapter
% itself returns only the path (not a result struct with outputs).
d2nDir = makeFakeD2nRoot('no_expose');
c1 = addCleanup(d2nDir);

config = struct('d2n_root', d2nDir, 'd2n_entrypoint', 'dcm2nii', ...
    'spm_root', '', 'log_level', 'info');

inpPath = fullfile(testCase.TestData.TempDir, 'expose_test.nii');
fid = fopen(inpPath, 'w'); fprintf(fid, 'fake'); fclose(fid);

[niiPath, cleanup] = alias.api.loadInput(inpPath, config);
% The adapter returns a char path, not a struct with outputs
testCase.verifyClass(niiPath, 'char');
clear cleanup;
end


%% --- Source preservation ---

function testSourceNotMutated(testCase)
d2nDir = makeFakeD2nRoot('source_safe');
c1 = addCleanup(d2nDir);

config = struct('d2n_root', d2nDir, 'd2n_entrypoint', 'dcm2nii', ...
    'spm_root', '', 'log_level', 'info');

dcmPath = fullfile(testCase.TestData.TempDir, 'source_safe.dcm');
origContent = 'original dicom data 12345';
fid = fopen(dcmPath, 'w'); fprintf(fid, '%s', origContent); fclose(fid);

[niiPath, cleanup, ~] = alias.api.loadInput(dcmPath, config);
clear cleanup;

% Source must be unchanged
testCase.verifyTrue(exist(dcmPath, 'file') == 2);
fid = fopen(dcmPath, 'r');
c = fread(fid, inf, 'uint8=>char')';
fclose(fid);
testCase.verifyEqual(c, origContent);
end


%% --- Converter error diagnostics ---

function testThrowingConverterReturnsFailedResult(testCase)
d2nDir = fullfile(tempdir, 'fake_cb_d2n_throw');
if exist(d2nDir, 'dir') == 7, rmdir(d2nDir, 's'); end
mkdir(d2nDir);
c1 = addCleanup(d2nDir);

% Legacy facade stub
fid = fopen(fullfile(d2nDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n');
fclose(fid);

% Throwing structured API stub
apiDir = fullfile(d2nDir, '+dicom2nifti', '+api');
mkdir(apiDir);
writeThrowingConverterStub(fullfile(apiDir, 'run.m'));

config = struct('d2n_root', d2nDir, 'd2n_entrypoint', 'dcm2nii', ...
    'spm_root', '', 'log_level', 'info');

dcmPath = fullfile(testCase.TestData.TempDir, 'throw_test.dcm');
fid = fopen(dcmPath, 'w'); fprintf(fid, 'fake'); fclose(fid);

bp = path; bd = pwd;
[niiPath, cleanup, convResult] = alias.api.loadInput(dcmPath, config);
clear cleanup;

% loadInput no longer throws on converter failure — returns result
testCase.verifyEqual(niiPath, '', 'No NIfTI path on converter throw');
testCase.verifyTrue(isfield(convResult, 'status'), 'Must have status field');
testCase.verifyEqual(convResult.status, 'failed', 'Status must be failed');
testCase.verifyTrue(contains(convResult.message, 'dicom2nifti:api:ConversionFailed'), ...
    'Must preserve original converter identifier');
testCase.verifyTrue(contains(convResult.message, 'converter exploded'), ...
    'Must preserve original converter message');
testCase.verifyEqual(path, bp);
testCase.verifyEqual(pwd, bd);
end


%% --- Path/CWD restoration ---

function testPathAndCwdRestored(testCase)
d2nDir = makeFakeD2nRoot('path_restore');
c1 = addCleanup(d2nDir);

config = struct('d2n_root', d2nDir, 'd2n_entrypoint', 'dcm2nii', ...
    'spm_root', '', 'log_level', 'info');

% Pass-through route (.nii)
inpNii = fullfile(testCase.TestData.TempDir, 'restore_test.nii');
fid = fopen(inpNii, 'w'); fprintf(fid, 'fake'); fclose(fid);

bp = path; bd = pwd;
[niiPath, cleanup] = alias.api.loadInput(inpNii, config);
clear cleanup;
testCase.verifyEqual(path, bp, 'Path must be restored after pass-through');
testCase.verifyEqual(pwd, bd, 'CWD must be restored after pass-through');

% Conversion route (.dcm)
inpDcm = fullfile(testCase.TestData.TempDir, 'restore_test.dcm');
fid = fopen(inpDcm, 'w'); fprintf(fid, 'fake'); fclose(fid);

bp = path; bd = pwd;
[niiPath, cleanup] = alias.api.loadInput(inpDcm, config);
clear cleanup;
testCase.verifyEqual(path, bp, 'Path must be restored after conversion');
testCase.verifyEqual(pwd, bd, 'CWD must be restored after conversion');
end


%% --- Shadowing guard ---

function testShadowedConverterRejected(testCase)
% d2n_root exists but dicom2nifti.api.run resolves from elsewhere
d2nEmptyDir = fullfile(tempdir, 'fake_cb_d2n_empty');
if exist(d2nEmptyDir, 'dir') == 7, rmdir(d2nEmptyDir, 's'); end
mkdir(d2nEmptyDir);
c1 = addCleanup(d2nEmptyDir);

% Write a dcm2nii stub (so the dir isn't totally empty)
fid = fopen(fullfile(d2nEmptyDir, 'dcm2nii.m'), 'w');
fprintf(fid, 'function dcm2nii(varargin), end\n');
fclose(fid);
% But NO +dicom2nifti/+api/run.m — so which('dicom2nifti.api.run') is empty

config = struct('d2n_root', d2nEmptyDir, 'd2n_entrypoint', 'dcm2nii', ...
    'spm_root', '', 'log_level', 'info');

inpPath = fullfile(testCase.TestData.TempDir, 'shadow_test.dcm');
fid = fopen(inpPath, 'w'); fprintf(fid, 'fake'); fclose(fid);

f = @() alias.api.loadInput(inpPath, config);
testCase.verifyError(f, 'alias:ConverterMissing');
end


%% --- Overwrite passed to converter ---

function testOverwriteTruePassedToConverter(testCase)
d2nDir = makeFakeD2nRoot('overwrite');
c1 = addCleanup(d2nDir);

config = struct('d2n_root', d2nDir, 'd2n_entrypoint', 'dcm2nii', ...
    'spm_root', '', 'log_level', 'info');

cleanupLog();
inpPath = fullfile(testCase.TestData.TempDir, 'overwrite_test.nii.gz');
fid = fopen(inpPath, 'w'); fprintf(fid, 'fake'); fclose(fid);

[niiPath, cleanup] = alias.api.loadInput(inpPath, config);
clear cleanup;

lines = readLog();
hasOverwrite = any(cellfun(@(l) contains(l, 'Overwrite') && contains(l, 'true'), lines));
testCase.verifyTrue(hasOverwrite, ...
    'Must pass Overwrite=true to the converter');
cleanupLog();
end


%% --- No extension dispatch in adapter source ---

function testNoExtensionDispatchInAdapter(testCase)
% Adapter uses isNiftiPassthrough for conditional routing — not the
% obsolete isNiftiExt/isDicomExt helpers.
adapterPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+api', 'loadInput.m');
content = fileread(adapterPath);
lines = strsplit(content, '\n');
hasPassthrough = false;
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if startsWith(line, '%'), continue; end
    if contains(line, 'isNiftiPassthrough'), hasPassthrough = true; end
    testCase.verifyFalse(contains(line, 'isNiftiExt'), ...
        'Adapter must not contain isNiftiExt');
    testCase.verifyFalse(contains(line, 'isDicomExt'), ...
        'Adapter must not contain isDicomExt');
end
testCase.verifyTrue(hasPassthrough, ...
    'Adapter must contain isNiftiPassthrough for conditional routing');
end


%% --- No direct spm_vol/spm_read_vols in adapter ---

function testNoDirectSpmReadInAdapter(testCase)
adapterPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+api', 'loadInput.m');
content = fileread(adapterPath);
lines = strsplit(content, '\n');
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if startsWith(line, '%'), continue; end
    testCase.verifyFalse(contains(line, 'spm_vol('), ...
        'Adapter must not call spm_vol directly');
    testCase.verifyFalse(contains(line, 'spm_read_vols('), ...
        'Adapter must not call spm_read_vols directly');
end
end


%% --- run.m uses sameCanonicalPath ---

function testRunUsesSameCanonicalPath(testCase)
runPath = fullfile(testCase.TestData.ProjectRoot, '+alias', '+api', 'run.m');
content = fileread(runPath);
testCase.verifyTrue(contains(content, 'alias.util.sameCanonicalPath'), ...
    'run.m must use alias.util.sameCanonicalPath for same-file guard');
end


%% --- run.m has no extension dispatch ---

function testRunHasNoExtensionDispatch(testCase)
runPath = fullfile(testCase.TestData.ProjectRoot, '+alias', '+api', 'run.m');
content = fileread(runPath);
testCase.verifyFalse(contains(content, 'isNiftiExt'), ...
    'run.m must not contain isNiftiExt');
testCase.verifyFalse(contains(content, 'isDicomExt'), ...
    'run.m must not contain isDicomExt');
end
