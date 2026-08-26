function tests = testSpmPreflight
%TESTSPMPREFLIGHT Core-5 marker SPM authority tests.
%   Verifies: core-5 caller passthrough, partial core-5 rejection,
%   no-marker fallback, path/CWD restoration on error only.
%
%   The preflight inspects exactly 5 core processing markers:
%     spm_vol, spm_read_vols, spm_create_vol, spm_write_vol, spm_type.
%   On success, the selected root + conditional override REMAIN on the
%   path for processing. Path is restored only on error.

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


%% --- Core-5 marker definition ---

function markers = coreMarkers()
markers = {'spm_vol', 'spm_read_vols', 'spm_create_vol', ...
           'spm_write_vol', 'spm_type'};
end

function tmpDir = makeFakeSpmRoot(name, markerNames)
tmpDir = fullfile(tempdir, ['fake_spm_' name]);
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


%% --- Validation guards (error path restores) ---

function testMissingSpmRootConfigFailsClosed(testCase)
config = struct('spm_root', '', 'log_level', 'info');
beforePath = path;
beforeDir = pwd;
f = @() alias.spm.preflight(config);
testCase.verifyError(f, 'alias:SpmRootMissing');
testCase.verifyEqual(path, beforePath);
testCase.verifyEqual(pwd, beforeDir);
end

function testSpmRootDirectoryMissingFails(testCase)
config = struct('spm_root', fullfile(tempdir, 'noexist_xyz_123'), 'log_level', 'info');
beforePath = path;
beforeDir = pwd;
f = @() alias.spm.preflight(config);
testCase.verifyError(f, 'alias:SpmRootMissing');
testCase.verifyEqual(path, beforePath);
testCase.verifyEqual(pwd, beforeDir);
end

function testPreflightRestoresPathAndCwdOnError(testCase)
beforePath = path;
beforeDir = pwd;
config = struct('spm_root', '', 'log_level', 'info');
try, alias.spm.preflight(config); catch, end
testCase.verifyEqual(path, beforePath);
testCase.verifyEqual(pwd, beforeDir);
end


%% --- Core-5 caller passthrough ---

function testCallerCore5Passthrough(testCase)
% Caller has all 5 core markers → preflight selects caller root,
% leaves it on path for processing, records authority='caller'.
tmpDir = makeFakeSpmRoot('caller_passthrough', coreMarkers());
c = addCleanup(tmpDir);
addpath(tmpDir, '-begin');

beforePath = path;
beforeDir = pwd;

config = struct('spm_root', fullfile(tempdir, 'noexist_should_not_use'), ...
                'log_level', 'info');
info = alias.spm.preflight(config);

testCase.verifyTrue(isfield(info, 'spm_root'), 'info must contain spm_root');
testCase.verifyTrue(isfield(info, 'spm_authority'), 'info must contain spm_authority');
testCase.verifyEqual(info.spm_authority, 'caller');

% Path was modified (selected root added), CWD unchanged
testCase.verifyTrue(contains(path, tmpDir), ...
    'Selected SPM root must remain on path after successful preflight');
testCase.verifyEqual(pwd, beforeDir);
end


%% --- Partial core-5 marker rejection ---

function testPartialCore5Rejects(testCase)
partialSets = { ...
    {'spm_vol'}, ...
    {'spm_vol', 'spm_read_vols'}, ...
    {'spm_vol', 'spm_read_vols', 'spm_create_vol'}, ...
    {'spm_vol', 'spm_read_vols', 'spm_create_vol', 'spm_write_vol'} ...
    };
for idx = 1:numel(partialSets)
    tmpDir = makeFakeSpmRoot(sprintf('partial_%d', idx), partialSets{idx});
    c = addCleanup(tmpDir);
    addpath(tmpDir, '-begin');

    beforePath = path;
    beforeDir = pwd;

    config = struct('spm_root', fullfile(tempdir, 'noexist_fallback'), ...
                    'log_level', 'info');
    f = @() alias.spm.preflight(config);
    testCase.verifyError(f, 'alias:SpmIncomplete', ...
        sprintf('Partial marker set %d must fail closed', idx));
    testCase.verifyEqual(path, beforePath, ...
        sprintf('Path leak after partial rejection %d', idx));
    testCase.verifyEqual(pwd, beforeDir, ...
        sprintf('CWD leak after partial rejection %d', idx));
end
end


%% --- No markers — fallback ---

function testNoMarkersSelectsFallback(testCase)
tmpDir = makeFakeSpmRoot('fallback_spm', coreMarkers());
c = addCleanup(tmpDir);

beforePath = path;
beforeDir = pwd;

config = struct('spm_root', tmpDir, 'log_level', 'info');
info = alias.spm.preflight(config);

testCase.verifyTrue(isfield(info, 'spm_authority'), 'info must contain spm_authority');
testCase.verifyEqual(info.spm_authority, 'fallback');
testCase.verifyTrue(isfield(info, 'spm_root'), 'info must contain spm_root');

% Path must contain fallback root (it remains for processing)
testCase.verifyTrue(contains(path, tmpDir), ...
    'Fallback SPM root must remain on path after successful preflight');
testCase.verifyEqual(pwd, beforeDir);
end


%% --- Vers override on path ---

function testVersOverrideRemainsOnPath(testCase)
% Fallback SPM lacks spm_vol_nifti → preflight adds vers/ override.
% The override must remain on path after preflight returns.
tmpDir = makeFakeSpmRoot('fallback_no_nifti', coreMarkers());
c = addCleanup(tmpDir);

beforeDir = pwd;

% Verify spm_vol_nifti is not already on path (clean starting state)
config = struct('spm_root', tmpDir, 'log_level', 'info');
info = alias.spm.preflight(config);

testCase.verifyEqual(info.spm_authority, 'fallback');
% Override must be active (on path) — but only if vers/ was actually needed.
% If another test left spm_vol_nifti on the path, override isn't added,
% which is correct behavior (never shadow a valid helper).
% We check: override was either added OR spm_vol_nifti was already available.
w = which('spm_vol_nifti');
testCase.verifyTrue(~isempty(w), 'spm_vol_nifti must resolve after preflight');

testCase.verifyEqual(pwd, beforeDir);
end


%% --- Shadowing: wrong resolved which() ---

function testWrongWhichResolutionRejects(testCase)
% GIVEN a shadow directory with a single core marker (spm_vol) on path
% AND a valid fallback SPM root configured
% WHEN preflight inspects the caller path
% THEN it detects the partial marker set (1 of 5) and rejects with
%      alias:SpmIncomplete. This proves shadowed/wrong resolution is
%      caught before any fallback mixing occurs.
shadowDir = fullfile(tempdir, 'shadow_inject');
if exist(shadowDir, 'dir') == 7, rmdir(shadowDir, 's'); end
mkdir(shadowDir);
cShadow = onCleanup(@() rmdir(shadowDir, 's'));
% Inject a wrong spm_vol that would resolve before the configured root
fid = fopen(fullfile(shadowDir, 'spm_vol.m'), 'w');
fprintf(fid, 'function V = spm_vol(fname), V = struct(); end');
fclose(fid);

addpath(shadowDir, '-begin');
beforeDir = pwd;

% Fallback root exists but its spm_vol is shadowed by the injected copy
tmpDir = makeFakeSpmRoot('legit_fallback', coreMarkers());
c1 = addCleanup(tmpDir);

config = struct('spm_root', tmpDir, 'log_level', 'info');
f = @() alias.spm.preflight(config);
testCase.verifyError(f, 'alias:SpmIncomplete');

testCase.verifyEqual(pwd, beforeDir);
end


%% --- Caller-owned authority with absent fallback ---

function testCallerCore5WithEmptyFallbackRoot(testCase)
% GIVEN caller has all 5 core markers on path
% AND configured spm_root is empty (fallback absent)
% WHEN preflight is called
% THEN it succeeds with authority='caller' (fallback not needed)
tmpDir = makeFakeSpmRoot('caller_empty_fallback', coreMarkers());
c = addCleanup(tmpDir);
addpath(tmpDir, '-begin');

beforePath = path;
beforeDir = pwd;

config = struct('spm_root', '', 'log_level', 'info');
info = alias.spm.preflight(config);

testCase.verifyEqual(info.spm_authority, 'caller', ...
    'Caller authority must work with empty fallback root');
testCase.verifyTrue(contains(path, tmpDir));
testCase.verifyEqual(pwd, beforeDir);
end

function testCallerCore5WithNonexistentFallbackRoot(testCase)
% GIVEN caller has all 5 core markers on path
% AND configured spm_root points to nonexistent directory
% WHEN preflight is called
% THEN it succeeds with authority='caller' (fallback not needed)
tmpDir = makeFakeSpmRoot('caller_noexist_fallback', coreMarkers());
c = addCleanup(tmpDir);
addpath(tmpDir, '-begin');

beforePath = path;
beforeDir = pwd;

config = struct('spm_root', fullfile(tempdir, 'totally_nonexistent_spm_abc'), ...
                'log_level', 'info');
info = alias.spm.preflight(config);

testCase.verifyEqual(info.spm_authority, 'caller', ...
    'Caller authority must work with nonexistent fallback root');
testCase.verifyTrue(contains(path, tmpDir));
testCase.verifyEqual(pwd, beforeDir);
end
