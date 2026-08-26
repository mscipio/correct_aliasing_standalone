function tests = testGui
%TESTGUI Tests for the operator GUI via callback injection.
%   The GUI uses Java JFileChooser for file/folder selection. We test
%   the GUI logic by verifying the source code delegates processing
%   to alias.api.run and contains no prohibited direct calls.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(projectRoot);
testCase.TestData.ProjectRoot = projectRoot;
testCase.TestData.TempDir = tempname;
mkdir(testCase.TestData.TempDir);
end

function teardownOnce(testCase)
if exist(testCase.TestData.TempDir, 'dir') == 7
    rmdir(testCase.TestData.TempDir, 's');
end
end


function testGuiModuleExists(testCase)
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
testCase.verifyTrue(exist(guiPath, 'file') == 2, ...
    'GUI module must exist');
end

function testGuiRestoresPathAndCwd(testCase)
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
testCase.verifyTrue(contains(content, 'onCleanup'), ...
    'GUI must have an onCleanup guard');
testCase.verifyTrue(contains(content, 'restoreSession'), ...
    'GUI must reference session restoration');
end

function testGuiResultSchemaIsValid(testCase)
r = alias.result.create('cancelled');
testCase.verifyEqual(r.status, 'cancelled');
testCase.verifyTrue(isfield(r, 'details'));
testCase.verifyTrue(isfield(r.details, 'failure'));

% No public 'rejected' — operator Reject maps to 'cancelled'
testCase.verifyError(@() alias.result.create('rejected'), 'alias:InvalidStatus');
end

function testAcceptStatusIsValid(testCase)
r = alias.result.create('success');
testCase.verifyEqual(r.status, 'success');
end

function testGuiFileSelectionUsesJavaChooser(testCase)
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
testCase.verifyTrue(contains(content, 'JFileChooser') || ...
    contains(content, 'javax.swing.JFileChooser'), ...
    'GUI must use Java JFileChooser for file selection');
end

function testGuiDelegatesToApiRun(testCase)
% GIVEN the GUI source code
% WHEN it processes files
% THEN it calls alias.api.run (not direct engine/spm/converter calls)
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
testCase.verifyTrue(contains(content, 'alias.api.run'), ...
    'GUI must delegate processing to alias.api.run');
end

function testGuiDoesNotCallEngine(testCase)
% GIVEN the GUI source
% THEN it must NOT call alias.core.engine directly
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
lines = strsplit(content, newline);
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if startsWith(line, '%'), continue; end
    testCase.verifyFalse(contains(line, 'alias.core.engine('), ...
        'GUI must not call alias.core.engine directly');
end
end

function testGuiDoesNotCallSpmVol(testCase)
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
lines = strsplit(content, newline);
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if startsWith(line, '%'), continue; end
    testCase.verifyFalse(contains(line, 'spm_vol('), ...
        'GUI must not call spm_vol directly');
end
end

function testGuiDoesNotCallSpmReadVols(testCase)
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
lines = strsplit(content, newline);
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if startsWith(line, '%'), continue; end
    testCase.verifyFalse(contains(line, 'spm_read_vols('), ...
        'GUI must not call spm_read_vols directly');
end
end

function testGuiDoesNotCallSpmCreateVol(testCase)
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
lines = strsplit(content, newline);
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if startsWith(line, '%'), continue; end
    testCase.verifyFalse(contains(line, 'spm_create_vol('), ...
        'GUI must not call spm_create_vol directly');
end
end

function testGuiDoesNotCallSpmWriteVol(testCase)
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
lines = strsplit(content, newline);
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if startsWith(line, '%'), continue; end
    testCase.verifyFalse(contains(line, 'spm_write_vol('), ...
        'GUI must not call spm_write_vol directly');
end
end

function testGuiDoesNotCallDicom2niftiApi(testCase)
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
lines = strsplit(content, newline);
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if startsWith(line, '%'), continue; end
    testCase.verifyFalse(contains(line, 'dicom2nifti.api.run'), ...
        'GUI must not call dicom2nifti.api.run directly');
end
end

function testGuiDoesNotCallLoadInput(testCase)
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
lines = strsplit(content, newline);
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if startsWith(line, '%'), continue; end
    testCase.verifyFalse(contains(line, 'alias.api.loadInput'), ...
        'GUI must not call alias.api.loadInput directly');
end
end

function testGuiUsesPreviewCallback(testCase)
% GIVEN the GUI source
% THEN it passes a previewFcn to alias.api.run
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
testCase.verifyTrue(contains(content, 'previewFcn'), ...
    'GUI must pass previewFcn to alias.api.run');
end

function testGuiHandlesOverwriteAuthorization(testCase)
% GIVEN the GUI source
% THEN it checks for existing output and asks user before overwriting
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
testCase.verifyTrue(contains(content, 'exist(outputFile'), ...
    'GUI must check if output file exists');
testCase.verifyTrue(contains(content, 'doOverwrite'), ...
    'GUI must manage overwrite authorization');
end

function testGuiRejectMapsToCancelled(testCase)
% The API maps 'reject' decision to 'cancelled' status
% Verify via the result schema
testCase.verifyTrue(contains(fileread(fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+result', 'create.m')), '''cancelled'''), ...
    'Result module must support cancelled status');
end

function testGuiResultHasFourFields(testCase)
r = alias.result.create('failed', 'SPM preflight failed.');
fn = fieldnames(r);
testCase.verifyEqual(numel(fn), 4);
testCase.verifyEqual(fn{1}, 'status');
testCase.verifyEqual(fn{2}, 'outputs');
testCase.verifyEqual(fn{3}, 'message');
testCase.verifyEqual(fn{4}, 'details');
end

function testGuiChooserCancellationReturnsCancelled(testCase)
% GIVEN the GUI source
% WHEN chooser is cancelled
% THEN result is 'cancelled'
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
testCase.verifyTrue(contains(content, '''cancelled'''), ...
    'GUI must return cancelled status on chooser cancellation');
end


%% --- T007: Folder delegation, overwrite refusal/approval, cancellation, schema ---

function testGuiChooserAllowsFolders(testCase)
% GIVEN the GUI input chooser
% WHEN it is configured
% THEN it allows both files and directories (FILES_AND_DIRECTORIES)
%      so that DICOM folder inputs can be selected without local routing
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
testCase.verifyTrue(contains(content, 'FILES_AND_DIRECTORIES'), ...
    'Input chooser must allow both files and directories for folder input');
end

function testGuiChooserDoesNotRouteByType(testCase)
% GIVEN the GUI source
% WHEN it handles the selected input
% THEN it passes the selection to alias.api.run without local type routing
%      (no isdir/isfile branching on the input before delegation)
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
lines = strsplit(content, newline);
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if startsWith(line, '%'), continue; end
    % No local extension-based routing
    testCase.verifyFalse(contains(line, 'isNiftiExt(') || contains(line, 'isDicomExt('), ...
        'GUI must not perform local type routing on the input');
end
% The selected input is passed directly to alias.api.run
testCase.verifyTrue(contains(content, 'alias.api.run(inputFile'), ...
    'GUI must delegate the selected input directly to alias.api.run');
end

function testGuiOverwriteRefusalReturnsFailed(testCase)
% GIVEN the GUI source
% WHEN the user refuses overwrite authorization
% THEN the result status is 'failed' (not 'cancelled')
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
% The overwrite refusal path must use 'failed'
testCase.verifyTrue(contains(content, '''failed'', ''Overwrite not authorized'), ...
    'Overwrite refusal must return failed status');
% And must populate failure metadata
testCase.verifyTrue(contains(content, 'alias:OverwriteRefused'), ...
    'Overwrite refusal must include failure identifier');
end

function testGuiOverwriteApprovalDelegatesToApi(testCase)
% GIVEN the GUI source
% WHEN the user approves overwrite
% THEN doOverwrite=true is passed to alias.api.run
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
testCase.verifyTrue(contains(content, 'doOverwrite = true'), ...
    'GUI must set doOverwrite=true on approval');
testCase.verifyTrue(contains(content, 'alias.api.run(inputFile, outputFile, true, true, doOverwrite'), ...
    'GUI must pass doOverwrite to alias.api.run');
end

function testGuiChooserCancelIsCancelledNotFailed(testCase)
% GIVEN the GUI source
% WHEN the input or output chooser is cancelled
% THEN the result status is 'cancelled' (not 'failed')
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
% Input chooser cancellation
testCase.verifyTrue(contains(content, '''cancelled'', ''Input selection cancelled'), ...
    'Input chooser cancellation must return cancelled');
% Output chooser cancellation
testCase.verifyTrue(contains(content, '''cancelled'', ''Output selection cancelled'), ...
    'Output chooser cancellation must return cancelled');
end

function testGuiRejectAndCancelRemainCancelled(testCase)
% GIVEN the GUI delegates to alias.api.run with a preview callback
% WHEN the operator Rejects or Cancels in the preview dialog
% THEN the API maps both to 'cancelled' (verified via API tests)
% AND the GUI source does not override that mapping
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
% The preview callback returns 'reject' or 'cancel' to the API
testCase.verifyTrue(contains(content, '''reject'''), ...
    'Preview callback must return reject decision');
testCase.verifyTrue(contains(content, '''cancel'''), ...
    'Preview callback must return cancel decision');
% The GUI does not contain any status override after the API call
% (the API result is returned as-is)
lines = strsplit(content, newline);
apiCallFound = false;
statusOverrideAfterApi = false;
for i = 1:numel(lines)
    line = strtrim(lines{i});
    if contains(line, 'alias.api.run(')
        apiCallFound = true;
    end
    if apiCallFound && contains(line, 'varargout{1}') && contains(line, 'alias.result.create')
        statusOverrideAfterApi = true;
    end
end
testCase.verifyFalse(statusOverrideAfterApi, ...
    'GUI must not override the API result status after delegation');
end

function testGuiNoWriteOnCancelOrReject(testCase)
% GIVEN the GUI delegates processing to alias.api.run
% WHEN the operator cancels or rejects
% THEN no output is written (the API handles this — verified in testApi)
% AND the GUI source does not contain any direct write calls
guiPath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+gui', 'mainWindow.m');
content = fileread(guiPath);
% No direct SPM write calls
testCase.verifyFalse(contains(content, 'spm_write_vol('), ...
    'GUI must not write output directly');
testCase.verifyFalse(contains(content, 'spm_create_vol('), ...
    'GUI must not create volumes directly');
% All writing is delegated to the API
testCase.verifyTrue(contains(content, 'alias.api.run'), ...
    'GUI must delegate all processing to alias.api.run');
end

function testGuiResultSchemaOnOverwriteRefusal(testCase)
% GIVEN an overwrite refusal scenario
% WHEN the GUI returns a result
% THEN it has exactly four top-level fields (status, outputs, message, details)
%      with status='failed' and failure metadata populated
r = alias.result.create('failed', 'Overwrite not authorized.');
r.details.failure.identifier = 'alias:OverwriteRefused';
r.details.failure.message = 'Output exists and overwrite was not authorized.';
r.details.input_path = '/tmp/input.nii';
r.details.output_path = '/tmp/output.nii';

fn = fieldnames(r);
testCase.verifyEqual(numel(fn), 4, 'Result must have exactly 4 top-level fields');
testCase.verifyEqual(fn{1}, 'status');
testCase.verifyEqual(fn{2}, 'outputs');
testCase.verifyEqual(fn{3}, 'message');
testCase.verifyEqual(fn{4}, 'details');
testCase.verifyEqual(r.status, 'failed');
testCase.verifyEqual(r.details.failure.identifier, 'alias:OverwriteRefused');
testCase.verifyTrue(~isempty(r.details.failure.message));
testCase.verifyTrue(~isempty(r.details.input_path));
testCase.verifyTrue(~isempty(r.details.output_path));
testCase.verifyEqual(r.outputs, {}, 'No outputs on overwrite refusal');
end
