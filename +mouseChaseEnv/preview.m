function fig = preview(env, trainingStages)
%MOUSECHASEENV.PREVIEW Draw an environment to scale, as on the touchscreen.
%   MOUSECHASEENV.PREVIEW(ENV) shows the floor, the hiding objects (numbered,
%   as used by mouseChaseEnv.removeObject), the screen edge, the crevice
%   the bug can hide in past the edge, and the box over the photodiode
%   square (out of reach). Bug outlines at training stages 1 and 5 are drawn
%   below the screen edge for scale.
%   MOUSECHASEENV.PREVIEW(ENV, STAGES) draws bugs for other stages.
%   Accepts an environment struct or a saved environment's ID.

if ischar(env); env = mouseChaseEnv.load(env); end
if nargin < 2; trainingStages = [1 5]; end
scr = mouseChaseEnv.screen();
half = scr.dimsCm / 2;

fig = figure('Name', ['MouseChase environment: ' env.id], 'Color', 'w');
ax = axes(fig); hold(ax, 'on'); axis(ax, 'equal');
lim = half + scr.creviceCm;
set(ax, 'XLim', [-lim(1) lim(1)], 'YLim', [-lim(2) lim(2)], 'Color', [0.85 0.85 0.85]);
xlabel(ax, 'x (cm)'); ylabel(ax, 'y (cm)');

% Floor (image row 1 = top)
ext = env.floorExtentCm;
if isempty(ext); ext = scr.extentCm; end
if isempty(env.floorImage)
  floorImg = repmat(reshape(env.floorColour, 1, 1, 3), 2, 2);
else
  floorImg = env.floorImage;
end
image(ax, 'XData', [-ext(1) ext(1)] / 2, 'YData', [ext(2) -ext(2)] / 2, 'CData', floorImg);
% Everything outside the screen is out of view: shade it
outside = [-lim(1) -lim(2); lim(1) -lim(2); lim(1) lim(2); -lim(1) lim(2)];
inner = [-half(1) -half(2); -half(1) half(2); half(1) half(2); half(1) -half(2)];
patch(ax, 'Faces', [1 2 3 4 1 5 6 7 8 5], 'Vertices', [outside; inner], ...
  'FaceColor', [1 1 1], 'FaceAlpha', 0.7, 'EdgeColor', 'none');
rectangle(ax, 'Position', [-half, scr.dimsCm], 'EdgeColor', 'k', 'LineWidth', 1.5);

% Hiding objects
for k = 1:numel(env.objects)
  o = env.objects(k);
  [x, y] = outline(o.shape, o.centre, o.size, o.angle);
  patch(ax, x, y, o.colour(:)', 'EdgeColor', [0.2 0.2 0.2]);
  text(ax, o.centre(1), o.centre(2), sprintf('%d', k), 'HorizontalAlignment', 'center', ...
    'FontWeight', 'bold', 'Color', [0.1 0.1 0.6]);
end

% Areas out of reach (the photodiode box)
for b = 1:size(scr.blockedCm, 1)
  r = scr.blockedCm(b,:);
  patch(ax, r([1 3 3 1]), r([2 2 4 4]), [0.3 0.3 0.3], 'FaceAlpha', 0.6, 'EdgeColor', 'r');
  text(ax, mean(r([1 3])), r(4) + 0.8, 'photodiode box', 'Color', 'r', ...
    'HorizontalAlignment', 'right', 'FontSize', 8);
end

% Bugs for scale, below the screen edge
for i = 1:numel(trainingStages)
  [len, wid] = bugSize(trainingStages(i));
  c = [-half(1) + 3 + 12 * (i - 1), -half(2) - 2.2];
  [x, y] = outline('ellipse', c, [len wid], 0);
  patch(ax, x, y, 'k');
  text(ax, c(1) + len / 2 + 0.5, c(2), sprintf('bug, stage %d', trainingStages(i)), 'FontSize', 8);
end

nr = sum(strcmp({env.objects.shape}, 'rectangle'));
ne = sum(strcmp({env.objects.shape}, 'ellipse'));
title(ax, {sprintf('%s: %s', env.id, env.description), ...
  sprintf('floor: %s, %d rectangles, %d ellipses', env.floor.type, nr, ne)}, ...
  'Interpreter', 'none');
end

function [x, y] = outline(shape, centre, sz, angle)
if strcmp(shape, 'rectangle')
  u = [-1 1 1 -1] * sz(1) / 2;
  v = [-1 -1 1 1] * sz(2) / 2;
else
  a = linspace(0, 2 * pi, 60);
  u = cos(a) * sz(1) / 2;
  v = sin(a) * sz(2) / 2;
end
x = centre(1) + u * cosd(angle) - v * sind(angle);
y = centre(2) + u * sind(angle) + v * cosd(angle);
end

function [len, wid] = bugSize(stage)
% Bug size per training stage, as in MouseChaseTouch's stageValues
sizes = [4.0 1.6; 3.5 1.4; 3.0 1.2; 2.6 1.0; 2.4 0.9];
row = sizes(min(max(round(stage), 1), 5), :);
len = row(1); wid = row(2);
end
