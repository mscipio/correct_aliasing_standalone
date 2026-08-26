function V = spm_vol_nifti(fname, n)
%SPM_VOL_NIFTI Get header information for a NIFTI-1 image.
%
%   V = spm_vol_nifti(P)
%   P - filename.
%   n - volume id (a 1x2 array, e.g. [3,1])
%   V - a structure containing the image volume information.
%
% =========================================================================
% PROVENANCE
%
%   origin:    Adapted from the verified SPM8 r6313-compatible companion,
%              originally distributed with the pseudoCT standalone pipeline
%              (spm8-dan installation). The core function body is preserved
%              from the upstream SPM8 r1143 source with the addition of
%              the hdr field by David Izquierdo to preserve raw NIfTI
%              header access needed by the SPM8 NIfTI I/O path.
%
%   scope:     This app-owned compatibility shim is used ONLY when the
%              selected SPM installation (caller or fallback) lacks a
%              native spm_vol_nifti function. It is NEVER deployed into
%              the installed SPM tree and NEVER shadows a valid caller
%              helper. It remains under the standalone application's
%              vers/ directory and is conditionally added to the MATLAB
%              path only for the duration of processing.
%
%   installed: The pseudoCT standalone, installed SPM trees, and legacy
%              Aether project are NEVER modified, touched, or shadowed
%              by this file. This is a self-contained app-owned aid.
%
%   warranty:  No clinical validation. The calling application documents
%              the override in its result.provenance.spm_override_path.
% =========================================================================
%
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging

% John Ashburner
% $Id: spm_vol_nifti.m 1143 2008-02-07 19:33:33Z spm $

if nargin < 2,  n = [1 1];      end
if ischar(n), n = str2num(n); end  %#ok<ST2NM>
N  = nifti(fname);
n  = [n 1 1];
n  = n(1:2);
dm = [N.dat.dim 1 1 1 1];
if any(n > dm(4:5)), V = []; return; end

dt = struct(N.dat);
dt = double([dt.dtype dt.be]);

if isfield(N.extras, 'mat') && size(N.extras.mat, 3) >= n(1) && ...
   sum(sum(N.extras.mat(:,:,n(1)))) ~= 0
    mat = N.extras.mat(:,:,n(1));
else
    mat = N.mat;
end

off = (n(1)-1 + dm(4)*(n(2)-1)) * ...
      ceil(spm_type(dt(1), 'bits') * dm(1) * dm(2) / 8) * dm(3) + N.dat.offset;

V   = struct('fname',   N.dat.fname,...
             'dim',     dm(1:3),...
             'dt',      dt,...
             'pinfo',   [N.dat.scl_slope N.dat.scl_inter off]',...
             'mat',     mat,...
             'n',       n,...
             'descrip', N.descrip,...
             'private', N, ...
             'hdr',     N.hdr); % Added to preserve raw NIfTI header access
