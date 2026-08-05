function tests = testSpmPreflight
%TESTSPAMPREFLIGHT Focused tests for SPM preflight validation.
%   On both success and failure, preflight restores path and CWD via
%   onCleanup. The caller is responsible for adding SPM to the path for
%   the duration of actual processing.

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
testCase.TestData.BaselinePath = path;
end

function teardownOnce(testCase)
path(testCase.TestData.OriginalPath);
if exist(testCase.TestData.OriginalDir, 'dir') == 7
    cd(testCase.TestData.OriginalDir);
end
end


function testMissingSpmRootConfigFailsClosed(testCase)
config = struct('spm_root', '', 'log_level', 'info');
beforePath = testCase.TestData.BaselinePath;
beforeDir = pwd;
f = @() alias.spm.preflight(config);
testCase.verifyError(f, 'alias:SpmRootMissing');
testCase.verifyEqual(path, beforePath);
testCase.verifyEqual(pwd, beforeDir);
end

function testSpmRootDirectoryMissingFails(testCase)
config = struct('spm_root', fullfile(tempdir, 'noexist_xyz_123'), 'log_level', 'info');
beforePath = testCase.TestData.BaselinePath;
beforeDir = pwd;
f = @() alias.spm.preflight(config);
testCase.verifyError(f, 'alias:SpmRootMissing');
testCase.verifyEqual(path, beforePath);
testCase.verifyEqual(pwd, beforeDir);
end

function testIncompleteSpmInstallFails(testCase)
tmpDir = fullfile(tempdir, 'fake_spm_incomplete');
if exist(tmpDir, 'dir') == 7, rmdir(tmpDir, 's'); end
mkdir(tmpDir);
fid = fopen(fullfile(tmpDir, 'spm_vol.m'), 'w');
fprintf(fid, 'function V = spm_vol(fname), V = struct(); end');
fclose(fid);
cleanup = onCleanup(@() rmdir(tmpDir, 's'));

beforePath = testCase.TestData.BaselinePath;
beforeDir = pwd;

config = struct('spm_root', tmpDir, 'log_level', 'info');
f = @() alias.spm.preflight(config);
testCase.verifyError(f, 'alias:SpmIncomplete');
testCase.verifyEqual(path, beforePath);
testCase.verifyEqual(pwd, beforeDir);
end

function testPreflightRestoresPathAndCwdOnFailure(testCase)
beforePath = testCase.TestData.BaselinePath;
beforeDir = pwd;

config = struct('spm_root', '', 'log_level', 'info');
try
    alias.spm.preflight(config);
catch
end

testCase.verifyEqual(path, beforePath);
testCase.verifyEqual(pwd, beforeDir);
end

function testValidSpmFixtureReturnsVersionAndRestoresState(testCase)
tmpDir = fullfile(tempdir, 'fake_spm_valid');
if exist(tmpDir, 'dir') == 7, rmdir(tmpDir, 's'); end
mkdir(tmpDir);

required = {'spm_vol', 'spm_read_vols', 'spm_write_vol', ...
            'spm_dicom_headers', 'spm_dicom_convert'};
for i = 1:numel(required)
    fid = fopen(fullfile(tmpDir, [required{i} '.m']), 'w');
    fprintf(fid, 'function varargout = %s(varargin), end', required{i});
    fclose(fid);
end
fid = fopen(fullfile(tmpDir, 'Contents.m'), 'w');
fprintf(fid, '%%%% SPM12 (7771)\nfunction c = Contents(), end');
fclose(fid);

cleanup = onCleanup(@() rmdir(tmpDir, 's'));

beforePath = testCase.TestData.BaselinePath;
beforeDir = pwd;

config = struct('spm_root', tmpDir, 'log_level', 'info');
info = alias.spm.preflight(config);

testCase.verifyClass(info, 'struct');
testCase.verifyTrue(isfield(info, 'spm_version'));
testCase.verifyTrue(~isempty(info.spm_version));
testCase.verifyTrue(isfield(info, 'spm_root'));
% Path and CWD must be restored
testCase.verifyEqual(path, beforePath);
testCase.verifyEqual(pwd, beforeDir);
end

function testSpmRootNotOnPathAfterSuccess(testCase)
% After preflight returns, SPM root must NOT remain on the path.
tmpDir = fullfile(tempdir, 'fake_spm_clean');
if exist(tmpDir, 'dir') == 7, rmdir(tmpDir, 's'); end
mkdir(tmpDir);
required = {'spm_vol', 'spm_read_vols', 'spm_write_vol', ...
            'spm_dicom_headers', 'spm_dicom_convert'};
for i = 1:numel(required)
    fid = fopen(fullfile(tmpDir, [required{i} '.m']), 'w');
    fprintf(fid, 'function varargout = %s(varargin), end', required{i});
    fclose(fid);
end
cleanup = onCleanup(@() rmdir(tmpDir, 's'));

beforePath = testCase.TestData.BaselinePath;

config = struct('spm_root', tmpDir, 'log_level', 'info');
info = alias.spm.preflight(config);

currentPath = path;
testCase.verifyFalse(contains(currentPath, info.spm_root), ...
    sprintf('Path should NOT contain SPM root "%s" after preflight', info.spm_root));
testCase.verifyEqual(path, beforePath);
end
