function tests = testResult
%TESTRESULT Tests for result structure and provenance capture.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(projectRoot);
testCase.TestData.ProjectRoot = projectRoot;
end


function testCreateReturnsFullSchema(testCase)
% GIVEN no special arguments
% WHEN create() is called
% THEN it returns a struct with all required scalar fields initialized
r = alias.result.create();

testCase.verifyClass(r, 'struct');
testCase.verifyTrue(ischar(r.status) && strcmp(r.status, 'success'));
testCase.verifyTrue(ischar(r.input));
testCase.verifyTrue(ischar(r.output));
testCase.verifyTrue(islogical(r.changed) && ~r.changed);

% Per-operation states
testCase.verifyTrue(isfield(r, 'alias_correction'));
testCase.verifyTrue(isstruct(r.alias_correction));
testCase.verifyTrue(isfield(r.alias_correction, 'performed'));
testCase.verifyFalse(r.alias_correction.performed);

testCase.verifyTrue(isfield(r, 'centering'));
testCase.verifyTrue(isstruct(r.centering));
testCase.verifyTrue(isfield(r.centering, 'performed'));
testCase.verifyFalse(r.centering.performed);

% Transform and provenance
testCase.verifyTrue(isfield(r, 'transform'));
testCase.verifyEqual(r.transform, eye(4));

testCase.verifyTrue(isfield(r, 'provenance'));
testCase.verifyTrue(isstruct(r.provenance));

% Error field
testCase.verifyTrue(isfield(r, 'error'));
testCase.verifyTrue(isstruct(r.error));
end

function testCreateWithStatusProducesGivenStatus(testCase)
% WHEN create('failed') is called
% THEN the status field matches
r = alias.result.create('failed');
testCase.verifyEqual(r.status, 'failed');

r2 = alias.result.create('rejected');
testCase.verifyEqual(r2.status, 'rejected');

r3 = alias.result.create('cancelled');
testCase.verifyEqual(r3.status, 'cancelled');
end

function testResultHasNoSharedReferences(testCase)
% GIVEN two independent creates
% WHEN one is mutated
% THEN the other is unchanged
a = alias.result.create();
b = alias.result.create();

a.status = 'cancelled';
a.changed = true;
a.alias_correction.performed = true;

testCase.verifyEqual(b.status, 'success');
testCase.verifyFalse(b.changed);
testCase.verifyFalse(b.alias_correction.performed);
end

function testProvenanceCaptureReturnsRequiredFields(testCase)
% GIVEN a project root
% WHEN capture() is called
% THEN it returns a struct with version, matlab_release, spm_version,
%      algorithm_id, and validation_status
p = alias.provenance.capture('SPM12 (7771)', testCase.TestData.ProjectRoot);

testCase.verifyClass(p, 'struct');
testCase.verifyTrue(isfield(p, 'version'));
testCase.verifyTrue(~isempty(p.version));
testCase.verifyTrue(isfield(p, 'matlab_release'));
testCase.verifyTrue(~isempty(p.matlab_release));
testCase.verifyTrue(isfield(p, 'spm_version'));
testCase.verifyEqual(p.spm_version, 'SPM12 (7771)');
testCase.verifyTrue(isfield(p, 'algorithm_id'));
testCase.verifyTrue(~isempty(p.algorithm_id));
testCase.verifyTrue(isfield(p, 'validation_status'));
testCase.verifyEqual(p.validation_status, 'unvalidated');
end

function testProvenanceVersionReadsVersionFile(testCase)
% GIVEN a temporary VERSION file in the project root
% WHEN capture() is called
% THEN version matches the file content
tmpProject = fullfile(tempdir, 'fake_proj_version');
if exist(tmpProject, 'dir') == 7, rmdir(tmpProject, 's'); end
mkdir(tmpProject);
fid = fopen(fullfile(tmpProject, 'VERSION'), 'w');
fprintf(fid, '0.2.0-alpha');
fclose(fid);
cleanup = onCleanup(@() rmdir(tmpProject, 's'));

p = alias.provenance.capture('SPM12', tmpProject);
testCase.verifyEqual(p.version, '0.2.0-alpha');
end

function testProvenanceMatlabReleaseIsNonempty(testCase)
p = alias.provenance.capture('any', testCase.TestData.ProjectRoot);
testCase.verifyClass(p.matlab_release, 'char');
testCase.verifyTrue(length(p.matlab_release) > 2, ...
    'MATLAB release string should be non-trivial');
end
