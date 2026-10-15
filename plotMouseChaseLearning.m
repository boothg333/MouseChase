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
%     approach before the catches, one curve per session
%     catches per minute within each session (engagement)
%   Training stage changes are marked. PLOTMOUSECHASELEARNING(SESSIONS)
%   takes a cell array of experiment references or file paths instead.
%   Options (name, value):
%     'root'     subjects folder (default \\zenneth.cortexlab.net\Subjects)
%     'saveDir'  save the figure as PNG (and the table as CSV) here
%   Other options are passed to mouseChaseMetrics.
%   [T, S] = PLOTMOUSECHASELEARNING(...) returns a table with one row per
%   session and the per-session measures (mouseChaseMetrics).

o = struct('root', '\\zenneth.cortexlab.net\Subjects', 'saveDir', '');
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
  m = mouseChaseLoad(sessions{k}, o.root);
  fprintf('%s\n', m.expRef);
  S{k} = mouseChaseMetrics(m, mOpts{:});
end
S = [S{:}];
[~, order] = sort({S.expRef}); % date_seq_subject sorts by date, then sequence
S = S(order);
if isempty(subject); subject = regexprep(S(1).expRef, '^\d{4}-\d{2}-\d{2}_\d+_', ''); end
cols = {'expRef', 'date', 'trainingStage', 'rewardSize', 'environment', 'duration', 'catches', ...
  'catchesPerMin', 'medianTimeToCatch', 'fracCaughtWithin10s', 'catchSpeedVsChance', ...
  'pursuitIndex', 'chancePursuitIndex', 'medianTimeToNear', 'medianNearToCatch', ...
  'landingsPerMin', 'distanceMovedPerMin', 'rewardVolume'};
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
fig = figure('Name', [subject ': learning'], 'Color', 'w', 'Position', [60 60 1500 820]);
tl = tiledlayout(fig, 2, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('%s: %d sessions, %s to %s', subject, n, S(1).expRef(1:10), S(end).expRef(1:10)), ...
  'FontWeight', 'bold', 'Interpreter', 'none');

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

ax = sessionAxes(tl, x, labels, S, c);
plot(ax, x, [S.chancePursuitIndex], '-o', 'Color', c.muted, 'MarkerFaceColor', c.muted, 'LineWidth', 2);
plot(ax, x, [S.pursuitIndex], '-o', 'Color', c.mouse, 'MarkerFaceColor', c.mouse, 'LineWidth', 2);
ylabel(ax, 'mean cos(heading to bug)'); title(ax, 'Pursuit: moving towards the bug');
legend(ax, {'chance', 'mouse'}, 'Location', 'best', 'Box', 'off');

ax = sessionAxes(tl, x, labels, S, c);
plot(ax, x, [S.medianTimeToNear], '-o', 'Color', c.mouse, 'MarkerFaceColor', c.mouse, 'LineWidth', 2);
plot(ax, x, [S.medianNearToCatch], '-o', 'Color', c.catch, 'MarkerFaceColor', c.catch, 'LineWidth', 2);
ylabel(ax, 'median time (s)'); title(ax, sprintf('Finding (paw within %g cm) vs hitting', S(1).nearDist));
legend(ax, {'appearance to near', 'near to catch'}, 'Location', 'best', 'Box', 'off');
ylim(ax, [0 max([S.medianTimeToNear S.medianNearToCatch]) * 1.2 + eps]);

ax = sessionAxes(tl, x, labels, S, c);
plot(ax, x, [S.distanceMovedPerMin], '-o', 'Color', c.mouse, 'MarkerFaceColor', c.mouse, 'LineWidth', 2);
ylabel(ax, 'cm / min'); title(ax, 'Activity: distance moved (touches)');
ylim(ax, [0 max([S.distanceMovedPerMin]) * 1.2 + eps]);

ax = nexttile(tl); hold(ax, 'on');
for k = 1:n
  A = S(k).aligned;
  plot(ax, A.tCatch, mean(A.catch, 1, 'omitnan'), 'Color', sc(k,:), 'LineWidth', 2);
end
xlabel(ax, 'time to catch (s)'); ylabel(ax, 'nearest paw to bug (cm)');
title(ax, 'Approach before the catches');
legend(ax, labels, 'Location', 'northwest', 'Box', 'off');
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

function placeStageLabels(fig)
%PLACESTAGELABELS Move the stage labels to the top of their axes.
for h = findobj(fig, 'Tag', 'stageLabel')'
  yl = ylim(h.Parent);
  h.Position = [h.Position(1) yl(2) 0];
end
end
