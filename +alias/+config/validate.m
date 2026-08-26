function validated = validate(c)
%VALIDATE Deployer-owned configuration before any processing work.
%   validated = alias.config.validate(c)
%
%   Checks required scalar fields, verifies the d2n root directory exists,
%   and enforces the fixed public facade identity for the converter
%   entrypoint. The SPM root is validated for type only; its existence
%   is checked conditionally by alias.spm.preflight when the fallback
%   is actually selected (caller-owned core-5 authority may not need it).
%
%   Throws:
%     alias:ConfigInvalid        — missing/non-scalar/non-char required field
%     alias:D2nRootMissing       — d2n_root directory does not exist
%     alias:D2nEntrypointFixed   — d2n_entrypoint is not the fixed public name

% Config must be a scalar struct
if ~isstruct(c) || ~isscalar(c)
    error('alias:ConfigInvalid', 'Configuration must be a scalar struct.');
end

requiredScalars = {'spm_root', 'd2n_root', 'd2n_entrypoint', 'log_level'};
for i = 1:numel(requiredScalars)
    name = requiredScalars{i};
    if ~isfield(c, name) || ~ischar(c.(name))
        error('alias:ConfigInvalid', ...
            'Configuration field ''%s'' must be a scalar character vector.', name);
    end
    % d2n_root and d2n_entrypoint must be nonempty (always required).
    % spm_root may be empty when caller-owned SPM authority is sufficient.
    if isempty(strtrim(c.(name))) && any(strcmp(name, {'d2n_root', 'd2n_entrypoint'}))
        error('alias:ConfigInvalid', ...
            'Configuration field ''%s'' must be nonempty.', name);
    end
end

% d2n root must exist as a directory (always required for conversion)
if exist(c.d2n_root, 'dir') ~= 7
    error('alias:D2nRootMissing', ...
        'Configured d2n root does not exist: %s', c.d2n_root);
end

% Fixed public facade identity for the converter entrypoint
fixedEntrypoint = 'dcm2nii';
if ~strcmp(c.d2n_entrypoint, fixedEntrypoint)
    error('alias:D2nEntrypointFixed', ...
        'Converter entrypoint must be ''%s''; got ''%s''.', ...
        fixedEntrypoint, c.d2n_entrypoint);
end

% NOTE: spm_root existence is NOT validated here. It is validated
% conditionally by alias.spm.preflight only when the fallback path is
% selected (no core-5 markers on caller path). This allows complete
% caller-owned SPM authority even when the configured fallback root
% is absent or empty.

validated = c;
end
