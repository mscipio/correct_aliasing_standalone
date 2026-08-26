function safePromote(staging, final, mover)
%SAFEPROMOTE Atomically promote a temp file to its final location.
%   alias.util.safePromote(staging, final)
%   alias.util.safePromote(staging, final, @movefile)
%
%   1. If final exists: backup = tempname(fileparts(final));
%      movefile(final, backup). On failure, delete staging and throw
%      alias:PromoteFailed (destination unchanged).
%   2. movefile(staging, final). If succeeds, delete backup.
%   3. If promotion fails: movefile(backup, final), delete staging,
%      throw alias:PromoteFailed (destination restored). If restoration
%      itself fails, throw alias:PromoteFailed with the original error
%      and a note that restoration also failed.
%
%   The optional 'mover' argument (default @movefile) allows tests to
%   inject a deterministic failure; it must have the same signature as
%   movefile: [ok, msg] = mover(src, dst, 'f').

if nargin < 3
    mover = @movefile;
end

if exist(staging, 'file') ~= 2
    error('alias:PromoteFailed', 'Staging file does not exist: %s', staging);
end

outputDir = fileparts(final);
if isempty(outputDir), outputDir = pwd; end

hadPrior = exist(final, 'file') == 2;
backup = '';

if hadPrior
    backup = tempname(outputDir);
    [ok, msg] = mover(final, backup, 'f');
    if ~ok
        if exist(staging, 'file') == 2, delete(staging); end
        error('alias:PromoteFailed', ...
            'Could not back up existing destination: %s', msg);
    end
end

% Promote staging → final
[ok, msg] = mover(staging, final, 'f');
if ~ok
    % Restore backup if we had one
    if hadPrior && ~isempty(backup) && exist(backup, 'file') == 2
        [rok, rmsg] = movefile(backup, final, 'f');
        if ~rok
            % Restoration itself failed — surface both errors
            if exist(staging, 'file') == 2, delete(staging); end
            error('alias:PromoteFailed', ...
                'Promotion failed (%s) AND restoration failed (%s). Backup at: %s', ...
                msg, rmsg, backup);
        end
    end
    if exist(staging, 'file') == 2, delete(staging); end
    error('alias:PromoteFailed', ...
        'Could not promote staging to final: %s', msg);
end

% Clean up backup on success
if hadPrior && ~isempty(backup) && exist(backup, 'file') == 2
    delete(backup);
end
end
