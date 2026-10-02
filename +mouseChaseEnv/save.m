function file = save(env, overwrite)
%MOUSECHASEENV.SAVE Save an environment for the task, under its unique ID.
%   FILE = MOUSECHASEENV.SAVE(ENV) writes MouseChaseEnvironments/<id>.mat.
%   An existing environment is never replaced (sessions refer to it by ID),
%   unless MOUSECHASEENV.SAVE(ENV, true) is used deliberately.
%   Remember to commit/sync the new file so the stimulus PC has it.

if nargin < 2; overwrite = false; end
scr = mouseChaseEnv.screen();
% Checks the task relies on
for shape = {'rectangle', 'ellipse'}
  assert(sum(strcmp({env.objects.shape}, shape{1})) <= scr.maxPerShape, ...
    'mouseChaseEnv:tooMany', 'At most %d objects of each shape.', scr.maxPerShape);
end
for k = 1:numel(env.objects)
  if any(abs(env.objects(k).centre) > scr.dimsCm / 2)
    warning('mouseChaseEnv:offScreen', 'Object %d is centred off the screen.', k);
  end
end
dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'MouseChaseEnvironments');
if ~exist(dir, 'dir'); mkdir(dir); end
file = fullfile(dir, [env.id '.mat']);
assert(overwrite || ~exist(file, 'file'), 'mouseChaseEnv:exists', ...
  ['Environment ''%s'' already exists. Choose a new ID, or call ' ...
  'mouseChaseEnv.save(env, true) to replace it (sessions that used it then ' ...
  'refer to the new version).'], env.id);
env.created = datestr(now, 31);
env.createdBy = getenv('USERNAME');
builtin('save', file, 'env');
fprintf('Saved %s\n', file);
end
