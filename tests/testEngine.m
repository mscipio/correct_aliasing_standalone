function tests = testEngine
%TESTENGINE Tests for the adapted alias correction and centering engine.
%   Uses synthetic volume fixtures with controlled affine matrices.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(projectRoot);
testCase.TestData.ProjectRoot = projectRoot;
end


%% --- Helper fixtures ---

function [volData, affine] = makeSyntheticVol(dims, voxSize)
% Build a centered head-like volume with clear edges and no wrap.
volData = zeros(dims, 'single');
centerI = round(dims(1) / 2);
centerJ = round(dims(2) / 2);
rJ = round(dims(2) * 0.35);
rI = round(dims(1) * 0.38);

for k = 1:dims(3)
    for j = 1:dims(2)
        for i = 1:dims(1)
            dist = sqrt(((j - centerJ) / rJ)^2 + ((i - centerI) / rI)^2);
            if dist < 1
                volData(i, j, k) = single(200 + 80 * (1 - dist));
            end
        end
    end
end

affine = diag([voxSize(1), voxSize(2), voxSize(3), 1]);
affine(1:3, 4) = -(dims .* voxSize) / 2;
end

function [volData, affine] = makeAliasedVol(dims, voxSize, cutPlane)
% Build a head-like volume then circularly rearrange at cutPlane
% to simulate the nose-to-back aliasing wrap pattern.
volCenter = zeros(dims, 'single');
centerI = round(dims(1) / 2);
centerJ = round(dims(2) / 2);
rJ = round(dims(2) * 0.30);
rI = round(dims(1) * 0.35);

for k = 1:dims(3)
    for j = 1:dims(2)
        for i = 1:dims(1)
            dist = sqrt(((j - centerJ) / rJ)^2 + ((i - centerI) / rI)^2);
            if dist < 1
                volCenter(i, j, k) = single(200 + 100 * (1 - dist));
            end
        end
    end
end

% Circularly rearrange: move planes cutPlane..end to beginning
volData = cat(2, volCenter(:, cutPlane:end, :), volCenter(:, 1:(cutPlane-1), :));

affine = diag([voxSize(1), voxSize(2), voxSize(3), 1]);
affine(1:3, 4) = -(dims .* voxSize) / 2;
end

function [volData, affine] = makeOffCenterVol(dims, voxSize, noseGap, backGap)
% Build a head-like volume with asymmetric edge gaps.
volData = zeros(dims, 'single');
centerI = round(dims(1) / 2);
centerJ = round(dims(2) / 2);
rJ = round(dims(2) * 0.35);
rI = round(dims(1) * 0.38);

for k = 1:dims(3)
    for j = 1:dims(2)
        for i = 1:dims(1)
            dist = sqrt(((j - centerJ) / rJ)^2 + ((i - centerI) / rI)^2);
            if dist < 1
                volData(i, j, k) = single(200 + 80 * (1 - dist));
            end
        end
    end
end

% Shift the volume along coronal axis to create asymmetric gaps
shift = (backGap - noseGap);
if shift > 0
    padBefore = zeros(dims(1), shift, dims(3), 'single');
    volData = cat(2, padBefore, volData(:, 1:(end-shift), :));
elseif shift < 0
    padAfter = zeros(dims(1), -shift, dims(3), 'single');
    volData = cat(2, volData(:, (-shift+1):end, :), padAfter);
end

affine = diag([voxSize(1), voxSize(2), voxSize(3), 1]);
affine(1:3, 4) = -(dims .* voxSize) / 2;
end


%% --- Tests ---

function testIdentityPassThrough(testCase)
[volData, affine] = makeSyntheticVol([64 64 32], [2 2 3]);
ops = struct('AliasCorrection', false, 'Centering', false);
result = alias.core.engine(volData, affine, ops);

testCase.verifyEqual(single(result.volData), single(volData));
testCase.verifyEqual(result.affine, affine);
testCase.verifyFalse(result.alias_corrected);
testCase.verifyFalse(result.centered);
end

function testAliasCorrectionDetectsCircularWrap(testCase)
[volData, affine] = makeAliasedVol([64 64 32], [2 2 3], 20);
ops = struct('AliasCorrection', true, 'Centering', false);
result = alias.core.engine(volData, affine, ops);

testCase.verifyTrue(result.alias_corrected, ...
    'Engine should detect aliasing in a wrapped volume');
testCase.verifyTrue(any(result.volData(:) ~= volData(:)), ...
    'Rearranged volume must differ from original');
testCase.verifyTrue(any(result.affine(:) ~= affine(:)), ...
    'Affine must be updated to reflect translation');
testCase.verifyTrue(abs(result.translation_mm) > 0, ...
    'Translation should be non-zero after correction');
testCase.verifyEqual(size(result.volData), size(volData));
end

function testCenteringOffCenterVolume(testCase)
[volData, affine] = makeOffCenterVol([64 64 32], [2 2 3], 5, 15);
ops = struct('AliasCorrection', false, 'Centering', true);
result = alias.core.engine(volData, affine, ops);

testCase.verifyTrue(result.centered, ...
    'Engine should center an off-center volume');
testCase.verifyTrue(any(result.volData(:) ~= volData(:)), ...
    'Shifted volume must differ from original');
testCase.verifyTrue(any(result.affine(:) ~= affine(:)), ...
    'Affine must be updated after centering');
testCase.verifyTrue(abs(result.shift_mm) > 0, ...
    'Shift should be non-zero');
testCase.verifyEqual(size(result.volData), size(volData));
end

function testAliasAndCenteringCombined(testCase)
[volData, affine] = makeAliasedVol([64 64 32], [2 2 3], 15);
ops = struct('AliasCorrection', true, 'Centering', true);
result = alias.core.engine(volData, affine, ops);

testCase.verifyTrue(result.alias_corrected || result.centered, ...
    'At least one correction should be applied');
testCase.verifyEqual(size(result.volData), size(volData));
end

function testSourceVolumeUnchanged(testCase)
[volData, affine] = makeAliasedVol([64 64 32], [2 2 3], 20);
originalCopy = single(volData);
ops = struct('AliasCorrection', true, 'Centering', true);
alias.core.engine(volData, affine, ops);

testCase.verifyEqual(single(volData), originalCopy, ...
    'Input volume must not be mutated by the engine');
end

function testNoCorrectionWhenNotNeeded(testCase)
[volData, affine] = makeSyntheticVol([64 64 32], [2 2 3]);
ops = struct('AliasCorrection', true, 'Centering', true);
result = alias.core.engine(volData, affine, ops);

testCase.verifyFalse(result.alias_corrected, ...
    'Unaliased volume should not trigger alias correction');
testCase.verifyEqual(single(result.volData), single(volData), ...
    'No-correction path should return original data unchanged');
testCase.verifyEqual(result.affine, affine);
end

function testOutputDimensionsMatchInput(testCase)
dimsList = {[32 32 16], [64 64 32], [128 128 64], [96 80 48]};
voxList = {[3 3 4], [2 2 3], [1 1 1.5], [1.5 1.5 2]};

for idx = 1:numel(dimsList)
    [volData, affine] = makeSyntheticVol(dimsList{idx}, voxList{idx});
    ops = struct('AliasCorrection', true, 'Centering', true);
    result = alias.core.engine(volData, affine, ops);
    testCase.verifyEqual(size(result.volData), dimsList{idx}, ...
        sprintf('Dimensions must match for test case %d', idx));
end
end

function testEnginePreservesDataType(testCase)
[volData, affine] = makeAliasedVol([64 64 32], [2 2 3], 20);
ops = struct('AliasCorrection', true, 'Centering', false);
result = alias.core.engine(volData, affine, ops);

testCase.verifyClass(result.volData, 'single');
end
