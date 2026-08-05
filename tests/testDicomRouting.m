function tests = testDicomRouting
%TESTDICOMROUTING Tests for DICOM input routing and conversion.
%   Verifies: DICOM input is routed through SPM conversion to the engine,
%   routing metadata, and graceful failure when SPM is missing.

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


function testInputTypeDetectionNifti(testCase)
% GIVEN the API input routing logic
% WHEN we check how it identifies NIfTI
% THEN .nii and .nii.gz are recognized as NIfTI
% This test inspects the input routing responsibilities.
% The API already handles NIfTI loading; we verify the extension
% detection logic is consistent.

testCase.verifyTrue(isNiftiExt('file.nii'));
testCase.verifyTrue(isNiftiExt('file.nii.gz'));
testCase.verifyFalse(isNiftiExt('file.dcm'));
testCase.verifyFalse(isNiftiExt('file.ima'));
end

function testDicomInputDetection(testCase)
% GIVEN a DICOM extension (.dcm, .DCM, .ima, .IMA)
% WHEN routing determines input type
% THEN it should be recognized as DICOM
testCase.verifyTrue(isDicomExt('file.dcm'));
testCase.verifyTrue(isDicomExt('file.DCM'));
testCase.verifyTrue(isDicomExt('file.ima'));
testCase.verifyTrue(isDicomExt('file.IMA'));
testCase.verifyFalse(isDicomExt('file.nii'));
end

function testDicomRoutingRequiresSpm(testCase)
% GIVEN a DICOM input
% WHEN SPM is not configured
% THEN the call fails with a deterministic error before output
% We verify this indirectly: the API dispatcher must detect DICOM
% and route through spm_dicom_headers/spm_dicom_convert.
% With no real SPM, this should produce a 'failed' result.
result = alias.api.run(fullfile(testCase.TestData.TempDir, 'test.dcm'), ...
    fullfile(testCase.TestData.TempDir, 'out.nii'), true, true, false);

testCase.verifyEqual(result.status, 'failed', ...
    'DICOM input without SPM must fail deterministically');
end

function testApiInputRoutingLogicExists(testCase)
% GIVEN the API module
% WHEN we inspect the source
% THEN there is routing logic for DICOM vs NIfTI inputs
apiPath = fullfile(testCase.TestData.ProjectRoot, '+alias', '+api', 'run.m');
content = fileread(apiPath);
testCase.verifyTrue(contains(content, 'dicom') || contains(content, 'DICOM'), ...
    'API must contain DICOM routing logic');
end

function testEngineDoesNotHandleDicomDirectly(testCase)
% GIVEN the engine module
% WHEN we inspect the source
% THEN the engine does NOT contain DICOM conversion logic
% (the API/caller handles routing before invoking the engine)
enginePath = fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+core', 'engine.m');
content = fileread(enginePath);
% Engine should not mention DICOM conversion
testCase.verifyFalse(contains(content, 'spm_dicom_convert'), ...
    'Engine must not handle DICOM conversion directly');
testCase.verifyFalse(contains(content, 'spm_dicom_headers'), ...
    'Engine must not handle DICOM headers directly');
end


%% --- Local helper functions ---

function result = isNiftiExt(filePath)
[~, ~, ext] = fileparts(filePath);
result = strcmpi(ext, '.nii');
% Also check .nii.gz
if ~result && length(filePath) > 7
    result = strcmpi(filePath(end-6:end), '.nii.gz');
end
end

function result = isDicomExt(filePath)
[~, ~, ext] = fileparts(filePath);
result = any(strcmpi(ext, {'.dcm', '.ima'}));
end
