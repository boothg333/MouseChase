function R = mouseChaseCatchRules(C, varargin)
%MOUSECHASECATCHRULES Which touch features tell a real catch from an
%   accidental one, and what would a rule on them cost?
%   R = MOUSECHASECATCHRULES(C) takes a catch table of one or more sessions
%   (mouseChaseCatchTable, concatenated) and splits the catches into good and
%   bad by the video's automatic label: good = 'paw', bad = 'badTypes'
%   (default 'tail'; the rest left out: 'none' catches are mostly fresh
%   landings, so possibly paws reaching out further than the video's
%   1.5 cm from the body; check them by hand). With 'labels' (mouseChaseLabelCatches' table) the
%   labelled catches use those instead: good = deliberate strike, bad =
%   incidental paw, tail, other body part, no mouse (can't tell left out).
%   For each online feature (computable by MouseChaseTouch from the contacts)
%   it sweeps a threshold and returns the trade-off: the fraction of good
%   catches the rule would lose against the fraction of bad ones it would
%   reject. Then a small decision tree on all of them, cross-validated by
%   leaving out one session at a time (does the rule carry over to new days
%   and mice?).
%   R has:
%     data      the table used (with .good: true/false)
%     curves    per feature: name, direction ('<=' keeps small values),
%               theta, goodLost, badRejected
%     atLoss    table: per feature, the bad catches rejected at 5% and 10%
%               of good catches lost, and the thresholds that do it
%     tree      tree fitted on all catches, and its cross-validated
%               goodLost / badRejected
%   Options (name, value):
%     'labels'     manual labels (table, or the CSV file)
%     'manualOnly' true: only the labelled catches (default false)
%     'stages'     only these training stages (default all)
%     'badTypes'   video labels counted as bad (default "tail")
%     'plot'       true (default)
%     'saveDir'    save the figure and the atLoss table here

o = struct('labels', [], 'manualOnly', false, 'stages', [], 'plot', true, 'saveDir', '', ...
  'badTypes', "tail");
for k = 1:2:numel(varargin); o.(varargin{k}) = varargin{k+1}; end

%% Good and bad catches
D = C;
D.good = nan(height(D), 1);
D.good(D.videoType == "paw") = 1;
D.good(ismember(string(D.videoType), o.badTypes)) = 0;
D.labelSource = repmat("video", height(D), 1);
D.manualLabel = nan(height(D), 1);
if ~isempty(o.labels)
  L = o.labels;
  if ~istable(L); L = readtable(L, 'TextType', 'string', 'VariableNamingRule', 'preserve'); end % ('catch' is a keyword)
  [isL, j] = ismember(D.expRef + "#" + D.catch, string(L.expRef) + "#" + L.catch);
  D.manualLabel(isL) = L.label(j(isL));
  lab = D.manualLabel(isL);
  g = nan(size(lab)); g(lab == 1) = 1; g(ismember(lab, 2:5)) = 0;
  D.good(isL) = g;
  D.labelSource(isL) = "manual";
  if o.manualOnly; D = D(isL,:); end
end
if ~isempty(o.stages); D = D(ismember(D.trainingStage, o.stages),:); end
D = D(~isnan(D.good),:);
D.good = D.good == 1;
D.maxSize = max(D.w, D.h);
D.maxSizeLife = max(D.maxW, D.maxH);
R.data = D;
fprintf('%d catches: %d good, %d bad (%d by hand)\n', height(D), sum(D.good), sum(~D.good), ...
  sum(D.labelSource == "manual"));

%% One-feature rules
% [feature, keep direction]: '<=' keeps catches with values up to theta
feats = {'maxSize', '<='; 'area', '<='; 'maxSizeLife', '<='; 'age', '<='; 'pathLen', '<='; ...
  'dCentroid', '<='; 'dNearestOther', '<='; 'behind', '<='; 'dTouchMouse', '<='; 'closing', '>='; ...
  'dOutline', '<='; 'snout', '<='};
D.snout = double(D.snout); % (1: caught only thanks to snoutReach)
nF = size(feats, 1);
curves = struct('name', feats(:,1), 'direction', feats(:,2), 'theta', [], 'goodLost', [], 'badRejected', []);
rowNames = feats(:,1);
at = nan(nF, 4);
for f = 1:nF
  x = D.(feats{f,1});
  sgn = 1; if strcmp(feats{f,2}, '>='); sgn = -1; end
  xs = sgn * x;
  % NaN (e.g. no other contacts) is kept: a rule can't reject on it
  th = unique(xs(~isnan(xs)));
  th = [th; inf]; %#ok<AGROW>
  keep = xs(:)' <= th | isnan(xs(:)');
  gl = 1 - mean(keep(:, D.good), 2);
  br = 1 - mean(keep(:, ~D.good), 2);
  curves(f).theta = sgn * th; curves(f).goodLost = gl; curves(f).badRejected = br;
  for q = 1:2
    lim = [0.05 0.10];
    i = find(gl <= lim(q));
    [~, best] = max(br(i));
    at(f, 2 * q - 1) = br(i(best)); at(f, 2 * q) = sgn * th(i(best));
  end
end
R.curves = curves;
R.atLoss = array2table(at, 'RowNames', rowNames, 'VariableNames', ...
  {'badRejected_at5pctLoss', 'theta_at5pct', 'badRejected_at10pctLoss', 'theta_at10pct'});
R.atLoss.direction = feats(:,2);
R.atLoss = sortrows(R.atLoss, 'badRejected_at5pctLoss', 'descend');
disp(R.atLoss);

%% A small tree on all features, cross-validated by session
X = D{:, feats(:,1)};
sessions = unique(D.expRef);
pred = nan(height(D), 1);
cost = [0 1; 1 0]; % (rows: true bad, good)
for s = 1:numel(sessions)
  test = D.expRef == sessions(s);
  if all(D.good(~test)) || ~any(D.good(~test)); continue; end
  t = fitctree(X(~test,:), D.good(~test), 'MaxNumSplits', 3, 'PredictorNames', feats(:,1), ...
    'Cost', cost, 'ClassNames', [false true]);
  pred(test) = predict(t, X(test,:));
end
ok = ~isnan(pred);
R.tree.model = fitctree(X, D.good, 'MaxNumSplits', 3, 'PredictorNames', feats(:,1), ...
  'ClassNames', [false true]);
R.tree.goodLost = mean(pred(ok & D.good) == 0);
R.tree.badRejected = mean(pred(ok & ~D.good) == 0);
fprintf('Tree (3 splits), leave-one-session-out: loses %.0f%% of good catches, rejects %.0f%% of bad ones\n', ...
  100 * R.tree.goodLost, 100 * R.tree.badRejected);
view(R.tree.model);

%% Figure
if ~o.plot; return; end
c = mouseChaseStyle();
fig = figure('Name', 'MouseChase: catch rules', 'Color', 'w', 'Position', [80 60 1400 900]);
tl = tiledlayout(fig, 3, 5, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('%d catches from %d sessions: %d good (%s), %d bad', height(D), numel(sessions), ...
  sum(D.good), iff(any(D.labelSource == "manual"), 'video + hand labels', 'video: paw'), sum(~D.good)), ...
  'FontWeight', 'bold');
% trade-off curves, best 5 features
ax = nexttile(tl, 1, [2 2]); hold(ax, 'on');
best = R.atLoss.Properties.RowNames(1:min(6, nF));
cols = lines(numel(best));
for b = 1:numel(best)
  f = find(strcmp(feats(:,1), best{b}));
  stairs(ax, 100 * curves(f).goodLost, 100 * curves(f).badRejected, 'LineWidth', 2, 'Color', cols(b,:));
end
if any(ok)
  plot(ax, 100 * R.tree.goodLost, 100 * R.tree.badRejected, 'kp', 'MarkerSize', 12, 'MarkerFaceColor', 'k');
end
plot(ax, [0 100], [0 100], ':', 'Color', c.muted);
xline(ax, [5 10], ':', 'Color', c.axis);
set(ax, 'XLim', [0 50], 'YLim', [0 100]);
xlabel(ax, 'good catches lost (%)'); ylabel(ax, 'bad catches rejected (%)');
legend(ax, [best; {'tree (cross-validated)'}], 'Location', 'southeast', 'Box', 'off', 'Interpreter', 'none');
title(ax, 'Trade-off of one-threshold rules (up and left is better)');
c.style(ax);
% distributions
for f = 1:min(9, nF)
  ax = nexttile(tl); hold(ax, 'on');
  x = D.(feats{f,1});
  e = linspace(prctile(x, 1), prctile(x, 99), 30);
  if numel(unique(e)) < 2; e = linspace(min(x) - 1, max(x) + 1, 30); end
  histogram(ax, x(D.good), e, 'Normalization', 'probability', 'FaceColor', c.mouse, 'EdgeColor', 'none');
  histogram(ax, x(~D.good), e, 'Normalization', 'probability', 'FaceColor', c.bug, 'EdgeColor', 'none', ...
    'FaceAlpha', 0.6);
  title(ax, feats{f,1}); c.style(ax);
  if f == 1; legend(ax, {'good', 'bad'}, 'Box', 'off'); end
end
R.figure = fig;
if ~isempty(o.saveDir)
  if ~isfolder(o.saveDir); mkdir(o.saveDir); end
  exportgraphics(fig, fullfile(o.saveDir, 'mouseChase_catchRules.png'), 'Resolution', 150);
  writetable(R.atLoss, fullfile(o.saveDir, 'mouseChase_catchRules.csv'), 'WriteRowNames', true);
end
end

function v = iff(c, a, b)
if c; v = a; else; v = b; end
end
