function tests = testSpmOverride
%TESTSPMOVERRIDE Tests for vers/spm_vol_nifti.m override behavior.
%   Verifies: valid caller spm_vol_nifti preserved (never shadowed);
%   missing caller helper → local override added and stays on path;
%   provenance records authority and override path.

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


%% --- Helpers ---

function markers = coreMarkers()
markers = {'spm_vol', 'spm_read_vols', 'spm_create_vol', ...
           'spm_write_vol', 'spm_type'};
end

function tmpDir = makeFakeSpmRoot(name, markerNames)
tmpDir = fullfile(tempdir, ['fake_ovr_' name]);
if exist(tmpDir, 'dir') == 7, rmdir(tmpDir, 's'); end
mkdir(tmpDir);
for i = 1:numel(markerNames)
    fid = fopen(fullfile(tmpDir, [markerNames{i} '.m']), 'w');
    fprintf(fid, 'function varargout = %s(varargin), end', markerNames{i});
    fclose(fid);
end
end

function cleanup = addCleanup(tmpDir)
cleanup = onCleanup(@() rmdir(tmpDir, 's'));
end


%% --- Valid caller spm_vol_nifti preserved ---

function testCallerSpmVolNiftiPreserved(testCase)
tmpDir = makeFakeSpmRoot('caller_with_nifti', ...
    [coreMarkers(), {'spm_vol_nifti'}]);
c = addCleanup(tmpDir);
addpath(tmpDir, '-begin');

beforeDir = pwd;

config = struct('spm_root', fullfile(tempdir, 'noexist_fb'), ...
                'log_level', 'info');
info = alias.spm.preflight(config);

testCase.verifyEqual(info.spm_authority, 'caller');
testCase.verifyTrue(isfield(info, 'spm_override_path'));
testCase.verifyTrue(isempty(info.spm_override_path), ...
    'Override path must be empty when caller already has spm_vol_nifti');

% Caller's spm_vol_nifti must still resolve
w = which('spm_vol_nifti');
testCase.verifyTrue(~isempty(w), 'Caller spm_vol_nifti must still be reachable');
testCase.verifyEqual(pwd, beforeDir);
end


%% --- Missing spm_vol_nifti → override added and stays on path ---

function testMissingSpmVolNiftiAddsOverride(testCase)
tmpDir = makeFakeSpmRoot('spm_no_nifti', coreMarkers());
c = addCleanup(tmpDir);

beforeDir = pwd;

config = struct('spm_root', tmpDir, 'log_level', 'info');
info = alias.spm.preflight(config);

testCase.verifyEqual(info.spm_authority, 'fallback');
testCase.verifyTrue(isfield(info, 'spm_override_path'));
testCase.verifyTrue(~isempty(info.spm_override_path), ...
    'Override path must be set when spm_vol_nifti is missing');

% Override must resolve on path
w = which('spm_vol_nifti');
testCase.verifyTrue(~isempty(w), ...
    'spm_vol_nifti must resolve after preflight adds override');
testCase.verifyEqual(pwd, beforeDir);
end


%% --- vers/spm_vol_nifti.m exists and has provenance ---

function testVersSpmVolNiftiExistsAndResolves(testCase)
projectRoot = testCase.TestData.ProjectRoot;
versDir = fullfile(projectRoot, 'vers');
testCase.verifyTrue(exist(versDir, 'dir') == 7);
testCase.verifyTrue(exist(fullfile(versDir, 'spm_vol_nifti.m'), 'file') == 2);

content = fileread(fullfile(versDir, 'spm_vol_nifti.m'));
testCase.verifyTrue(contains(content, 'PROVENANCE') || ...
    contains(content, 'origin') || contains(content, 'standalone'), ...
    'vers/spm_vol_nifti.m must contain provenance documentation');
end


%% --- Override never shadows a valid caller helper ---

function testOverrideNeverShadowsValidCaller(testCase)
tmpDir = makeFakeSpmRoot('caller_with_both', ...
    [coreMarkers(), {'spm_vol_nifti'}]);
c = addCleanup(tmpDir);
addpath(tmpDir, '-begin');

beforeDir = pwd;

config = struct('spm_root', fullfile(tempdir, 'noexist'), ...
                'log_level', 'info');
info = alias.spm.preflight(config);

testCase.verifyEqual(info.spm_authority, 'caller');
testCase.verifyTrue(isempty(info.spm_override_path), ...
    'Must NOT add override when caller has spm_vol_nifti');
testCase.verifyEqual(pwd, beforeDir);
end
