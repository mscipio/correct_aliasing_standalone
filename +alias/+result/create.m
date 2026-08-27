function r = create(status, message)
%CREATE Build a structured result with the unified public shape.
%   r = alias.result.create()              returns a 'success' result
%   r = alias.result.create(status)        returns a result with the given status
%   r = alias.result.create(status, msg)   also sets the top-level message
%
%   Status vocabulary (no public 'rejected'):
%     'success'   — processing completed and output committed
%     'partial'   — accepted vocabulary; not emitted unless output committed
%     'failed'    — processing/config/output refusal
%     'cancelled' — operator Reject/Cancel/chooser close
%
%   Public result contract — exactly these four top-level fields, in order:
%     .status   — char: 'success' | 'partial' | 'failed' | 'cancelled'
%     .outputs  — cell array of char: committed corrected paths only
%     .message  — char: human-readable summary
%     .details  — struct: all rich diagnostics
%
%   .details sub-fields (populated by callers as appropriate):
%     .input_path, .output_path, .changed, .operations,
%     .alias_correction, .centering, .transform, .provenance, .failure

if nargin < 1 || isempty(status)
    status = 'success';
end
if nargin < 2 || isempty(message)
    message = '';
end

% Validate status vocabulary
validStatuses = {'success', 'partial', 'failed', 'cancelled'};
if ~any(strcmp(status, validStatuses))
    error('alias:InvalidStatus', ...
        'Status must be one of: %s. Got ''%s''.', ...
        strjoin(validStatuses, ', '), status);
end

% Build the four-field result in deterministic field order.
r = struct();
r.status  = status;
r.outputs = {};
r.message = message;

% details: all rich diagnostics live here.
r.details = struct();
r.details.input_path = '';
r.details.output_path = '';
r.details.changed = false;

r.details.operations = struct( ...
    'AliasCorrection', false, ...
    'Centering', false);

r.details.alias_correction = struct( ...
    'performed', false);

r.details.centering = struct( ...
    'performed', false);

r.details.transform = struct( ...
    'applied', false, ...
    'rotation', 0, ...
    'translation', 0, ...
    'scale', 1);

r.details.provenance = struct( ...
    'version', '', ...
    'matlab_release', '', ...
    'spm_version', '', ...
    'spm_authority', '', ...
    'spm_root', '', ...
    'spm_override_path', '', ...
    'd2n_root', '', ...
    'algorithm_id', '', ...
    'validation_status', '', ...
    'converter_route', '');

r.details.failure = struct( ...
    'identifier', '', ...
    'message', '', ...
    'stack', '', ...
    'cause', '');
end
