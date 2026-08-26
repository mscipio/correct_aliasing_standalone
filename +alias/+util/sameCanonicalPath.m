function same = sameCanonicalPath(a, b)
%SAMECANONICALPATH Compare two paths via canonical resolution.
%   same = alias.util.sameCanonicalPath(a, b)
%
%   Resolves both paths through java.io.File.getCanonicalPath() to
%   handle symlinks, relative components, and redundant separators.
%   Slashes are normalized before comparison. Case-insensitive on
%   Windows, case-sensitive on Unix.
%
%   Input:
%     a, b  — character vectors (paths to files or directories)
%
%   Output:
%     same  — logical, true if the canonical paths are equivalent

if ~ischar(a) || ~ischar(b)
    same = false;
    return;
end

try
    ca = char(java.io.File(a).getCanonicalPath());
    cb = char(java.io.File(b).getCanonicalPath());
catch
    same = false;
    return;
end

ca = normalize(ca);
cb = normalize(cb);

if ispc
    same = strcmpi(ca, cb);
else
    same = strcmp(ca, cb);
end
end

function p = normalize(p)
p = strrep(p, '\', '/');
end
