function varargout = mainWindow()
%MAINWINDOW Operator GUI for alias correction and centering.
%   alias.gui.mainWindow()
%
%   Launches a programmatic MATLAB GUI with Java JFileChooser file
%   selection, preview display, and accept/reject/cancel decisions.
%   Path and CWD are restored on exit via onCleanup.
%
%   All processing (conversion, SPM read, engine, write) is delegated
%   to alias.api.run with an injected preview callback. The GUI owns
%   only chooser presentation, preview rendering, and decision interaction.
%
%   Output (when nargout > 0):
%     scalar struct with exactly four top-level fields:
%     status, outputs, message, details

rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
originalPath = path;
originalDir = pwd;
cleanup = onCleanup(@() restoreSession(originalPath, originalDir));
addpath(rootDir, '-begin');

% --- Step 1: Select input file ---
[inputFile, cancelled] = chooseInputFile();
if cancelled
    if nargout > 0
        r = alias.result.create('cancelled', 'Input selection cancelled.');
        varargout{1} = r;
    end
    return;
end

% --- Step 2: Select output file ---
[outputFile, cancelled] = chooseOutputFile(inputFile);
if cancelled
    if nargout > 0
        r = alias.result.create('cancelled', 'Output selection cancelled.');
        varargout{1} = r;
    end
    return;
end

% --- Step 2b: Reject source=destination ---
if alias.util.sameCanonicalPath(inputFile, outputFile)
    errordlg('Output must differ from the selected source file.', ...
        'Invalid Selection');
    if nargout > 0
        r = alias.result.create('failed', 'Output must differ from source.');
        r.details.failure.identifier = 'alias:InputOutputSame';
        r.details.failure.message = 'Output must differ from the selected source file.';
        r.details.input_path = inputFile;
        r.details.output_path = outputFile;
        varargout{1} = r;
    end
    return;
end

% --- Step 2c: Overwrite authorization ---
doOverwrite = false;
if exist(outputFile, 'file') == 2
    choice = questdlg( ...
        sprintf('Output file already exists:\n%s\n\nOverwrite?', outputFile), ...
        'Confirm Overwrite', 'Yes', 'No', 'No');
    if ~strcmp(choice, 'Yes')
        if nargout > 0
            r = alias.result.create('failed', 'Overwrite not authorized.');
            r.details.failure.identifier = 'alias:OverwriteRefused';
            r.details.failure.message = 'Output exists and overwrite was not authorized.';
            r.details.input_path = inputFile;
            r.details.output_path = outputFile;
            varargout{1} = r;
        end
        return;
    end
    doOverwrite = true;
end

% --- Step 3: Delegate all processing to the API with preview callback ---
opts = struct('previewFcn', @showPreviewAndDecide);

if nargout > 0
    varargout{1} = alias.api.run(inputFile, outputFile, true, true, doOverwrite, opts);
else
    alias.api.run(inputFile, outputFile, true, true, doOverwrite, opts);
end
end


function decision = showPreviewAndDecide(ctx)
% Preview callback injected into alias.api.run.
% Renders original vs corrected side-by-side and returns the operator decision.
% ctx has: originalVolData, originalAffine, processedVolData, processedAffine,
%           engineResult, inputPath, outputPath

volData = ctx.originalVolData;
volAffine = ctx.originalAffine;
engResult = ctx.engineResult;

f = figure('Name', 'Correct MR Aliasing — Preview', ...
    'NumberTitle', 'off', ...
    'Position', [200 200 900 450], ...
    'MenuBar', 'none', ...
    'ToolBar', 'none', ...
    'Resize', 'on');

% Original axial MIP
ax1 = subplot(1, 2, 1, 'Parent', f);
[~, pos] = max(abs(volAffine(1:3, 1:3)), [], 1);
axDim = find(pos == 3, 1);
if isempty(axDim), axDim = 3; end
mipOrig = squeeze(max(volData, [], axDim));
imagesc(mipOrig, 'Parent', ax1);
title(ax1, 'Original');
axis(ax1, 'image');
colormap(ax1, 'gray');

% Corrected axial MIP
ax2 = subplot(1, 2, 2, 'Parent', f);
mipCorr = squeeze(max(engResult.volData, [], axDim));
imagesc(mipCorr, 'Parent', ax2);
title(ax2, 'After Correction');
axis(ax2, 'image');
colormap(ax2, 'gray');

% Status text
if engResult.alias_corrected
    statusText = sprintf('Alias correction: YES (%.1f mm translation)', ...
        engResult.translation_mm);
else
    statusText = 'Alias correction: not needed';
end
if engResult.centered
    statusText = sprintf('%s | Centering: YES (%.1f mm shift)', ...
        statusText, engResult.shift_mm);
else
    statusText = sprintf('%s | Centering: not needed', statusText);
end
uicontrol('Parent', f, 'Style', 'text', ...
    'String', statusText, ...
    'Position', [10 10 880 20], ...
    'HorizontalAlignment', 'left');

% Accept/Reject/Cancel
rawDecision = questdlg( ...
    sprintf('Apply corrections and save to:\n%s', ctx.outputPath), ...
    'Accept Correction?', 'Accept', 'Reject', 'Cancel', 'Accept');

if isvalid(f), close(f); end

switch rawDecision
    case 'Accept'
        decision = 'accept';
    case 'Reject'
        decision = 'reject';
    otherwise
        decision = 'cancel';
end
end


function [inputFile, cancelled] = chooseInputFile()
startDir = pwd;
try
    if exist('javaObjectEDT', 'file') == 2
        chooser = javaObjectEDT('javax.swing.JFileChooser', startDir);
    else
        chooser = javaObject('javax.swing.JFileChooser', startDir);
    end
catch
    chooser = javaObject('javax.swing.JFileChooser', startDir);
end

chooser.setDialogTitle('Select DICOM/NIfTI file or DICOM folder');
chooser.setDialogType(javax.swing.JFileChooser.OPEN_DIALOG);
% Allow both files and directories — the converter adapter handles
% folder inputs (e.g. DICOM series) uniformly, without local routing.
chooser.setFileSelectionMode(javax.swing.JFileChooser.FILES_AND_DIRECTORIES);
chooser.setCurrentDirectory(javaObject('java.io.File', startDir));

dicomFilter = javaObject('javax.swing.filechooser.FileNameExtensionFilter', ...
    'DICOM (*.dcm, *.DCM, *.ima, *.IMA)', {'dcm', 'DCM', 'ima', 'IMA'});
niftiFilter = javaObject('javax.swing.filechooser.FileNameExtensionFilter', ...
    'NIfTI (*.nii, *.nii.gz)', {'nii', 'gz'});

chooser.setAcceptAllFileFilterUsed(true);
chooser.addChoosableFileFilter(dicomFilter);
chooser.addChoosableFileFilter(niftiFilter);
chooser.setFileFilter(niftiFilter);

result = chooser.showOpenDialog([]);
if result ~= 0
    inputFile = '';
    cancelled = true;
    return;
end

selected = chooser.getSelectedFile();
if isempty(selected)
    inputFile = '';
    cancelled = true;
else
    inputFile = char(selected.getAbsolutePath());
    cancelled = false;
end
end


function [outputFile, cancelled] = chooseOutputFile(inputFile)
startDir = fileparts(inputFile);
if isempty(startDir), startDir = pwd; end

try
    if exist('javaObjectEDT', 'file') == 2
        chooser = javaObjectEDT('javax.swing.JFileChooser', startDir);
    else
        chooser = javaObject('javax.swing.JFileChooser', startDir);
    end
catch
    chooser = javaObject('javax.swing.JFileChooser', startDir);
end

chooser.setDialogTitle('Save corrected NIfTI output');
chooser.setDialogType(javax.swing.JFileChooser.SAVE_DIALOG);
chooser.setCurrentDirectory(javaObject('java.io.File', startDir));

[~, baseName] = fileparts(inputFile);
defaultName = [baseName '_corrected.nii'];
chooser.setSelectedFile(javaObject('java.io.File', ...
    fullfile(startDir, defaultName)));

niiFilter = javaObject('javax.swing.filechooser.FileNameExtensionFilter', ...
    'NIfTI (*.nii)', {'nii'});
chooser.setAcceptAllFileFilterUsed(false);
chooser.addChoosableFileFilter(niiFilter);
chooser.setFileFilter(niiFilter);

result = chooser.showSaveDialog([]);
if result ~= 0
    outputFile = '';
    cancelled = true;
    return;
end

selected = chooser.getSelectedFile();
if isempty(selected)
    outputFile = '';
    cancelled = true;
    return;
end

outputFile = char(selected.getAbsolutePath());
[~, ~, ext] = fileparts(outputFile);
if ~strcmpi(ext, '.nii')
    outputFile = [outputFile '.nii'];
end
cancelled = false;
end


function restoreSession(originalPath, originalDir)
path(originalPath);
if exist(originalDir, 'dir') == 7
    cd(originalDir);
end
end
