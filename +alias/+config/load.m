function c = load()
%LOAD Deployer-owned configuration through a scoped path/CWD-safe boundary.
%   c = alias.config.load()
%
%   Locates config/defaults.m relative to the standalone project root
%   (derived from this file's own path, never pwd), adds only the config
%   directory to the path inside a scoped onCleanup guard, invokes
%   defaults(), and restores the caller's path before returning.
%
%   Output:
%     c — struct with at least .spm_root, .d2n_root, .d2n_entrypoint,
%         .log_level. Missing fields are filled with safe defaults.
%
%   Throws:
%     alias:ConfigMissing — config/defaults.m cannot be located.

projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
configPath = fullfile(projectRoot, 'config', 'defaults.m');
if exist(configPath, 'file') ~= 2
    error('alias:ConfigMissing', ...
        'Deployer configuration not found at %s', configPath);
end

originalPath = path;
restore = onCleanup(@() path(originalPath));
addpath(fullfile(projectRoot, 'config'), '-begin');
c = defaults();

% Fill missing fields with safe defaults so downstream code can rely on them.
if ~isfield(c, 'spm_root') || ~ischar(c.spm_root)
    c.spm_root = '';
end
if ~isfield(c, 'd2n_root') || ~ischar(c.d2n_root)
    c.d2n_root = '';
end
if ~isfield(c, 'd2n_entrypoint') || ~ischar(c.d2n_entrypoint) || isempty(c.d2n_entrypoint)
    c.d2n_entrypoint = 'dcm2nii';
end
if ~isfield(c, 'log_level') || ~ischar(c.log_level) || isempty(c.log_level)
    c.log_level = 'info';
end
end
