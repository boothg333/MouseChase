function S = plotMouseChase(source)
%PLOTMOUSECHASE Plot a MouseChaseTouch session from its log.
%   PLOTMOUSECHASE(FILE) plots <expRef>_MouseChase.mat (saved by
%   MouseChaseTouch at the end of a session, next to the block file).
%   PLOTMOUSECHASE(EXPREF) finds that file in the experiment's folders
%   (needs Rigbox on the path). PLOTMOUSECHASE() asks for the file.
%   S = PLOTMOUSECHASE(...) also returns the summary numbers.
%
%   Figure 1, arena: where the mouse touched (density), the bug's path,
%   hiding objects and where catches happened.
%   Figure 2, over time: distance from the bug to the nearest paw, the
%   bug's threat level (how strongly it reacted) and the catches.
%   Figure 3, pursuit: paw speed against paw-to-bug distance, and how fast
%   the bug moved against its threat level.

if nargin < 1 || isempty(source)
  [f, d] = uigetfile('*_MouseChase.mat', 'Choose a MouseChase session log');
  if isequal(f, 0); S = []; return; end
  source = fullfile(d, f);
end
if ~exist(source, 'file') % treat as an experiment reference
  dirs = cellstr(dat.expPath(source, 'main'));
  files = fullfile(dirs, [source '_MouseChase.mat']);
  source = files{find(cellfun(@(f) exist(f, 'file') == 2, files), 1)};
end
m = load(source, 'mouseChase');
m = m.mouseChase;

B = m.bug; % [time x y heading hidden alive threatLevel]
E = m.touchEvents; % [type id x y w h time]
K = m.catchLog; % [time x y rewarded]
t0 = B(1,1);
dims = m.geometry.dimsCm;
half = dims / 2;
visible = B(:,6) == 1 & B(:,5) == 0;

%% Nearest paw to the bug at each update, and paw speeds
nearest = nan(size(B, 1), 1);
[~, order] = sort(E(:,7));
E = E(order,:);
active = containers.Map('KeyType', 'double', 'ValueType', 'any');
iE = 1;
for i = 1:size(B, 1)
  while iE <= size(E, 1) && E(iE,7) <= B(i,1)
    if E(iE,1) == 4
      if isKey(active, E(iE,2)); remove(active, E(iE,2)); end
    else
      active(E(iE,2)) = E(iE,3:4);
    end
    iE = iE + 1;
  end
  if B(i,6) && active.Count > 0
    P = cell2mat(values(active)');
    nearest(i) = min(hypot(P(:,1) - B(i,2), P(:,2) - B(i,3)));
  end
end
% Paw speed from successive positions of the same contact
pawSpeed = []; pawDist = [];
moves = E(E(:,1) == 3,:);
for id = unique(moves(:,2))'
  r = moves(moves(:,2) == id,:);
  if size(r, 1) < 2; continue; end
  dtm = diff(r(:,7));
  ok = dtm > 0;
  v = hypot(diff(r(:,3)), diff(r(:,4))) ./ max(dtm, eps);
  tm = r(2:end, 7);
  % distance to the bug at that moment (nearest bug update)
  idx = interp1(B(:,1), 1:size(B, 1), tm, 'nearest', 'extrap');
  dB = hypot(r(2:end,3) - B(idx,2), r(2:end,4) - B(idx,3));
  keep = ok & B(idx,6) == 1;
  pawSpeed = [pawSpeed; v(keep)]; %#ok<AGROW>
  pawDist = [pawDist; dB(keep)]; %#ok<AGROW>
end
bugSpeed = [0; hypot(diff(B(:,2)), diff(B(:,3))) ./ max(diff(B(:,1)), eps)];

%% Summary
S.duration = B(end,1) - t0;
S.catches = size(K, 1);
S.rewarded = sum(K(:,4));
S.catchesPerMinute = S.catches / S.duration * 60;
S.touches = sum(E(:,1) == 2);
S.fractionVisible = mean(visible);
fprintf(['%s: %.1f min, %d catches (%d rewarded), %.2f catches/min, ' ...
  '%d paw touches, bug visible %.0f%% of the time\n'], m.expRef, S.duration / 60, ...
  S.catches, S.rewarded, S.catchesPerMinute, S.touches, 100 * S.fractionVisible);
if isfield(m, 'params') && isstruct(m.params) && isfield(m.params, 'trainingStage')
  fprintf('Training stage %g, environment %s\n', m.params.trainingStage, m.environment.id);
end

%% Figure 1: arena
fig1 = figure('Name', [m.expRef ': arena'], 'Color', 'w');
ax = axes(fig1); hold(ax, 'on'); axis(ax, 'equal');
starts = E(ismember(E(:,1), [2 3]), 3:4);
edges = {linspace(-half(1), half(1), 39), linspace(-half(2), half(2), 31)};
if ~isempty(starts)
  N = histcounts2(starts(:,1), starts(:,2), edges{1}, edges{2});
  imagesc(ax, edges{1}, edges{2}, log1p(N'));
  colormap(ax, flipud(gray)); cb = colorbar(ax); cb.Label.String = 'touch density (log)';
end
for k = 1:numel(m.environment.objects)
  o = m.environment.objects(k);
  [x, y] = outline(o.shape, o.centre, o.size, o.angle);
  plot(ax, x, y, 'Color', [0.2 0.5 0.2], 'LineWidth', 1.5);
end
bx = B(:,2); by = B(:,3); bx(~B(:,6)) = nan; by(~B(:,6)) = nan;
plot(ax, bx, by, 'Color', [0.85 0.33 0.1 0.6]);
if ~isempty(K)
  plot(ax, K(K(:,4) == 1, 2), K(K(:,4) == 1, 3), 'o', 'MarkerFaceColor', [0 0.6 0], ...
    'MarkerEdgeColor', 'k', 'MarkerSize', 8);
  plot(ax, K(K(:,4) == 0, 2), K(K(:,4) == 0, 3), 'o', 'MarkerFaceColor', [1 0.7 0], ...
    'MarkerEdgeColor', 'k', 'MarkerSize', 8);
end
rectangle(ax, 'Position', [-half, dims], 'EdgeColor', 'k', 'LineWidth', 1.5);
set(ax, 'XLim', [-half(1) half(1)] * 1.15, 'YLim', [-half(2) half(2)] * 1.15, 'YDir', 'normal');
xlabel(ax, 'x (cm)'); ylabel(ax, 'y (cm)');
title(ax, {sprintf('%s, environment %s', m.expRef, m.environment.id), ...
  'orange: bug path; green/yellow: rewarded/unrewarded catches'}, 'Interpreter', 'none');

%% Figure 2: over time
fig2 = figure('Name', [m.expRef ': over time'], 'Color', 'w');
tm = (B(:,1) - t0) / 60;
ax1 = subplot(2, 1, 1, 'Parent', fig2); hold(ax1, 'on');
plot(ax1, tm, nearest, 'k');
ylabel(ax1, 'nearest paw to bug (cm)');
markCatches(ax1, K, t0);
ax2 = subplot(2, 1, 2, 'Parent', fig2); hold(ax2, 'on');
area(ax2, tm, B(:,7), 'FaceColor', [0.85 0.33 0.1], 'EdgeColor', 'none');
ylabel(ax2, 'bug threat level'); xlabel(ax2, 'time (min)'); ylim(ax2, [0 1]);
markCatches(ax2, K, t0);
linkaxes([ax1 ax2], 'x');
title(ax1, sprintf('%s: %d catches in %.1f min', m.expRef, S.catches, S.duration / 60), ...
  'Interpreter', 'none');

%% Figure 3: pursuit
fig3 = figure('Name', [m.expRef ': pursuit'], 'Color', 'w');
ax3 = subplot(1, 2, 1, 'Parent', fig3);
scatter(ax3, pawDist, pawSpeed, 6, 'filled', 'MarkerFaceAlpha', 0.3);
xlabel(ax3, 'paw-to-bug distance (cm)'); ylabel(ax3, 'paw speed (cm/s)');
title(ax3, 'Paw movement relative to the bug');
ax4 = subplot(1, 2, 2, 'Parent', fig3);
scatter(ax4, B(visible,7), bugSpeed(visible), 6, 'filled', 'MarkerFaceAlpha', 0.3);
xlabel(ax4, 'bug threat level'); ylabel(ax4, 'bug speed (cm/s)');
title(ax4, 'Bug escape response');
S.figures = [fig1 fig2 fig3];
end

function markCatches(ax, K, t0)
yl = ylim(ax);
for k = 1:size(K, 1)
  if K(k,4); c = [0 0.6 0]; else; c = [1 0.7 0]; end % rewarded / not
  plot(ax, [1 1] * (K(k,1) - t0) / 60, yl, 'Color', c);
end
ylim(ax, yl);
end

function [x, y] = outline(shape, centre, sz, angle)
if strcmp(shape, 'rectangle')
  u = [-1 1 1 -1 -1] * sz(1) / 2;
  v = [-1 -1 1 1 -1] * sz(2) / 2;
else
  a = linspace(0, 2 * pi, 60);
  u = cos(a) * sz(1) / 2;
  v = sin(a) * sz(2) / 2;
end
x = centre(1) + u * cosd(angle) - v * sind(angle);
y = centre(2) + u * sind(angle) + v * cosd(angle);
end
