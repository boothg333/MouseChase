function S = plotMouseChase(source, varargin)
%PLOTMOUSECHASE Plot a MouseChaseTouch session from its log (touches only).
%   PLOTMOUSECHASE(FILE) plots <expRef>_MouseChase.mat (saved by
%   MouseChaseTouch at the end of a session, next to the block file).
%   PLOTMOUSECHASE(EXPREF) finds it (see mouseChaseLoad). PLOTMOUSECHASE()
%   asks for the file. S = PLOTMOUSECHASE(...) returns the measures of
%   mouseChaseMetrics, plus the figure handle in S.figure.
%   Options (name, value):
%     'video'    true: also show video frames of a few catches
%                (plotMouseChaseCatches; slow, reads the camera file)
%     'root'     subjects folder for finding EXPREF without Rigbox
%     'saveDir'  save the figure(s) as PNG in this folder
%   Other options are passed to mouseChaseMetrics.
%
%   One figure, read left to right, top to bottom:
%     arena          where the mouse touched, the bug's path, the catches
%     catches        cumulative catches over the session
%     time to catch  per trial (bug appearance to catch), running median
%     trials         each row a trial: how close the nearest paw was to the
%                    bug from its appearance on, until the catch (dot)
%     approach       nearest paw distance in the seconds before the catches
%     heading        where the mouse moves relative to the bug, vs chance
%     catch speed    per trial: how often touches from other times would
%                    have caught this bug as fast (0.5 = chance)
%     bug escape     (stages with fleeing) bug speed against threat level

o = struct('video', false, 'root', '', 'saveDir', '');
mOpts = {};
for k = 1:2:numel(varargin)
  if isfield(o, varargin{k}); o.(varargin{k}) = varargin{k+1};
  else; mOpts(end+1:end+2) = varargin(k:k+1); end
end
if nargin < 1; source = []; end
[m, folder] = mouseChaseLoad(source, o.root);
if isempty(m); S = []; return; end
S = mouseChaseMetrics(m, mOpts{:});
c = mouseChaseStyle();

fprintf(['%s (stage %g, %s): %.1f min, %d catches (%.2f/min, %d rewarded, %g ul), ' ...
  'median %.1f s to catch\n'], m.expRef, S.trainingStage, S.environment, S.duration / 60, ...
  S.catches, S.catchesPerMin, S.rewarded, S.rewardVolume, S.medianTimeToCatch);
fprintf(['  catch speed vs chance %.2f (0.5 = chance, lower = faster), pursuit index %.3f ' ...
  '(chance %.3f), touch clock: %s (+-%.3f s)\n'], S.catchSpeedVsChance, S.pursuitIndex, ...
  S.chancePursuitIndex, S.touchClock.method, S.touchClock.uncertainty);

fig = figure('Name', [m.expRef ': session'], 'Color', 'w', 'Position', [80 60 1500 900]);
tl = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('%s   stage %g   %d catches in %.0f min   %g ul water', m.expRef, ...
  S.trainingStage, S.catches, S.duration / 60, S.rewardVolume), 'Interpreter', 'none', ...
  'FontWeight', 'bold');

%% Arena
ax = nexttile(tl, 1); hold(ax, 'on'); axis(ax, 'equal');
dims = m.geometry.dimsCm; half = dims / 2;
allLand = S.touches(S.touches(:,1) == 2 & S.touches(:,7) >= S.tStart, 3:4);
edges = {linspace(-half(1), half(1), 39), linspace(-half(2), half(2), 31)};
if ~isempty(allLand)
  N = histcounts2(allLand(:,1), allLand(:,2), edges{1}, edges{2});
  imagesc(ax, edges{1}, edges{2}, N' / S.duration * 60);
  colormap(ax, c.seqMap);
  cb = colorbar(ax); cb.Label.String = 'paw landings / min';
end
objects = m.environment.objects;
if isfield(m.params, 'hidingObjects') && ~m.params.hidingObjects; objects = objects([]); end
for k = 1:numel(objects)
  [x, y] = outline(objects(k).shape, objects(k).centre, objects(k).size, objects(k).angle);
  plot(ax, x, y, 'Color', c.secondary, 'LineWidth', 1.5);
end
B = m.bug;
bx = B(:,2); by = B(:,3); bx(~B(:,6)) = NaN; by(~B(:,6)) = NaN;
plot(ax, bx, by, 'Color', [c.bug 0.35], 'LineWidth', 0.5);
K = m.catchLog;
if ~isempty(K)
  scatter(ax, K(:,2), K(:,3), 40, c.catch, 'filled', 'MarkerEdgeColor', 'w', 'LineWidth', 1);
end
rectangle(ax, 'Position', [-half, dims], 'EdgeColor', c.axis, 'LineWidth', 1);
set(ax, 'XLim', [-half(1) half(1)] * 1.15, 'YLim', [-half(2) half(2)] * 1.15, 'YDir', 'normal');
xlabel(ax, 'x (cm)'); ylabel(ax, 'y (cm)');
title(ax, 'Arena: touches, bug path, catches');
legendFor(ax, {'bug path', 'catch'}, {c.bug, c.catch}, {'-', 'o'});
c.style(ax);

%% Cumulative catches
ax = nexttile(tl, 2); hold(ax, 'on');
tm = (K(:,1) - S.tStart) / 60;
stairs(ax, [0; tm; S.duration / 60], [0; (1:numel(tm))'; numel(tm)], 'Color', c.mouse, 'LineWidth', 2);
xlabel(ax, 'time in session (min)'); ylabel(ax, 'catches');
title(ax, sprintf('Catches: %.2f / min', S.catchesPerMin));
xlim(ax, [0 S.duration / 60]);
c.style(ax);

%% Time to catch per trial
ax = nexttile(tl, 3); hold(ax, 'on');
tr = S.trials;
caught = tr.caught;
scatter(ax, tr.trial(caught), tr.timeToCatch(caught), 30, c.mouse, 'filled', 'MarkerFaceAlpha', 0.7);
if any(~caught) % last trial: not caught when the session ended
  scatter(ax, tr.trial(~caught), tr.tEnd(~caught) - tr.tSpawn(~caught), 30, c.muted, '^');
end
if sum(caught) >= 5
  plot(ax, tr.trial(caught), movmedian(tr.timeToCatch(caught), 7), 'Color', c.primary, 'LineWidth', 1.5);
end
set(ax, 'YScale', 'log');
xlabel(ax, 'trial'); ylabel(ax, 'time to catch (s)');
title(ax, sprintf('Time to catch: median %.1f s', S.medianTimeToCatch));
c.style(ax);

%% Trial raster: nearest paw distance from bug appearance on
ax = nexttile(tl, 4, [1 2]); hold(ax, 'on');
A = S.aligned;
imagesc(ax, A.tSpawn, 1:height(tr), A.spawn, 'AlphaData', ~isnan(A.spawn));
colormap(ax, flipud(c.seqMap));
clim(ax, [0 20]);
cb = colorbar(ax); cb.Label.String = 'nearest paw to bug (cm)';
scatter(ax, tr.timeToCatch(caught), tr.trial(caught), 14, c.primary, 'filled');
set(ax, 'YDir', 'reverse', 'XLim', A.tSpawn([1 end]), 'YLim', [0.5 height(tr) + 0.5], 'Color', c.surface);
xlabel(ax, 'time since the bug appeared (s)'); ylabel(ax, 'trial');
title(ax, sprintf(['Trials: dark = paw close to the bug, dot = catch. ' ...
  'Median %.1f s until a paw is within %g cm, then %.1f s to the catch'], ...
  S.medianTimeToNear, S.nearDist, S.medianNearToCatch));
c.style(ax);

%% Approach before the catch
ax = nexttile(tl, 6); hold(ax, 'on');
mu = mean(A.catch, 1, 'omitnan');
se = std(A.catch, 0, 1, 'omitnan') ./ sqrt(sum(~isnan(A.catch), 1));
fill(ax, [A.tCatch fliplr(A.tCatch)], [mu - se fliplr(mu + se)], c.mouse, ...
  'FaceAlpha', 0.2, 'EdgeColor', 'none');
plot(ax, A.tCatch, mu, 'Color', c.mouse, 'LineWidth', 2);
yline(ax, A.chanceDist, '--', 'typical distance', 'Color', c.muted, 'LabelHorizontalAlignment', 'left');
xlabel(ax, 'time to catch (s)'); ylabel(ax, 'nearest paw to bug (cm)');
title(ax, 'Approach before the catches');
ylim(ax, [0 max([mu + se, A.chanceDist]) * 1.1]);
c.style(ax);

%% Heading relative to the bug
ax = nexttile(tl, 7); hold(ax, 'on');
e = linspace(-180, 180, 13); % 30 deg bins
ctr = e(1:end-1) + diff(e) / 2;
hA = histcounts(rad2deg(S.headingToBug.actual), e, 'Normalization', 'probability');
hC = histcounts(rad2deg(S.headingToBug.chance), e, 'Normalization', 'probability');
plot(ax, ctr, hC, 'Color', c.muted, 'LineWidth', 2);
plot(ax, ctr, hA, 'Color', c.mouse, 'LineWidth', 2);
xline(ax, 0, ':', 'Color', c.axis);
set(ax, 'XLim', [-180 180], 'XTick', -180:90:180);
xlabel(ax, 'bug direction relative to the mouse''s heading (deg)'); ylabel(ax, 'fraction of time');
title(ax, sprintf('Heading: pursuit index %.3f (chance %.3f)', S.pursuitIndex, S.chancePursuitIndex));
legend(ax, {'chance (bug shifted in time)', 'mouse'}, 'Location', 'south', 'Box', 'off');
c.style(ax);

%% Catch speed against chance, per trial
ax = nexttile(tl, 8); hold(ax, 'on');
yline(ax, 0.5, '--', 'chance', 'Color', c.muted, 'LabelHorizontalAlignment', 'right');
scatter(ax, tr.trial, tr.chanceFaster, 30, c.mouse, 'filled', 'MarkerFaceAlpha', 0.7);
ylim(ax, [0 1]);
xlabel(ax, 'trial'); ylabel(ax, 'P(random touches as fast)');
title(ax, sprintf('Catch speed vs chance: %.2f (lower = faster)', S.catchSpeedVsChance));
c.style(ax);

%% Bug escape (only at stages where the bug flees)
ax = nexttile(tl, 9); hold(ax, 'on');
vis = B(:,6) == 1 & B(:,5) == 0;
if any(B(vis,7) > 0)
  spd = [0; hypot(diff(B(:,2)), diff(B(:,3))) ./ max(diff(B(:,1)), eps)];
  scatter(ax, B(vis,7), spd(vis), 6, c.bug, 'filled', 'MarkerFaceAlpha', 0.3);
  xlabel(ax, 'bug threat level'); ylabel(ax, 'bug speed (cm/s)');
  title(ax, 'Bug escape response');
  c.style(ax);
else
  axis(ax, 'off');
  txt = {sprintf('Duration          %.1f min', S.duration / 60), ...
    sprintf('Catches           %d (%.2f / min)', S.catches, S.catchesPerMin), ...
    sprintf('Rewarded          %d x %g ul', S.rewarded, S.rewardSize), ...
    sprintf('Caught within 10 s  %.0f%% of trials', 100 * S.fracCaughtWithin10s), ...
    sprintf('Paw landings      %.0f / min', S.landingsPerMin), ...
    sprintf('Moved (touches)   %.0f cm / min', S.distanceMovedPerMin), ...
    sprintf('Bug visible       %.0f%% of the time', 100 * S.fractionVisible), ...
    '', 'The bug does not flee at this stage.', ...
    sprintf('Touch clock: %s (+-%.0f ms)', S.touchClock.method, 1000 * S.touchClock.uncertainty)};
  text(ax, 0, 1, txt, 'VerticalAlignment', 'top', 'FontName', 'Consolas', 'FontSize', 10, ...
    'Color', c.primary, 'Interpreter', 'none');
end

S.figure = fig;
if ~isempty(o.saveDir)
  if ~isfolder(o.saveDir); mkdir(o.saveDir); end
  exportgraphics(fig, fullfile(o.saveDir, [m.expRef '_session.png']), 'Resolution', 150);
end
if o.video
  F = plotMouseChaseCatches(m, folder, 'saveDir', o.saveDir);
  S.figure = [fig F];
end
end

%% ===================== Helpers =====================


function legendFor(ax, names, cols, styles)
%LEGENDFOR Legend from invisible proxy markers (so image layers don't show).
h = gobjects(1, numel(names));
for k = 1:numel(names)
  if strcmp(styles{k}, 'o')
    h(k) = plot(ax, NaN, NaN, 'o', 'MarkerFaceColor', cols{k}, 'MarkerEdgeColor', 'w', 'MarkerSize', 7);
  else
    h(k) = plot(ax, NaN, NaN, styles{k}, 'Color', cols{k}, 'LineWidth', 1.5);
  end
end
legend(ax, h, names, 'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off');
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
