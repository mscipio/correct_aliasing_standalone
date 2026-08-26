function varargout = correct_aliasing(varargin)
%CORRECT_ALIASING Standalone MR aliasing correction and centering.
%   correct_aliasing()                         Launch operator GUI
%   result = correct_aliasing(inputPath, outputPath, ...
%       'AliasCorrection', true, 'Centering', true, 'Overwrite', false)
%       Run non-interactively, return structured result.
%
%   Explicit calls never create UI. The source file is never modified.

rootDir = fileparts(mfilename('fullpath'));
originalPath = path;
originalDir = pwd;
cleanup = onCleanup(@() restoreSession(originalPath, originalDir));
addpath(rootDir, '-begin');

if nargin == 0
    % GUI mode — return the GUI result when requested, never []
    if nargout > 0
        varargout{1} = alias.gui.mainWindow();
    else
        alias.gui.mainWindow();
    end
    return;
end

% --- Parse explicit arguments ---
p = inputParser;
p.addRequired('inputPath', @ischar);
p.addRequired('outputPath', @ischar);
p.addParameter('AliasCorrection', true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('Centering', true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('Overwrite', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));

try
    p.parse(varargin{:});
catch ME
    result = alias.result.create('failed', 'Invalid arguments.');
    result.details.failure.identifier = 'alias:InvalidArguments';
    result.details.failure.message = ME.message;
    % Preserve any supplied positional paths in normalized form
    [result.details.input_path, result.details.output_path] = extractPaths(varargin);
    if nargout > 0, varargout{1} = result; end
    return;
end

args = p.Results;
doAlias = logical(args.AliasCorrection);
doCenter = logical(args.Centering);
doOverwrite = logical(args.Overwrite);

result = alias.api.run(args.inputPath, args.outputPath, doAlias, doCenter, doOverwrite);

if nargout > 0
    varargout{1} = result;
end
end

function restoreSession(originalPath, originalDir)
path(originalPath);
if exist(originalDir, 'dir') == 7
    cd(originalDir);
end
end

function [inPath, outPath] = extractPaths(args)
% Pull the first two positional args if they look like paths.
inPath = ''; outPath = '';
if numel(args) >= 1 && ischar(args{1})
    inPath = normalize(args{1});
end
if numel(args) >= 2 && ischar(args{2})
    outPath = normalize(args{2});
end
end

function p = normalize(p)
if isempty(p), return; end
p = strtrim(p);
if isunix && p(1) == '~'
    p = fullfile(getenv('HOME'), p(2:end));
end
if isunix && p(1) == '/', return; end
if ispc && length(p) >= 2 && p(2) == ':', return; end
p = fullfile(pwd, p);
end
