function S = plotMouseChase(source, varargin)
%PLOTMOUSECHASE Plot a MouseChaseTouch session from its log (touches only).
%   PLOTMOUSECHASE(FILE) plots <expRef>_MouseChase.mat (saved by
%   MouseChaseTouch at the end of a session, next to the block file).
%   PLOTMOUSECHASE(EXPREF) finds it (see mouseChaseLoad). PLOTMOUSECHASE()
%   asks for the file. S = PLOTMOUSECHASE(...) returns the measures of
%   mouseChaseMetrics, plus the figure handle in S.figure.
%   Options (name, value):
%     'video'    true: use the top camera video: the mouse's position from
%                video tracking (mouseChaseTrack; the first time ~7 min per
%                session, then cached) instead of from the touches, and a
%                figure with video frames of a few catches
%     'root'     subjects folder for finding EXPREF without Rigbox
%     'saveDir'  save the figure(s) as PNG in this folder
%   Other options are passed to mouseChaseMetrics.
%
%   One figure, read left to right, top to bottom:
%     arena          where the mouse touched, the bug's path, the catches,
%                    the reward spout
%     catches        cumulative catches over the session
%     time to catch  per trial (bug appearance to catch), running median
%     trials         each row a trial: how close the nearest paw was to the
%                    bug from its appearance on, until the catch (dot)
%     approach       nearest paw distance in the seconds before the catches
%     heading        where the mouse moves relative to the bug (while it is
%                    within 15 cm), compared with chance
%     catch speed    per trial: how often touches from other times would
%                    have caught this bug as fast (0.5 = chance)
%     bug escape     (stages with fleeing) bug speed against threat level;
%                    otherwise a summary
%     to the spout   distance to the reward spout after the catches, and
%                    how soon the mouse gets there, against random times

o = struct('video', false, 'root', '', 'saveDir', '');
mOpts = {};
for k = 1:2:numel(varargin)
  if isfield(o, varargin{k}); o.(varargin{k}) = varargin{k+1};
  else; mOpts(end+1:end+2) = varargin(k:k+1); end
end
if nargin < 1; source = []; end
[m, folder] = mouseChaseLoad(source, o.root);
if isempty(m); S = []; return; end
if o.video
  mOpts = [mOpts, {'track', mouseChaseTrack(m, folder)}];
end
S = mouseChaseMetrics(m, mOpts{:});
c = mouseChaseStyle();

fprintf(['%s (stage %g, %s): %.1f min, %d catches (%.2f/min, %d rewarded, %g ul), ' ...
  'median %.1f s to catch\n'], m.expRef, S.trainingStage, S.environment, S.duration / 60, ...
  S.catches, S.catchesPerMin, S.rewarded, S.rewardVolume, S.medianTimeToCatch);
fprintf(['  catch speed vs chance %.2f (0.5 = chance, lower = faster), pursuit index %.3f ' ...
  '(chance %.3f), touch clock: %s (+-%.3f s)\n'], S.catchSpeedVsChance, S.pursuitIndex, ...
  S.chancePursuitIndex, S.touchClock.method, S.touchClock.uncertainty);

fig = figure('Name', [m.expRef ': session'], 'Color', 'w', 'Position', [80 30 1500 1150]);
tl = tiledlayout(fig, 4, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('%s   stage %g   %d catches in %.0f min   %g ul water   (mouse position: %s)', ...
  m.expRef, S.trainingStage, S.catches, S.duration / 60, S.rewardVolume, S.mousePosition), ...
  'Interpreter', 'none', 'FontWeight', 'bold');

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
sp = S.spout.pos;
plot(ax, sp(1), sp(2), 'p', 'MarkerSize', 12, 'MarkerFaceColor', c.primary, 'MarkerEdgeColor', 'w');
set(ax, 'XLim', [min(-half(1) * 1.15, sp(1) - 1.5) max(half(1) * 1.15, sp(1) + 1.5)], ...
  'YLim', [min(-half(2) * 1.15, sp(2) - 1.5) max(half(2) * 1.15, sp(2) + 1.5)], 'YDir', 'normal');
xlabel(ax, 'x (cm)'); ylabel(ax, 'y (cm)');
title(ax, 'Arena: touches, bug path, catches, spout');
legendFor(ax, {'bug path', 'catch', 'spout'}, {c.bug, c.catch, c.primary}, {'-', 'o', 'p'});
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
bar(ax, ctr, 100 * (hA - hC), 1, 'FaceColor', c.mouse, 'EdgeColor', 'w', 'LineWidth', 2);
yline(ax, 0, '-', 'Color', c.axis);
set(ax, 'XLim', [-180 180], 'XTick', -180:90:180);
xlabel(ax, 'bug direction relative to the mouse''s heading (deg)');
ylabel(ax, 'time, mouse - chance (% points)');
title(ax, sprintf('Heading (bug < %g cm): pursuit index %.3f, chance %.3f', S.pursuitMaxDist, ...
  S.pursuitIndex, S.chancePursuitIndex));
text(ax, 0, 1, ' above 0 near 0 deg = heading for the bug', 'Units', 'normalized', ...
  'VerticalAlignment', 'top', 'Color', c.muted, 'FontSize', 8);
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
    sprintf('At the spout      %.0f%% of the time', 100 * S.spout.fracTimeAtSpout), ...
    '', 'The bug does not flee at this stage.', ...
    sprintf('Touch clock: %s (+-%.0f ms)', S.touchClock.method, 1000 * S.touchClock.uncertainty)};
  text(ax, 0, 1, txt, 'VerticalAlignment', 'top', 'FontName', 'Consolas', 'FontSize', 10, ...
    'Color', c.primary, 'Interpreter', 'none');
end

%% After the catch: to the spout
Sp = S.spout;
ax = nexttile(tl, 10, [1 2]); hold(ax, 'on');
band(ax, Sp.tAligned, Sp.afterRandom, c.muted);
band(ax, Sp.tAligned, Sp.afterCatch, c.mouse);
yline(ax, Sp.dist, ':', 'at the spout', 'Color', c.secondary, 'LabelHorizontalAlignment', 'left');
xline(ax, 0, '-', 'catch', 'Color', c.axis);
xlabel(ax, 'time from the catch (or a matched random time: as far from the spout) (s)');
ylabel(ax, 'mouse to spout (cm)');
if strcmp(S.mousePosition, 'touches')
  title(ax, {'After the catch: distance to the spout', ...
    '(from the touches: rough near the spout, where the mouse is partly off the screen; ''video'', true is better)'});
else
  title(ax, 'After the catch: distance to the spout (mouse position from the video)');
end
legend(ax, flipud(findobj(ax, 'Type', 'line', 'Tag', 'mean')), {'random times', 'catches'}, ...
  'Location', 'northeast', 'Box', 'off');
xlim(ax, Sp.tAligned([1 end]));
c.style(ax);

ax = nexttile(tl, 12); hold(ax, 'on');
tq = 0:0.5:Sp.maxWait;
lc = S.trials.spoutLatency(S.trials.caught);
cumFrac = @(l) mean(l(:) <= tq, 1); % NaN (not within maxWait) counts as never
stairs(ax, tq, cumFrac(Sp.latencyRandom), 'Color', c.muted, 'LineWidth', 2);
stairs(ax, tq, cumFrac(lc), 'Color', c.mouse, 'LineWidth', 2);
ylim(ax, [0 1]);
xlabel(ax, 'time (s)'); ylabel(ax, 'fraction at the spout by then');
title(ax, sprintf('To the spout: median %.1f s after a catch (random times %.1f s)', ...
  S.medianSpoutLatency, S.chanceMedianSpoutLatency));
legend(ax, {'random times', 'catches'}, 'Location', 'southeast', 'Box', 'off');
c.style(ax);

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


function band(ax, t, X, col)
%BAND Mean +- s.e.m. over the rows of X.
mu = mean(X, 1, 'omitnan');
se = std(X, 0, 1, 'omitnan') ./ sqrt(sum(~isnan(X), 1));
ok = ~isnan(mu) & ~isnan(se);
fill(ax, [t(ok) fliplr(t(ok))], [mu(ok) - se(ok) fliplr(mu(ok) + se(ok))], col, ...
  'FaceAlpha', 0.2, 'EdgeColor', 'none', 'HandleVisibility', 'off');
plot(ax, t, mu, 'Color', col, 'LineWidth', 2, 'Tag', 'mean');
end

function legendFor(ax, names, cols, styles)
%LEGENDFOR Legend from invisible proxy markers (so image layers don't show).
h = gobjects(1, numel(names));
for k = 1:numel(names)
  if any(strcmp(styles{k}, {'o', 'p'}))
    h(k) = plot(ax, NaN, NaN, styles{k}, 'MarkerFaceColor', cols{k}, 'MarkerEdgeColor', 'w', 'MarkerSize', 8);
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
