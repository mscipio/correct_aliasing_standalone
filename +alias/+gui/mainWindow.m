function varargout = mainWindow()
%MAINWINDOW Operator GUI for alias correction and centering.
%   alias.gui.mainWindow()
%
%   Launches a programmatic MATLAB GUI with Java JFileChooser file
%   selection, preview display, and accept/reject/cancel decisions.
%   Path and CWD are restored on exit via onCleanup.
%
%   Input file selection uses JFileChooser with DICOM and NIfTI filters.
%   Output uses a save dialog with NIfTI filter only.

rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
originalPath = path;
originalDir = pwd;
cleanup = onCleanup(@() restoreSession(originalPath, originalDir));
addpath(rootDir, '-begin');

% --- Step 1: Select input file ---
[inputFile, cancelled] = chooseInputFile();
if cancelled
    if nargout > 0
        r = alias.result.create('cancelled');
        varargout{1} = r;
    end
    return;
end

% --- Step 2: Select output file ---
[outputFile, cancelled] = chooseOutputFile(inputFile);
if cancelled
    if nargout > 0
        r = alias.result.create('cancelled');
        varargout{1} = r;
    end
    return;
end

% --- Step 3: SPM preflight ---
config = loadConfig(rootDir);
try
    spmInfo = alias.spm.preflight(config);
catch ME
    errordlg(sprintf('SPM preflight failed: %s', ME.message), 'SPM Error');
    if nargout > 0
        r = alias.result.create('failed');
        r.error.identifier = strrep(ME.identifier, 'alias:', 'alias:Spm');
        r.error.message = ME.message;
        varargout{1} = r;
    end
    return;
end

% Add SPM for processing duration
addpath(config.spm_root, '-begin');

% --- Step 4: Load and process ---
try
    V = spm_vol(inputFile);
    volData = spm_read_vols(V);
    volAffine = V.mat;
catch ME
    errordlg(sprintf('Failed to load input: %s', ME.message), 'Load Error');
    if nargout > 0
        r = alias.result.create('failed');
        r.error.identifier = 'alias:LoadFailed';
        r.error.message = ME.message;
        varargout{1} = r;
    end
    return;
end

% Run engine with both operations
ops = struct('AliasCorrection', true, 'Centering', true);
engResult = alias.core.engine(volData, volAffine, ops);

% --- Step 5: Show preview ---
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

% --- Step 6: Accept/Reject/Cancel ---
decision = questdlg( ...
    sprintf('Apply corrections and save to:\n%s', outputFile), ...
    'Accept Correction?', 'Accept', 'Reject', 'Cancel', 'Accept');

if isvalid(f), close(f); end

switch decision
    case 'Accept'
        % Write output
        provenance = alias.provenance.capture(spmInfo.spm_version, rootDir);
        try
            writeOutput(outputFile, engResult.volData, engResult.affine, V);
            if nargout > 0
                r = alias.result.create('success');
                r.input = inputFile;
                r.output = outputFile;
                r.changed = engResult.alias_corrected || engResult.centered;
                r.alias_correction = struct('performed', engResult.alias_corrected, ...
                    'detected_direction', '', 'translation_mm', engResult.translation_mm);
                r.centering = struct('performed', engResult.centered, ...
                    'shift_mm', engResult.shift_mm);
                r.transform = engResult.affine;
                r.provenance = provenance;
                varargout{1} = r;
            end
        catch ME
            if nargout > 0
                r = alias.result.create('failed');
                r.error.identifier = 'alias:WriteFailed';
                r.error.message = ME.message;
                varargout{1} = r;
            end
        end

    case 'Reject'
        if nargout > 0
            r = alias.result.create('rejected');
            r.input = inputFile;
            varargout{1} = r;
        end

    otherwise  % Cancel or close
        if nargout > 0
            r = alias.result.create('cancelled');
            r.input = inputFile;
            varargout{1} = r;
        end
end
end


function [inputFile, cancelled] = chooseInputFile()
% Choose one input file using Java JFileChooser.
% Mirrors the pattern from dicom2nifti_standalone/dcm2nii.m.
startDir = pwd;
try
    if exist('javaObjectEDT', 'file') == 2
        chooser = javaObjectEDT('javax.swing.JFileChooser', startDir);
    else
        chooser = javaObject('javax.swing.JFileChooser', startDir);
    end
catch
    % R2019 fallback
    chooser = javaObject('javax.swing.JFileChooser', startDir);
end

chooser.setDialogTitle('Select DICOM or NIfTI input');
chooser.setDialogType(javax.swing.JFileChooser.OPEN_DIALOG);
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
if result ~= 0  % JFileChooser.APPROVE_OPTION = 0
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
% Choose output file using Java JFileChooser save dialog.
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

% Propose default name
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
% Ensure .nii extension
[~, ~, ext] = fileparts(outputFile);
if ~strcmpi(ext, '.nii')
    outputFile = [outputFile '.nii'];
end
cancelled = false;
end


function writeOutput(outputPath, volData, affine, V)
% Write output using SPM with temp-staged atomic promote.
tempOutput = [outputPath '.tmp_' char(randi([97 122], 1, 8)) '.nii'];
try
    V.fname = tempOutput;
    V.mat = affine;
    V = spm_create_vol(V);
    spm_write_vol(V, volData);
    % Atomic promote
    if exist(outputPath, 'file') == 2
        delete(outputPath);
    end
    [ok, msg] = movefile(tempOutput, outputPath, 'f');
    if ~ok
        error('alias:WriteFailed', 'Could not promote: %s', msg);
    end
catch ME
    if exist(tempOutput, 'file') == 2
        delete(tempOutput);
    end
    rethrow(ME);
end
end


function config = loadConfig(rootDir)
% Load deployer configuration.
configPath = fullfile(rootDir, 'config', 'defaults.m');
if exist(configPath, 'file') == 2
    oldPath = path;
    restore = onCleanup(@() path(oldPath));
    addpath(fullfile(rootDir, 'config'), '-begin');
    config = defaults();
else
    config = struct('spm_root', '', 'log_level', 'info');
end
end


function restoreSession(originalPath, originalDir)
% Restore MATLAB path and CWD.
path(originalPath);
if exist(originalDir, 'dir') == 7
    cd(originalDir);
end
end
