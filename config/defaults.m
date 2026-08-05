function c = defaults()
%DEFAULTS Deployer-owned configuration for correct_aliasing_standalone.
%   Edit this file to set the SPM installation root and log level.
%
%   Fields:
%     spm_root  — absolute path to SPM installation directory
%     log_level — 'none' | 'info' | 'verbose'

c = struct();
c.spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/spm8-r6313';
c.log_level = 'info';
end
