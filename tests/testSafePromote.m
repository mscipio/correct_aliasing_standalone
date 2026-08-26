function tests = testSafePromote
%TESTSAFEPROMOTE Tests for alias.util.safePromote.
%   Determistic fixtures including optional mover handle injection.

tests = functiontests(localfunctions);
end


function testSafePromoteSuccess(testCase)
tmpDir = tempname; mkdir(tmpDir);
c = onCleanup(@() rmdir(tmpDir, 's'));

staging = fullfile(tmpDir, 'stage.tmp');
final   = fullfile(tmpDir, 'final.nii');
fid = fopen(staging, 'w'); fprintf(fid, 'NEW'); fclose(fid);
fid = fopen(final, 'w');   fprintf(fid, 'OLD'); fclose(fid);

alias.util.safePromote(staging, final);

testCase.verifyTrue(exist(final, 'file') == 2);
fid = fopen(final, 'r'); content = fread(fid, inf, 'uint8=>char')'; fclose(fid);
testCase.verifyEqual(content, 'NEW');
testCase.verifyFalse(exist(staging, 'file') == 2, 'Staging removed');
testCase.verifyEmpty(dir(fullfile(tmpDir, 'tp*')));
end


function testMissingStagingThrows(testCase)
tmpDir = tempname; mkdir(tmpDir);
c = onCleanup(@() rmdir(tmpDir, 's'));
f = @() alias.util.safePromote(fullfile(tmpDir,'noexist.tmp'), fullfile(tmpDir,'final.nii'));
testCase.verifyError(f, 'alias:PromoteFailed');
testCase.verifyFalse(exist(fullfile(tmpDir,'final.nii'), 'file') == 2);
end


function testSafePromoteWithoutPrior(testCase)
tmpDir = tempname; mkdir(tmpDir);
c = onCleanup(@() rmdir(tmpDir, 's'));
staging = fullfile(tmpDir, 'stage.tmp');
final   = fullfile(tmpDir, 'final.nii');
fid = fopen(staging, 'w'); fprintf(fid, 'DATA'); fclose(fid);

alias.util.safePromote(staging, final);

testCase.verifyTrue(exist(final, 'file') == 2);
fid = fopen(final, 'r'); content = fread(fid, inf, 'uint8=>char')'; fclose(fid);
testCase.verifyEqual(content, 'DATA');
testCase.verifyFalse(exist(staging, 'file') == 2);
end


function testBackupFailureLeavesDestinationUntouched(testCase)
% Inject a mover that fails on the first call (backup) but works on
% the second (promotion). The backup failure must leave the original
% destination unchanged and delete staging.
tmpDir = tempname; mkdir(tmpDir);
c = onCleanup(@() rmdir(tmpDir, 's'));

staging = fullfile(tmpDir, 'stage.tmp');
final   = fullfile(tmpDir, 'final.nii');
fid = fopen(staging, 'w'); fprintf(fid, 'NEW'); fclose(fid);
fid = fopen(final, 'w');   fprintf(fid, 'OLD'); fclose(fid);

callCount = 0;
function [ok, msg] = failFirst(src, dst, flag)
    callCount = callCount + 1;
    if callCount == 1
        ok = false; msg = 'injected backup failure';
    else
        [ok, msg] = movefile(src, dst, flag);
    end
end

f = @() alias.util.safePromote(staging, final, @failFirst);
testCase.verifyError(f, 'alias:PromoteFailed');

% Destination must be untouched
testCase.verifyTrue(exist(final, 'file') == 2);
fid = fopen(final, 'r'); content = fread(fid, inf, 'uint8=>char')'; fclose(fid);
testCase.verifyEqual(content, 'OLD', 'Destination must be untouched');
% Staging must be cleaned
testCase.verifyFalse(exist(staging, 'file') == 2, 'Staging removed');
end


function testPromotionFailureRestoresPriorContent(testCase)
% Inject a mover that succeeds on backup but fails on promotion.
% The backup must be restored to final, staging removed, no artifacts.
tmpDir = tempname; mkdir(tmpDir);
c = onCleanup(@() rmdir(tmpDir, 's'));

staging = fullfile(tmpDir, 'stage.tmp');
final   = fullfile(tmpDir, 'final.nii');
fid = fopen(staging, 'w'); fprintf(fid, 'NEW'); fclose(fid);
fid = fopen(final, 'w');   fprintf(fid, 'OLD'); fclose(fid);

callCount = 0;
function [ok, msg] = failSecond(src, dst, flag)
    callCount = callCount + 1;
    if callCount == 2
        ok = false; msg = 'injected promotion failure';
    else
        [ok, msg] = movefile(src, dst, flag);
    end
end

f = @() alias.util.safePromote(staging, final, @failSecond);
testCase.verifyError(f, 'alias:PromoteFailed');

% Destination must have OLD content (restored from backup)
testCase.verifyTrue(exist(final, 'file') == 2);
fid = fopen(final, 'r'); content = fread(fid, inf, 'uint8=>char')'; fclose(fid);
testCase.verifyEqual(content, 'OLD', 'Destination must be restored to prior content');
% Staging removed
testCase.verifyFalse(exist(staging, 'file') == 2, 'Staging removed');
% No backup artifact
testCase.verifyEmpty(dir(fullfile(tmpDir, 'tp*')));
end
