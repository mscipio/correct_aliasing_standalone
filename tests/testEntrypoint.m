function tests = testEntrypoint
%TESTENTRYPOINT Tests for the correct_aliasing dispatcher entrypoint.
%   Verifies: zero-arg dispatch returns GUI result (not []), explicit
%   mode remains non-interactive, path/CWD cleanup is exact, result
%   schema is {status, outputs, message, details}.

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


function testDispatcherExists(testCase)
dispatcherPath = fullfile(testCase.TestData.ProjectRoot, 'correct_aliasing.m');
testCase.verifyTrue(exist(dispatcherPath, 'file') == 2, ...
    'Dispatcher correct_aliasing.m must exist');
end

function testDispatcherZeroArgsReturnsGuiResult(testCase)
% GIVEN the dispatcher source
% WHEN zero-arg mode is used with nargout > 0
% THEN it returns alias.gui.mainWindow() result, never []
dispatcherPath = fullfile(testCase.TestData.ProjectRoot, 'correct_aliasing.m');
content = fileread(dispatcherPath);

% Verify it does NOT return [] for nargout > 0 in zero-arg mode
% It should return alias.gui.mainWindow() instead
testCase.verifyFalse(contains(content, 'varargout{1} = []'), ...
    'Zero-arg mode must not return [] — must return GUI result');
testCase.verifyTrue(contains(content, 'varargout{1} = alias.gui.mainWindow()'), ...
    'Zero-arg mode with nargout must return alias.gui.mainWindow() result');
end

function testDispatcherExplicitModeNoUi(testCase)
% GIVEN an explicit call with arguments
% WHEN correct_aliasing is called
% THEN it routes to alias.api.run (non-interactive), never to GUI
dispatcherPath = fullfile(testCase.TestData.ProjectRoot, 'correct_aliasing.m');
content = fileread(dispatcherPath);

% After nargin==0 block, explicit path calls alias.api.run
testCase.verifyTrue(contains(content, 'alias.api.run'), ...
    'Explicit mode must call alias.api.run');
end

function testDispatcherRestoresPathAndCwd(testCase)
% GIVEN the dispatcher source
% WHEN we inspect it
% THEN it has onCleanup for path/CWD restoration
dispatcherPath = fullfile(testCase.TestData.ProjectRoot, 'correct_aliasing.m');
content = fileread(dispatcherPath);
testCase.verifyTrue(contains(content, 'onCleanup'), ...
    'Dispatcher must have onCleanup guard');
testCase.verifyTrue(contains(content, 'restoreSession'), ...
    'Dispatcher must restore session state');
end

function testExplicitInvalidArgsReturnFailed(testCase)
% GIVEN invalid arguments
% WHEN correct_aliasing is called explicitly
% THEN result is 'failed' with alias:InvalidArguments
result = correct_aliasing('/some/input.nii', '/some/output.nii', ...
    'AliasCorrection', 'notlogical');

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:InvalidArguments');
end

function testExplicitResultHasFourFields(testCase)
% GIVEN any explicit call
% WHEN the result is returned
% THEN it has exactly four top-level fields
result = correct_aliasing('', '', 'AliasCorrection', true);
fn = fieldnames(result);
testCase.verifyEqual(numel(fn), 4);
testCase.verifyEqual(fn{1}, 'status');
testCase.verifyEqual(fn{2}, 'outputs');
testCase.verifyEqual(fn{3}, 'message');
testCase.verifyEqual(fn{4}, 'details');
end

function testExplicitNonexistentInputFails(testCase)
% GIVEN a nonexistent input file
% WHEN correct_aliasing is called
% THEN it returns 'failed'
inFile = fullfile(testCase.TestData.TempDir, 'noexist.nii');
outFile = fullfile(testCase.TestData.TempDir, 'out.nii');
result = correct_aliasing(inFile, outFile, 'AliasCorrection', true, ...
    'Centering', true, 'Overwrite', false);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.outputs, {});
end

function testExplicitSameInputOutputFails(testCase)
% GIVEN input == output
% WHEN correct_aliasing is called
% THEN it returns 'failed' with alias:InputOutputSame
sameFile = fullfile(testCase.TestData.TempDir, 'same_entry.nii');
fid = fopen(sameFile, 'w'); fprintf(fid, 'fake'); fclose(fid);

result = correct_aliasing(sameFile, sameFile, ...
    'AliasCorrection', true, 'Centering', true);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:InputOutputSame');
end

function testExplicitOverwriteRefused(testCase)
% GIVEN existing output and Overwrite=false
% WHEN correct_aliasing is called
% THEN it returns 'failed' with alias:OutputExists
outFile = fullfile(testCase.TestData.TempDir, 'exists_entry.nii');
fid = fopen(outFile, 'w'); fprintf(fid, 'old'); fclose(fid);
inFile = fullfile(testCase.TestData.TempDir, 'in_entry.nii');
fid = fopen(inFile, 'w'); fprintf(fid, 'data'); fclose(fid);

result = correct_aliasing(inFile, outFile, ...
    'AliasCorrection', true, 'Centering', true, 'Overwrite', false);

testCase.verifyEqual(result.status, 'failed');
testCase.verifyEqual(result.details.failure.identifier, 'alias:OutputExists');
end

function testPathRestoredAfterExplicitCall(testCase)
% GIVEN the current path and CWD
% WHEN correct_aliasing is called (even if it fails)
% THEN path and CWD are unchanged
bp = path;
bd = pwd;

inFile = fullfile(testCase.TestData.TempDir, 'noexist_path.nii');
outFile = fullfile(testCase.TestData.TempDir, 'out_path.nii');
correct_aliasing(inFile, outFile, 'AliasCorrection', true);

testCase.verifyEqual(path, bp, 'Path must be restored');
testCase.verifyEqual(pwd, bd, 'CWD must be restored');
end
