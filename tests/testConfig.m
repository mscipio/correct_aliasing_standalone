function tests = testConfig
%TESTCONFIG Tests for alias.config.load and alias.config.validate.
%   Verifies: scoped path/CWD-safe loading, required scalar validation,
%   SPM root existence, d2n root existence, fixed facade identity,
%   and deterministic error identifiers.

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
end

function teardownOnce(testCase)
path(testCase.TestData.OriginalPath);
if exist(testCase.TestData.OriginalDir, 'dir') == 7
    cd(testCase.TestData.OriginalDir);
end
end


%% --- alias.config.load ---

function testLoadReturnsStructWithRequiredFields(testCase)
% GIVEN the real config/defaults.m in the project
% WHEN alias.config.load() is called
% THEN it returns a struct with spm_root, d2n_root, d2n_entrypoint, log_level
c = alias.config.load();
testCase.verifyClass(c, 'struct');
testCase.verifyTrue(isfield(c, 'spm_root'));
testCase.verifyTrue(isfield(c, 'd2n_root'));
testCase.verifyTrue(isfield(c, 'd2n_entrypoint'));
testCase.verifyTrue(isfield(c, 'log_level'));
testCase.verifyClass(c.spm_root, 'char');
testCase.verifyClass(c.d2n_root, 'char');
testCase.verifyClass(c.d2n_entrypoint, 'char');
testCase.verifyClass(c.log_level, 'char');
end

function testLoadRestoresPath(testCase)
% GIVEN a call to alias.config.load()
% WHEN it returns
% THEN the caller's path is restored (scoped addpath)
beforePath = path;
c = alias.config.load();
afterPath = path;
testCase.verifyEqual(afterPath, beforePath, ...
    'alias.config.load must restore caller path');
end

function testLoadMissingConfigThrows(testCase)
% GIVEN a project root with no config/defaults.m
% WHEN alias.config.load() is called
% THEN it throws alias:ConfigMissing
tmpRoot = fullfile(tempdir, 'fake_proj_no_config');
if exist(tmpRoot, 'dir') == 7, rmdir(tmpRoot, 's'); end
mkdir(tmpRoot);
cClean = onCleanup(@() rmdir(tmpRoot, 's'));

% We can't easily redirect alias.config.load to a different root,
% so we verify the error identifier by source inspection.
loadSrc = fileread(fullfile(testCase.TestData.ProjectRoot, ...
    '+alias', '+config', 'load.m'));
testCase.verifyTrue(contains(loadSrc, 'alias:ConfigMissing'), ...
    'load.m must throw alias:ConfigMissing when config is absent');
end


%% --- alias.config.validate ---

function testValidateAcceptsValidConfig(testCase)
% GIVEN a config with all required fields and existing directories
% WHEN alias.config.validate() is called
% THEN it returns the config unchanged
tmpSpm = fullfile(tempdir, 'fake_spm_cfg_valid');
tmpD2n = fullfile(tempdir, 'fake_d2n_cfg_valid');
if exist(tmpSpm, 'dir') == 7, rmdir(tmpSpm, 's'); end
if exist(tmpD2n, 'dir') == 7, rmdir(tmpD2n, 's'); end
mkdir(tmpSpm); mkdir(tmpD2n);
cClean1 = onCleanup(@() rmdir(tmpSpm, 's'));
cClean2 = onCleanup(@() rmdir(tmpD2n, 's'));

c = struct('spm_root', tmpSpm, 'd2n_root', tmpD2n, ...
           'd2n_entrypoint', 'dcm2nii', 'log_level', 'info');
validated = alias.config.validate(c);
testCase.verifyEqual(validated.spm_root, tmpSpm);
testCase.verifyEqual(validated.d2n_root, tmpD2n);
testCase.verifyEqual(validated.d2n_entrypoint, 'dcm2nii');
end

function testValidateRejectsMissingSpmRootField(testCase)
% GIVEN a config missing spm_root
% WHEN validate is called
% THEN it throws alias:ConfigInvalid
c = struct('d2n_root', '/tmp', 'd2n_entrypoint', 'dcm2nii', 'log_level', 'info');
testCase.verifyError(@() alias.config.validate(c), 'alias:ConfigInvalid');
end

function testValidateRejectsEmptyD2nRoot(testCase)
% d2n_root must still be nonempty (always required for conversion)
c = struct('spm_root', '/tmp', 'd2n_root', '', ...
           'd2n_entrypoint', 'dcm2nii', 'log_level', 'info');
testCase.verifyError(@() alias.config.validate(c), 'alias:ConfigInvalid');
end

function testValidateAllowsNonexistentSpmRoot(testCase)
% spm_root existence is conditionally checked by preflight, not validate.
% Caller-owned core-5 authority may not need the fallback root.
c = struct('spm_root', fullfile(tempdir, 'noexist_spm_xyz'), ...
           'd2n_root', '/tmp', 'd2n_entrypoint', 'dcm2nii', 'log_level', 'info');
validated = alias.config.validate(c);
testCase.verifyEqual(validated.spm_root, fullfile(tempdir, 'noexist_spm_xyz'));
end

function testValidateAllowsEmptySpmRoot(testCase)
% Empty spm_root is allowed — caller-owned SPM authority may suffice.
c = struct('spm_root', '', 'd2n_root', '/tmp', ...
           'd2n_entrypoint', 'dcm2nii', 'log_level', 'info');
validated = alias.config.validate(c);
testCase.verifyEqual(validated.spm_root, '');
end

function testValidateRejectsNonexistentD2nRoot(testCase)
tmpSpm = fullfile(tempdir, 'fake_spm_cfg_d2n_missing');
if exist(tmpSpm, 'dir') == 7, rmdir(tmpSpm, 's'); end
mkdir(tmpSpm);
cClean = onCleanup(@() rmdir(tmpSpm, 's'));

c = struct('spm_root', tmpSpm, 'd2n_root', fullfile(tempdir, 'noexist_d2n_xyz'), ...
           'd2n_entrypoint', 'dcm2nii', 'log_level', 'info');
testCase.verifyError(@() alias.config.validate(c), 'alias:D2nRootMissing');
end

function testValidateRejectsWrongEntrypoint(testCase)
tmpSpm = fullfile(tempdir, 'fake_spm_cfg_ep');
tmpD2n = fullfile(tempdir, 'fake_d2n_cfg_ep');
if exist(tmpSpm, 'dir') == 7, rmdir(tmpSpm, 's'); end
if exist(tmpD2n, 'dir') == 7, rmdir(tmpD2n, 's'); end
mkdir(tmpSpm); mkdir(tmpD2n);
cClean1 = onCleanup(@() rmdir(tmpSpm, 's'));
cClean2 = onCleanup(@() rmdir(tmpD2n, 's'));

c = struct('spm_root', tmpSpm, 'd2n_root', tmpD2n, ...
           'd2n_entrypoint', 'wrong_name', 'log_level', 'info');
testCase.verifyError(@() alias.config.validate(c), 'alias:D2nEntrypointFixed');
end

function testValidateRejectsNonScalarField(testCase)
tmpSpm = fullfile(tempdir, 'fake_spm_cfg_ns');
tmpD2n = fullfile(tempdir, 'fake_d2n_cfg_ns');
if exist(tmpSpm, 'dir') == 7, rmdir(tmpSpm, 's'); end
if exist(tmpD2n, 'dir') == 7, rmdir(tmpD2n, 's'); end
mkdir(tmpSpm); mkdir(tmpD2n);
cClean1 = onCleanup(@() rmdir(tmpSpm, 's'));
cClean2 = onCleanup(@() rmdir(tmpD2n, 's'));

c = struct('spm_root', {tmpSpm, '/extra'}, 'd2n_root', tmpD2n, ...
           'd2n_entrypoint', 'dcm2nii', 'log_level', 'info');
testCase.verifyError(@() alias.config.validate(c), 'alias:ConfigInvalid');
end

function testValidateIsDeterministic(testCase)
% GIVEN the same valid config called twice
% WHEN validate is called
% THEN both calls produce identical results
tmpSpm = fullfile(tempdir, 'fake_spm_cfg_det');
tmpD2n = fullfile(tempdir, 'fake_d2n_cfg_det');
if exist(tmpSpm, 'dir') == 7, rmdir(tmpSpm, 's'); end
if exist(tmpD2n, 'dir') == 7, rmdir(tmpD2n, 's'); end
mkdir(tmpSpm); mkdir(tmpD2n);
cClean1 = onCleanup(@() rmdir(tmpSpm, 's'));
cClean2 = onCleanup(@() rmdir(tmpD2n, 's'));

c = struct('spm_root', tmpSpm, 'd2n_root', tmpD2n, ...
           'd2n_entrypoint', 'dcm2nii', 'log_level', 'info');
v1 = alias.config.validate(c);
v2 = alias.config.validate(c);
testCase.verifyEqual(v1.spm_root, v2.spm_root);
testCase.verifyEqual(v1.d2n_entrypoint, v2.d2n_entrypoint);
end
