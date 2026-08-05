function result = engine(volData, affine, ops)
%ENGINE Adapted alias correction and centering core.
%   result = alias.core.engine(volData, affine, ops)
%
%   Performs nose-to-back alias correction and/or centering on a 3-D
%   volume using the adapted legacy algorithm. Operates on in-memory data;
%   SPM I/O is handled by the caller.
%
%   Input:
%     volData  — 3-D numeric array (single or double)
%     affine   — 4×4 affine transformation matrix
%     ops      — struct with fields:
%                  .AliasCorrection  (logical)
%                  .Centering        (logical)
%
%   Output:
%     result   — struct with fields:
%                  .volData         — corrected 3-D volume
%                  .affine          — updated 4×4 affine
%                  .alias_corrected — logical
%                  .centered        — logical
%                  .translation_mm  — alias correction translation (mm)
%                  .shift_mm        — centering shift (mm)

result = struct();
result.volData = volData;
result.affine = affine;
result.alias_corrected = false;
result.centered = false;
result.translation_mm = 0;
result.shift_mm = 0;

dims = size(volData);

% --- Detect axes from affine ---
[ax, sag, cor] = detectAxes(affine);

% --- Alias correction ---
if ops.AliasCorrection
    [result.volData, result.affine, result.alias_corrected, ...
        result.translation_mm] = correctAlias(result.volData, result.affine, ...
        dims, ax, sag, cor);
end

% --- Centering (on possibly alias-corrected data) ---
if ops.Centering
    [result.volData, result.affine, result.centered, ...
        result.shift_mm] = centerSubject(result.volData, result.affine, ...
        dims, ax, sag, cor);
end
end


function [ax, sag, cor] = detectAxes(affine)
% Detect axial, sagittal, and coronal axes from the affine matrix.
% Returns axis indices (1, 2, or 3) for each orientation.
[~, pos] = max(abs(affine(1:3, 1:3)), [], 1);
ax = find(pos == 3, 1);   % axial (max along dim 3)
sag = find(pos == 1, 1);  % sagittal (max along dim 1)
cor = find(pos == 2, 1);  % coronal (max along dim 2)
% If pos has duplicates, prefer defaults
if isempty(ax), ax = 3; end
if isempty(sag), sag = 1; end
if isempty(cor), cor = 2; end
end


function [volOut, affOut, corrected, translationMm] = correctAlias(volIn, affIn, dims, ax, sag, cor)
% Detect nose-back aliasing and perform circular rearrangement.
% Adapted from automatic_anti_aliasing_nose_2_back.m.
volOut = volIn;
affOut = affIn;
corrected = false;
translationMm = 0;

thresAliasing = 2;  % planes threshold for detection

% Compute maximum intensity projection along axial axis
projAxial = squeeze(max(volIn, [], ax));

% Compute edge map using gradient-based edge detection
ed = gradientEdge(projAxial);

% Sum edges along sagittal direction (ear-to-ear)
sumCol = sum(ed, sag);
sumCol = sumCol(:);

% Find first and last non-zero edge rows
edgeRows = find(sumCol > 1);
if isempty(edgeRows)
    return;  % no edges detected — no aliasing
end

distNose = edgeRows(1) - 1;  % gap from start to first edge
distBack = dims(cor) - edgeRows(end);  % gap from last edge to end

% Check if nose-back distances indicate aliasing
if distNose >= thresAliasing || distBack >= thresAliasing
    return;  % gaps are large enough — no wrap detected
end

% Flip coronal axis if needed (nose-back direction check)
flipNb = 0;
p1 = affIn \ [0; 0; 0; 1];
p2 = affIn \ [0; 100; 0; 1];
dd = p2(cor) - p1(cor);
if dd > 0
    flipNb = 1;
    volOut = flip(volOut, cor);
end

% Find cut plane using zero-edge method or gradient-based fallback
cutPlane = findCutPlane(sumCol, volIn, dims, ax, sag, cor);

if cutPlane >= dims(cor)
    % Cut plane at end — try gradient-based approach
    axProj = squeeze(max(volIn, [], ax));
    gradSmooth = imsmooth(axProj, 2);
    sumSag = sum(gradSmooth, sag);
    sumSag = sumSag(:) / dims(sag);
    c = conv(sumSag, [1 -2 1], 'same');
    c = c(1:end-1);
    [~, locs] = findpeaks(c);
    if isempty(locs)
        cutPlane = round(dims(cor) / 2);  % fallback
    else
        cutPlane = locs(end);
    end
end

if cutPlane <= 1 || cutPlane >= dims(cor)
    return;  % invalid cut plane
end

% Compute voxel displacement and translation in mm
voxDisp = dims(cor) - cutPlane + 1;
voxSize = abs(affIn(cor, cor));
if voxSize == 0, voxSize = 1; end
translationMm = voxDisp * voxSize;

% Circular rearrangement of the volume
% Reorder axes to [sag, cor, ax] for easy slicing
[~, permOrder] = sort([sag, cor, ax]);
% permOrder maps [sag cor ax] positions

% Build permuted volume indices
newOrder = [sag, cor, ax];
% Permute to [sag cor ax] order
volP = permute(volOut, newOrder);
% Dimensions in permuted order
permDims = size(volP);  % [d_sag, d_cor, d_ax]

% Circular shift: move cut plane to start
initPlane = 0;
if sumCol(1) == 0, initPlane = 1; end
% Rearrange along coronal dimension (dim 2 in permuted volume)
volPOut = cat(2, ...
    volP(:, 1:initPlane, :), ...
    volP(:, cutPlane:end, :), ...
    volP(:, (initPlane + 1):(cutPlane - 1), :));

% Un-permute
[~, invOrder] = sort(newOrder);
volOut = permute(volPOut, invOrder);

% Update affine: translation opposite to the displacement
params = zeros(1, 3);
params(cor) = -translationMm;
if flipNb, params(cor) = translationMm; end

T = spmMatrix(params, 'Z*S*R*T');
affOut = affIn * T;
corrected = true;
end


function [volOut, affOut, centered, shiftMm] = centerSubject(volIn, affIn, dims, ax, sag, cor)
% Center the subject in the FOV using head-edge detection.
% Adapted from center_subject_in_image.m.
volOut = volIn;
affOut = affIn;
centered = false;
shiftMm = 0;

thres = 5;  % minimum plane difference to trigger centering

% Compute axial projection for edge detection
projAxial = squeeze(max(volIn, [], ax));
ed = gradientEdge(projAxial);
sumCol = sum(ed, sag);
sumCol = sumCol(:);

edgeRows = find(sumCol > 1);
if isempty(edgeRows)
    return;
end

distNose = edgeRows(1) - 1;
distBack = dims(cor) - edgeRows(end);

% Check if centering is needed (asymmetric gaps > threshold)
if abs(distBack - distNose) <= thres
    return;
end

% Compute voxel displacement: half the difference
voxDisp = round(abs(distNose - distBack) / 2);
if voxDisp <= 0
    return;
end

voxSize = abs(affIn(cor, cor));
if voxSize == 0, voxSize = 1; end
shiftMm = voxDisp * voxSize;

% Permute to [sag cor ax] order
newOrder = [sag, cor, ax];
volP = permute(volOut, newOrder);

% Circular shift along coronal dimension
switch sign(distBack - distNose)
    case 1
        % More space at back: shift toward nose
        volPOut = cat(2, ...
            volP(:, (end - voxDisp + 1):end, :), ...
            volP(:, 1:(end - voxDisp), :));
        params = zeros(1, 3);
        params(2) = shiftMm;
    case -1
        % More space at nose: shift toward back
        volPOut = cat(2, ...
            volP(:, (voxDisp + 1):end, :), ...
            volP(:, 1:voxDisp, :));
        params = zeros(1, 3);
        params(2) = -shiftMm;
    otherwise
        return;
end

% Un-permute
[~, invOrder] = sort(newOrder);
volOut = permute(volPOut, invOrder);

% Update affine: pre-multiplication for centering
T = spmMatrix(params, 'Z*S*R*T');
affOut = T * affIn;
centered = true;
end


function T = spmMatrix(params, seq)
%SPMMATRIX Minimal affine construction matching spm_matrix behavior.
%   T = spmMatrix(params, seq)
%   params: [tx ty tz] translations in mm (params are in mm)
%   seq: ignored, we only apply translation for simplicity
%
%   This is a minimal replacement for SPM's spm_matrix to avoid the
%   dependency on SPM at the engine level. The caller ensures SPM is
%   on path for I/O operations.
T = eye(4);
T(1:3, 4) = params(:);
end


function cutPlane = findCutPlane(sumCol, volIn, dims, ax, sag, cor)
% Find the cut plane for alias correction using edge + intensity methods.
% Adapted from automatic_anti_aliasing_nose_2_back.m.

% Method 1: zero-edge method
edgesZ = sumCol(1:end-1);
zeroEdges = find(edgesZ == 0);
zeroEdges = zeroEdges(zeroEdges > dims(cor) / 2);
if ~isempty(zeroEdges)
    cutPlane = round(mean(zeroEdges));
    return;
end

% Method 2: classical intensity-based
axProj = squeeze(max(volIn, [], ax));
sumSag = squeeze(sum(axProj, sag));
sumSag = sumSag(:) / dims(sag);
[~, posMax] = max(sumSag);
sumCol2 = sumSag;
sumCol2(1:posMax) = posMax;
[~, posMini] = min(sumCol2);
cutPlane = posMini;
end


function ed = gradientEdge(im)
%GRADIENTEDGE Simple gradient-based edge detection.
%   No toolbox dependency. Uses central differences and threshold.
%   im: 2-D image (double or single)

im = double(im);
% Normalize
if range(im(:)) > 0
    im = (im - min(im(:))) / range(im(:));
end

% Gradient magnitude
[gx, gy] = gradient(im);
gmag = sqrt(gx.^2 + gy.^2);

% Threshold at median-based level
thresh = 2 * median(gmag(:));
if thresh <= 0, thresh = 0.01; end
ed = double(gmag > thresh);
end


function out = imsmooth(im, sigma)
%IMSMOOTH Simple Gaussian-like smoothing (boxcar approximation).
%   No toolbox dependency. Uses repeated boxcar filtering.
im = double(im);
n = max(1, round(sigma * 2));
kernel = ones(n, n) / (n * n);
out = conv2(im, kernel, 'same');
end


function [pks, locs] = findpeaks(x)
%FINDPEAKS Simple peak finding for 1-D signals.
%   No toolbox dependency. Finds local maxima.
x = x(:);
n = length(x);
if n < 3
    pks = x;
    locs = (1:n)';
    return;
end
isPeak = false(n, 1);
for i = 2:(n - 1)
    if x(i) > x(i - 1) && x(i) > x(i + 1)
        isPeak(i) = true;
    end
end
locs = find(isPeak);
pks = x(locs);
% Sort by peak height descending
[pks, idx] = sort(pks, 'descend');
locs = locs(idx);
end
