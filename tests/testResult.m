function tests = testResult
%TESTRESULT Tests for the unified public result shape.
%   Verifies: exactly four top-level fields (status, outputs, message, details),
%   status vocabulary (success|partial|failed|cancelled, no rejected),
%   details sub-fields, no shared state between results, and provenance capture.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(projectRoot);
testCase.TestData.ProjectRoot = projectRoot;
end


%% --- Public result shape ---

function testCreateReturnsExactFourFields(testCase)
% GIVEN a default result
% WHEN alias.result.create() is called
% THEN it has exactly four top-level fields in order: status, outputs, message, details
r = alias.result.create();
fn = fieldnames(r);
testCase.verifyEqual(numel(fn), 4, 'Result must have exactly 4 top-level fields');
testCase.verifyEqual(fn{1}, 'status');
testCase.verifyEqual(fn{2}, 'outputs');
testCase.verifyEqual(fn{3}, 'message');
testCase.verifyEqual(fn{4}, 'details');
end

function testCreateDefaultStatusIsSuccess(testCase)
r = alias.result.create();
testCase.verifyClass(r, 'struct');
testCase.verifyEqual(r.status, 'success');
testCase.verifyEqual(r.outputs, {});
testCase.verifyClass(r.message, 'char');
testCase.verifyClass(r.details, 'struct');
end

function testCreateWithMessage(testCase)
r = alias.result.create('failed', 'Something went wrong.');
testCase.verifyEqual(r.status, 'failed');
testCase.verifyEqual(r.message, 'Something went wrong.');
end

function testStatusVocabularyOnly(testCase)
% GIVEN the valid status vocabulary
% WHEN creating results with each valid status
% THEN each is accepted
for s = {'success', 'partial', 'failed', 'cancelled'}
    r = alias.result.create(s{1});
    testCase.verifyEqual(r.status, s{1});
end
end

function testInvalidStatusThrows(testCase)
% GIVEN an invalid status string
% WHEN create is called
% THEN it throws alias:InvalidStatus
testCase.verifyError(@() alias.result.create('rejected'), 'alias:InvalidStatus');
testCase.verifyError(@() alias.result.create('unknown'), 'alias:InvalidStatus');
end

function testNoPublicRejected(testCase)
% GIVEN the status vocabulary
% WHEN 'rejected' is passed
% THEN it throws — no public 'rejected'
testCase.verifyError(@() alias.result.create('rejected'), 'alias:InvalidStatus');
end


%% --- Details sub-fields ---

function testDetailsContainsAllRichFields(testCase)
r = alias.result.create();
d = r.details;

% Input/output paths
testCase.verifyTrue(isfield(d, 'input_path'));
testCase.verifyTrue(isfield(d, 'output_path'));
testCase.verifyTrue(isfield(d, 'changed'));
testCase.verifyFalse(d.changed);

% Operations (requested switches)
testCase.verifyTrue(isfield(d, 'operations'));
testCase.verifyTrue(isstruct(d.operations));
testCase.verifyTrue(isfield(d.operations, 'AliasCorrection'));
testCase.verifyFalse(d.operations.AliasCorrection);
testCase.verifyTrue(isfield(d.operations, 'Centering'));
testCase.verifyFalse(d.operations.Centering);

% Per-operation engine outcomes
testCase.verifyTrue(isfield(d, 'alias_correction'));
testCase.verifyTrue(isstruct(d.alias_correction));
testCase.verifyTrue(isfield(d.alias_correction, 'performed'));
testCase.verifyFalse(d.alias_correction.performed);

testCase.verifyTrue(isfield(d, 'centering'));
testCase.verifyTrue(isstruct(d.centering));
testCase.verifyTrue(isfield(d.centering, 'performed'));
testCase.verifyFalse(d.centering.performed);

% Transform
testCase.verifyTrue(isfield(d, 'transform'));
testCase.verifyTrue(isstruct(d.transform));
testCase.verifyTrue(isfield(d.transform, 'applied'));
testCase.verifyFalse(d.transform.applied);
testCase.verifyTrue(isfield(d.transform, 'rotation'));
testCase.verifyTrue(isfield(d.transform, 'translation'));
testCase.verifyTrue(isfield(d.transform, 'scale'));

% Provenance
testCase.verifyTrue(isfield(d, 'provenance'));
testCase.verifyTrue(isstruct(d.provenance));
testCase.verifyTrue(isfield(d.provenance, 'spm_authority'));
testCase.verifyTrue(isfield(d.provenance, 'spm_root'));
testCase.verifyTrue(isfield(d.provenance, 'spm_version'));
testCase.verifyTrue(isfield(d.provenance, 'spm_override_path'));
testCase.verifyTrue(isfield(d.provenance, 'd2n_root'));
testCase.verifyTrue(isfield(d.provenance, 'converter_route'));
testCase.verifyEqual(d.provenance.converter_route, '', ...
    'Default converter_route must be empty (set by run.m per call)');

% Failure
testCase.verifyTrue(isfield(d, 'failure'));
testCase.verifyTrue(isstruct(d.failure));
testCase.verifyTrue(isfield(d.failure, 'identifier'));
testCase.verifyTrue(isfield(d.failure, 'message'));
testCase.verifyTrue(isfield(d.failure, 'stack'));
testCase.verifyTrue(isfield(d.failure, 'cause'));
end

function testOutputsIsCellArray(testCase)
r = alias.result.create();
testCase.verifyClass(r.outputs, 'cell');
testCase.verifyEqual(numel(r.outputs), 0, 'Default outputs must be empty cell');
end

function testOutputsContainsCommittedPathsOnly(testCase)
r = alias.result.create('success');
r.outputs = {'/some/output.nii'};
testCase.verifyEqual(numel(r.outputs), 1);
testCase.verifyEqual(r.outputs{1}, '/some/output.nii');
end


%% --- No shared state ---

function testResultHasNoSharedReferences(testCase)
a = alias.result.create();
b = alias.result.create();
a.status = 'cancelled';
a.details.changed = true;
a.details.operations.AliasCorrection = true;
a.details.alias_correction.performed = true;
a.outputs = {'/a.nii'};
testCase.verifyEqual(b.status, 'success');
testCase.verifyFalse(b.details.changed);
testCase.verifyFalse(b.details.operations.AliasCorrection);
testCase.verifyFalse(b.details.alias_correction.performed);
testCase.verifyEqual(b.outputs, {});
end


%% --- Failure metadata ---

function testFailureMetadataFields(testCase)
r = alias.result.create('failed', 'Config error.');
r.details.failure.identifier = 'alias:ConfigInvalid';
r.details.failure.message = 'spm_root missing';
r.details.failure.stack = 'stack trace here';
r.details.failure.cause = '';
testCase.verifyEqual(r.details.failure.identifier, 'alias:ConfigInvalid');
testCase.verifyEqual(r.details.failure.message, 'spm_root missing');
testCase.verifyEqual(r.details.failure.stack, 'stack trace here');
end


%% --- Provenance capture (unchanged) ---

function testProvenanceCaptureReturnsRequiredFields(testCase)
p = alias.provenance.capture('SPM12 (7771)', testCase.TestData.ProjectRoot);
testCase.verifyClass(p, 'struct');
testCase.verifyTrue(isfield(p, 'version'));
testCase.verifyTrue(~isempty(p.version));
testCase.verifyTrue(isfield(p, 'matlab_release'));
testCase.verifyTrue(~isempty(p.matlab_release));
testCase.verifyTrue(isfield(p, 'spm_version'));
testCase.verifyEqual(p.spm_version, 'SPM12 (7771)');
testCase.verifyTrue(isfield(p, 'spm_authority'));
testCase.verifyTrue(isfield(p, 'spm_root'));
testCase.verifyTrue(isfield(p, 'algorithm_id'));
testCase.verifyTrue(~isempty(p.algorithm_id));
testCase.verifyTrue(isfield(p, 'validation_status'));
testCase.verifyEqual(p.validation_status, 'unvalidated');
end

function testProvenanceSpfInfoFieldsPopulated(testCase)
spmInfo = struct('spm_root', '/fake/spm/root', ...
                 'spm_authority', 'fallback', ...
                 'spm_version', 'SPM8', ...
                 'spm_override_path', '');
config = struct('d2n_root', '/fake/d2n/root');
p = alias.provenance.capture('SPM8', testCase.TestData.ProjectRoot, spmInfo, config);
testCase.verifyEqual(p.spm_root, '/fake/spm/root');
testCase.verifyEqual(p.spm_authority, 'fallback');
testCase.verifyEqual(p.d2n_root, '/fake/d2n/root');
testCase.verifyTrue(isempty(p.spm_override_path));
end

function testProvenanceVersionReadsVersionFile(testCase)
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
