function env = setFloor(env, type, varargin)
%MOUSECHASEENV.SETFLOOR Set the floor pattern of an environment.
%   ENV = MOUSECHASEENV.SETFLOOR(ENV, TYPE, NAME, VALUE, ...) with TYPE and
%   its options (colours are [r g b] in 0-1; two-colour patterns take a
%   2x3 matrix, one colour per row):
%     'uniform'   'colour' [0.5 0.5 0.5]
%     'checker'   'squareCm' 2, 'colours' [0.45 x3; 0.55 x3]
%     'stripes'   'widthCm' 1, 'angle' 0 (deg, anticlockwise), 'colours'
%     'noise'     'grainCm' 1, 'contrast' 0.15, 'colour' [0.5 x3], 'seed' 1
%     'gradient'  'colours' [from; to], 'angle' 90 (direction of change,
%                 deg anticlockwise from rightwards: 90 = bottom to top)
%     'image'     'file' (any image imread reads; stretched over the screen)
%   Patterns are centred on the screen and rendered at most
%   mouseChaseEnv.screen().floorPx pixels wide.

scr = mouseChaseEnv.screen();
opts = struct(varargin{:});
grey2 = [0.45 0.45 0.45; 0.55 0.55 0.55];
interp = 'nearest'; % sharp edges for geometric patterns
img = [];
[X, Y] = floorGrid(scr);
switch lower(type)
  case 'uniform'
    opts = withDefaults(opts, struct('colour', [0.5 0.5 0.5]));
    env.floorColour = opts.colour(:)';
    interp = 'linear';
  case 'checker'
    opts = withDefaults(opts, struct('squareCm', 2, 'colours', grey2));
    img = twoColour(mod(floor(X / opts.squareCm) + floor(Y / opts.squareCm), 2), opts.colours);
  case 'stripes'
    opts = withDefaults(opts, struct('widthCm', 1, 'angle', 0, 'colours', grey2));
    u = X * cosd(opts.angle) + Y * sind(opts.angle);
    img = twoColour(mod(floor(u / opts.widthCm), 2), opts.colours);
  case 'noise'
    opts = withDefaults(opts, struct('grainCm', 1, 'contrast', 0.15, ...
      'colour', [0.5 0.5 0.5], 'seed', 1));
    old = rng(opts.seed);
    xs = -scr.extentCm(1)/2 : opts.grainCm : scr.extentCm(1)/2 + opts.grainCm;
    ys = -scr.extentCm(2)/2 : opts.grainCm : scr.extentCm(2)/2 + opts.grainCm;
    V = interp2(xs, ys', randn(numel(ys), numel(xs)), X, Y, 'linear');
    rng(old);
    V = max(min(V / 2, 1), -1); % roughly -1..1
    img = min(max(reshape(opts.colour, 1, 1, 3) + opts.contrast * V, 0), 1);
    interp = 'linear';
  case 'gradient'
    opts = withDefaults(opts, struct('colours', [0.4 0.4 0.4; 0.6 0.6 0.6], 'angle', 90));
    u = X * cosd(opts.angle) + Y * sind(opts.angle);
    f = (u - min(u(:))) / (max(u(:)) - min(u(:)));
    c1 = reshape(opts.colours(1,:), 1, 1, 3);
    c2 = reshape(opts.colours(2,:), 1, 1, 3);
    img = c1 + f .* (c2 - c1);
    interp = 'linear';
  case 'image'
    assert(isfield(opts, 'file'), 'mouseChaseEnv:noFile', 'Give the image with ''file''.');
    src = imread(opts.file);
    if size(src, 3) == 1; src = repmat(src, 1, 1, 3); end
    src = double(src(:,:,1:3)) / double(intmax(class(src)));
    % Stretch over the visible screen; the overscan repeats the edge pixels
    col = round((X / scr.dimsCm(1) + 0.5) * size(src, 2) + 0.5);
    row = round((0.5 - Y / scr.dimsCm(2)) * size(src, 1) + 0.5);
    col = min(max(col, 1), size(src, 2));
    row = min(max(row, 1), size(src, 1));
    idx = sub2ind(size(src(:,:,1)), row, col);
    img = zeros([size(X) 3]);
    for c = 1:3
      layer = src(:,:,c);
      img(:,:,c) = layer(idx);
    end
    interp = 'linear';
  otherwise
    error('mouseChaseEnv:badFloor', 'Unknown floor type ''%s''.', type);
end
env.floor = struct('type', lower(type), 'options', opts);
env.floorImage = [];
if ~isempty(img); env.floorImage = uint8(round(255 * img)); end
env.floorExtentCm = scr.extentCm;
env.floorInterpolation = interp;
end

function [X, Y] = floorGrid(scr)
% Pixel-centre coordinates (cm) of the floor image; row 1 is the top
ext = scr.extentCm;
n = round(scr.floorPx * ext / max(ext));
x = ((1:n(1)) - 0.5) / n(1) * ext(1) - ext(1) / 2;
y = ext(2) / 2 - ((1:n(2)) - 0.5) / n(2) * ext(2);
[X, Y] = meshgrid(x, y);
end

function img = twoColour(which, colours)
img = zeros([size(which) 3]);
for c = 1:3
  img(:,:,c) = colours(1, c) * (which == 0) + colours(2, c) * (which == 1);
end
end

function s = withDefaults(s, defaults)
for f = fieldnames(defaults)'
  if ~isfield(s, f{1}); s.(f{1}) = defaults.(f{1}); end
end
unknown = setdiff(fieldnames(s), fieldnames(defaults));
assert(isempty(unknown), 'mouseChaseEnv:badOption', 'Unknown option(s): %s', strjoin(unknown, ', '));
end
