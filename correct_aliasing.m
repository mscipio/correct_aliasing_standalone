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
    % GUI mode
    alias.gui.mainWindow();
    if nargout > 0
        varargout{1} = [];
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
    result = alias.result.create('failed');
    result.error.identifier = 'alias:InvalidArguments';
    result.error.message = ME.message;
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
