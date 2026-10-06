function env = load(id)
%MOUSECHASEENV.LOAD Load a saved environment by ID, e.g. to change it and
%   save it under a new ID.
file = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'MouseChaseEnvironments', [id '.mat']);
assert(exist(file, 'file') == 2, 'mouseChaseEnv:notFound', 'No environment ''%s'' (%s).', id, file);
s = builtin('load', file, 'env');
env = s.env;
end
