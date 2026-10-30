function [T, S] = plotMouseChaseLearning(sessions, varargin)
%PLOTMOUSECHASELEARNING Learning curves of a mouse across MouseChase sessions.
%   PLOTMOUSECHASELEARNING(SUBJECT) finds all of the subject's sessions
%   (ROOT\SUBJECT\date\seq\*_MouseChase.mat) and plots, per session:
%     catches per minute
%     time to catch (median and quartiles of the trials)
%     catch speed against chance (0.5 = touches from other times would have
%       caught the bug as fast; lower = the mouse goes for the bug)
%     pursuit index: does the mouse move towards the bug (vs chance)
%     finding vs hitting: time until a paw is near the bug, and from there
%       to the catch
%     activity: distance moved (from the touches)
%     going to the reward spout soon after a catch (within 'spoutWindow' s,
%       see mouseChaseMetrics), against random times
%     approach before the catches, one curve per session
%     catches per minute within each session (engagement)
%   Training stage changes are marked. PLOTMOUSECHASELEARNING(SESSIONS)
%   takes a cell array of experiment references or file paths instead.
%   Options (name, value):
%     'root'     subjects folder (default \\zenneth.cortexlab.net\Subjects)
%     'saveDir'  save the figure as PNG (and the table as CSV) here
%     'video'    true: the mouse's position from video tracking where there
%                is a video (mouseChaseTrack: slow the first time, cached)
%   Other options are passed to mouseChaseMetrics.
%   [T, S] = PLOTMOUSECHASELEARNING(...) returns a table with one row per
%   session and the per-session measures (mouseChaseMetrics).

o = struct('root', '\\zenneth.cortexlab.net\Subjects', 'saveDir', '', 'video', false);
mOpts = {};
for k = 1:2:numel(varargin)
  if isfield(o, varargin{k}); o.(varargin{k}) = varargin{k+1};
  else; mOpts(end+1:end+2) = varargin(k:k+1); end
end
if ischar(sessions) || isstring(sessions) % a subject
  subject = char(sessions);
  files = dir(fullfile(o.root, subject, '*', '*', '*_MouseChase.mat'));
  assert(~isempty(files), 'plotMouseChaseLearning:noSessions', ...
    'No MouseChase sessions in %s', fullfile(o.root, subject));
  sessions = fullfile({files.folder}, {files.name});
else
  subject = '';
end

%% Measures per session
S = cell(1, numel(sessions));
for k = 1:numel(sessions)
  [m, folder] = mouseChaseLoad(sessions{k}, o.root);
  fprintf('%s\n', m.expRef);
  opts = mOpts;
  if o.video && exist(fullfile(folder, [m.expRef '_topCam.mj2']), 'file')
    opts = [opts, {'track', mouseChaseTrack(m, folder)}]; %#ok<AGROW>
  end
  S{k} = mouseChaseMetrics(m, opts{:});
end
S = [S{:}];
[~, order] = sort({S.expRef}); % date_seq_subject sorts by date, then sequence
S = S(order);
if isempty(subject); subject = regexprep(S(1).expRef, '^\d{4}-\d{2}-\d{2}_\d+_', ''); end
cols = {'expRef', 'date', 'trainingStage', 'rewardSize', 'environment', 'duration', 'catches', ...
  'catchesPerMin', 'medianTimeToCatch', 'fracCaughtWithin10s', 'catchSpeedVsChance', ...
  'pursuitIndex', 'chancePursuitIndex', 'medianTimeToNear', 'medianNearToCatch', ...
  'landingsPerMin', 'distanceMovedPerMin', 'rewardVolume', 'fracSpoutInWindow', ...
  'chanceFracSpoutInWindow', 'medianSpoutLatency', 'chanceMedianSpoutLatency', 'mousePosition'};
T = struct2table(rmfield(S, setdiff(fieldnames(S), cols)), 'AsArray', true);
T = T(:, cols);
disp(T(:, {'expRef', 'trainingStage', 'catches', 'catchesPerMin', 'medianTimeToCatch', ...
  'catchSpeedVsChance', 'pursuitIndex', 'chancePursuitIndex'}))

%% Figure
c = mouseChaseStyle();
n = numel(S);
x = 1:n;
labels = cellfun(@(r) r(6:10), {S.expRef}, 'Uni', 0); % MM-DD
sc = c.sessionColours(n);
fig = figure('Name', [subject ': learning'], 'Color', 'w', 'Position', [60 30 1300 1100]);
tl = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
ttl = sprintf('%s: %d sessions, %s to %s', subject, n, S(1).expRef(1:10), S(end).expRef(1:10));
if any(strcmp({S.mousePosition}, 'video'))
  ttl = {ttl, ['Pursuit, activity, spout: filled = mouse position from the video, open = from ' ...
    'the touches (not comparable: the touch estimate is rougher)']};
end
title(tl, ttl, 'FontWeight', 'bold', 'Interpreter', 'none');

ax = sessionAxes(tl, x, labels, S, c);
plot(ax, x, [S.catchesPerMin], '-o', 'Color', c.mouse, 'MarkerFaceColor', c.mouse, 'LineWidth', 2);
ylabel(ax, 'catches / min'); title(ax, 'Catch rate');
ylim(ax, [0 max([S.catchesPerMin]) * 1.2 + eps]);

ax = sessionAxes(tl, x, labels, S, c);
q = cell2mat(arrayfun(@(s) prctile(s.trials.timeToCatch(s.trials.caught), [25 50 75]), S(:), 'Uni', 0));
errorbar(ax, x, q(:,2), q(:,2) - q(:,1), q(:,3) - q(:,2), '-o', 'Color', c.mouse, ...
  'MarkerFaceColor', c.mouse, 'LineWidth', 2, 'CapSize', 0);
set(ax, 'YScale', 'log', 'YLim', [max(min(q(:)) / 1.5, 0.1) max(q(:)) * 1.5]);
ylabel(ax, 'time to catch (s)'); title(ax, 'Time to catch (median, quartiles)');

ax = sessionAxes(tl, x, labels, S, c);
yline(ax, 0.5, '--', 'chance', 'Color', c.muted, 'LabelHorizontalAlignment', 'right');
mu = [S.catchSpeedVsChance];
se = arrayfun(@(s) std(s.trials.chanceFaster, 'omitnan') / sqrt(sum(~isnan(s.trials.chanceFaster))), S);
errorbar(ax, x, mu, se, '-o', 'Color', c.mouse, 'MarkerFaceColor', c.mouse, 'LineWidth', 2, 'CapSize', 0);
ylim(ax, [0 1]);
ylabel(ax, 'P(random touches as fast)'); title(ax, 'Catch speed vs chance (lower = chasing)');

isVideo = strcmp({S.mousePosition}, 'video');
ax = sessionAxes(tl, x, labels, S, c);
yline(ax, 0, '--', 'chance', 'Color', c.muted, 'LabelHorizontalAlignment', 'right');
byMethod(ax, x, [S.pursuitIndex] - [S.chancePursuitIndex], c.mouse, isVideo);
ylabel(ax, 'pursuit index, mouse - chance');
title(ax, sprintf('Pursuit: heading to the bug (bug < %g cm)', S(1).pursuitMaxDist));

ax = sessionAxes(tl, x, labels, S, c);
plot(ax, x, [S.medianTimeToNear], '-o', 'Color', c.mouse, 'MarkerFaceColor', c.mouse, 'LineWidth', 2);
plot(ax, x, [S.medianNearToCatch], '-o', 'Color', c.catch, 'MarkerFaceColor', c.catch, 'LineWidth', 2);
ylabel(ax, 'median time (s)'); title(ax, sprintf('Finding (paw within %g cm) vs hitting', S(1).nearDist));
legend(ax, {'appearance to near', 'near to catch'}, 'Location', 'best', 'Box', 'off');
ylim(ax, [0 max([S.medianTimeToNear S.medianNearToCatch]) * 1.2 + eps]);

ax = sessionAxes(tl, x, labels, S, c);
byMethod(ax, x, [S.distanceMovedPerMin], c.mouse, isVideo);
ylabel(ax, 'cm / min'); title(ax, 'Activity: distance moved');
ylim(ax, [0 max([S.distanceMovedPerMin]) * 1.2 + eps]);

ax = sessionAxes(tl, x, labels, S, c);
h1 = byMethod(ax, x, 100 * [S.chanceFracSpoutInWindow], c.muted, isVideo);
h2 = byMethod(ax, x, 100 * [S.fracSpoutInWindow], c.mouse, isVideo);
ylim(ax, [0 100]);
ylabel(ax, sprintf('%% at the spout within %g s', S(1).spout.maxWait));
title(ax, 'To the spout after a catch');
legend(ax, [h1 h2], {'random times, as far from the spout', 'after catches'}, 'Location', 'best', 'Box', 'off');

ax = nexttile(tl); hold(ax, 'on');
for k = 1:n
  A = S(k).aligned;
  plot(ax, A.tCatch, mean(A.catch, 1, 'omitnan'), 'Color', sc(k,:), 'LineWidth', 2);
end
xlabel(ax, 'time to catch (s)'); ylabel(ax, 'nearest paw to bug (cm)');
title(ax, 'Approach before the catches');
legend(ax, labels, 'Location', 'southwest', 'Box', 'off');
c.style(ax);

ax = nexttile(tl); hold(ax, 'on');
for k = 1:n
  b = S(k).binned;
  plot(ax, b.tMin, b.catchesPerMin, '-o', 'Color', sc(k,:), 'MarkerFaceColor', sc(k,:), ...
    'MarkerSize', 4, 'LineWidth', 1.5);
end
xlabel(ax, 'time in session (min)'); ylabel(ax, 'catches / min');
title(ax, sprintf('Within session (%g min bins)', S(1).binned.binMin));
legend(ax, labels, 'Location', 'best', 'Box', 'off');
c.style(ax);
drawnow;
placeStageLabels(fig);

if ~isempty(o.saveDir)
  if ~isfolder(o.saveDir); mkdir(o.saveDir); end
  exportgraphics(fig, fullfile(o.saveDir, [subject '_learning.png']), 'Resolution', 150);
  writetable(T, fullfile(o.saveDir, [subject '_learning.csv']));
end
end

function ax = sessionAxes(tl, x, labels, S, c)
%SESSIONAXES Axes with one tick per session (MM-DD) and the training stage
%   changes marked by dashed lines and labels.
ax = nexttile(tl); hold(ax, 'on');
stage = [S.trainingStage];
change = [1, find(diff(stage) ~= 0) + 1];
for k = change
  if k > 1; xline(ax, k - 0.5, '--', 'Color', c.axis); end
  text(ax, k - 0.4, 1, sprintf('stage %g', stage(k)), 'Units', 'data', 'Color', c.muted, ...
    'FontSize', 8, 'VerticalAlignment', 'top', 'Tag', 'stageLabel');
end
set(ax, 'XTick', x, 'XTickLabel', labels, 'XLim', [0.5 max(x) + 0.5]);
xlabel(ax, 'session');
c.style(ax);
end

function h = byMethod(ax, x, y, col, isVideo)
%BYMETHOD Line through the sessions; markers filled where the mouse position
%   came from the video, open where it came from the touches.
h = plot(ax, x, y, '-', 'Color', col, 'LineWidth', 2, 'Marker', 'o', 'MarkerFaceColor', col, ...
  'MarkerIndices', find(isVideo));
plot(ax, x(~isVideo), y(~isVideo), 'o', 'Color', col, 'MarkerFaceColor', 'w', 'LineWidth', 2, ...
  'HandleVisibility', 'off');
end

function placeStageLabels(fig)
%PLACESTAGELABELS Move the stage labels to the top of their axes.
for h = findobj(fig, 'Tag', 'stageLabel')'
  yl = ylim(h.Parent);
  h.Position = [h.Position(1) yl(2) 0];
end
end
