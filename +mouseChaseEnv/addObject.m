function env = addObject(env, shape, centre, objSize, angle, colour)
%MOUSECHASEENV.ADDOBJECT Add a hiding object (the bug hides under it, and it
%   blocks the bug's view of paws).
%   ENV = MOUSECHASEENV.ADDOBJECT(ENV, SHAPE, CENTRE, SIZE, ANGLE, COLOUR)
%     SHAPE   'rectangle' or 'ellipse'
%     CENTRE  [x y] cm from the screen centre (y up)
%     SIZE    [w h] cm
%     ANGLE   deg, anticlockwise (default 0)
%     COLOUR  [r g b] in 0-1 (default [0.7 0.7 0.7])
%   The task can draw up to mouseChaseEnv.screen().maxPerShape objects of
%   each shape.

if nargin < 5 || isempty(angle); angle = 0; end
if nargin < 6 || isempty(colour); colour = [0.7 0.7 0.7]; end
assert(any(strcmp(shape, {'rectangle', 'ellipse'})), 'mouseChaseEnv:badShape', ...
  'Shape must be ''rectangle'' or ''ellipse''.');
assert(numel(centre) == 2 && numel(objSize) == 2 && all(objSize > 0) && numel(colour) == 3, ...
  'mouseChaseEnv:badObject', 'CENTRE and SIZE need 2 values (SIZE > 0), COLOUR 3.');
scr = mouseChaseEnv.screen();
n = sum(strcmp({env.objects.shape}, shape));
assert(n < scr.maxPerShape, 'mouseChaseEnv:tooMany', ...
  'The task can draw at most %d objects of each shape.', scr.maxPerShape);
env.objects(end+1) = struct('shape', shape, 'centre', centre(:)', 'size', objSize(:)', ...
  'angle', angle, 'colour', colour(:)');
end
