function env = create(id, description)
%MOUSECHASEENV.CREATE Start a new MouseChase environment.
%   ENV = MOUSECHASEENV.CREATE(ID, DESCRIPTION) returns an environment with
%   a plain grey floor and no hiding objects. ID is its unique name (letters,
%   digits, '_' and '-', starting with a letter); select it in mc with the
%   task's 'environment' parameter once saved.
%
%   Typical use:
%     env = mouseChaseEnv.create('rocks3', 'Three rocks on a checkerboard');
%     env = mouseChaseEnv.setFloor(env, 'checker', 'squareCm', 2);
%     env = mouseChaseEnv.addObject(env, 'ellipse', [-10 5], [6 4], 20);
%     mouseChaseEnv.preview(env)
%     mouseChaseEnv.save(env)
%
%   Coordinates are cm from the screen centre, x right, y up.
%
% See also mouseChaseEnv.setFloor, mouseChaseEnv.addObject,
%   mouseChaseEnv.preview, mouseChaseEnv.save, mouseChaseEnv.list

if nargin < 2; description = ''; end
assert(ischar(id) && ~isempty(regexp(id, '^[A-Za-z][A-Za-z0-9_-]*$', 'once')), ...
  'mouseChaseEnv:badId', 'ID must start with a letter and contain only letters, digits, _ and -.');
assert(~strcmp(id, 'default'), 'mouseChaseEnv:badId', '''default'' is built into the task.');
scr = mouseChaseEnv.screen();
env = struct('id', id, 'description', description, ...
  'floor', struct('type', 'uniform', 'options', struct('colour', [0.5 0.5 0.5])), ...
  'floorColour', [0.5 0.5 0.5], 'floorImage', [], 'floorExtentCm', scr.extentCm, ...
  'floorInterpolation', 'linear', ...
  'objects', struct('shape', {}, 'centre', {}, 'size', {}, 'angle', {}, 'colour', {}), ...
  'created', '', 'createdBy', '');
end
