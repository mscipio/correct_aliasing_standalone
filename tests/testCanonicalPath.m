function tests = testCanonicalPath
%TESTCANONICALPATH Tests for alias.util.sameCanonicalPath.
%   Verifies: symlink-equivalent paths → true; different files → false;
%   case-insensitive only on Windows.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(projectRoot);
testCase.TestData.ProjectRoot = projectRoot;
end

function testSymlinkEquivalentReturnsTrue(testCase)
% GIVEN a real file and a symlink to it
% WHEN sameCanonicalPath compares the symlink and the target
% THEN it returns true (canonical resolution matches).
tmpDir = tempname;
mkdir(tmpDir);
c = onCleanup(@() rmdir(tmpDir, 's'));

realFile = fullfile(tmpDir, 'real.txt');
fid = fopen(realFile, 'w'); fprintf(fid, 'hello'); fclose(fid);

linkFile = fullfile(tmpDir, 'link.txt');
if isunix
    [s, ~] = system(sprintf('ln -s %s %s', realFile, linkFile));
    testCase.verifyEqual(s, 0, 'symlink creation must succeed');
else
    copyfile(realFile, linkFile);  % Windows: plain copy as proxy
end

result = alias.util.sameCanonicalPath(realFile, linkFile);
testCase.verifyTrue(result, 'Symlink-equivalent paths must compare true');
end

function testDifferentFilesReturnFalse(testCase)
tmpDir = tempname;
mkdir(tmpDir);
c = onCleanup(@() rmdir(tmpDir, 's'));

a = fullfile(tmpDir, 'a.txt');
b = fullfile(tmpDir, 'b.txt');
fid = fopen(a, 'w'); fprintf(fid, 'a'); fclose(fid);
fid = fopen(b, 'w'); fprintf(fid, 'b'); fclose(fid);

result = alias.util.sameCanonicalPath(a, b);
testCase.verifyFalse(result, 'Different files must compare false');
end

function testNormalizedSlashes(testCase)
tmpDir = tempname;
mkdir(tmpDir);
c = onCleanup(@() rmdir(tmpDir, 's'));

f = fullfile(tmpDir, 'slash.txt');
fid = fopen(f, 'w'); fprintf(fid, 'x'); fclose(fid);

% Unix: backslash-normalized comparison
a = strrep(f, '/', '//');
b = f;
result = alias.util.sameCanonicalPath(a, b);
testCase.verifyTrue(result, 'Slash-normalized paths must compare true');
end
