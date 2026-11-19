function [rec, T] = mouseChaseNextStage(sessions, varargin)
%MOUSECHASENEXTSTAGE Recommend the training stage for a mouse's next
%   MouseChase session.
%   REC = MOUSECHASENEXTSTAGE(SUBJECT) looks at the subject's sessions
%   (ROOT\SUBJECT\date\seq\*_MouseChase.mat; or a cell array of experiment
%   references or files) and, from the last 'nSessions' at the current
%   stage, recommends:
%     up    every one of them met all criteria below
%     down  every one of them had fewer than 'minDownRate' catches/min (the
%           mouse lost track after moving up)
%     stay  otherwise (REC.failed says what was missing)
%   Criteria, per session (defaults; name, value options to change them):
%     'minRate'      2     catches per minute (engagement)
%     'maxTimeToCatch' 12  s, median from the bug appearing to the catch
%     'minPursuit'   0.1   pursuit index minus chance: moves towards the bug
%     'minSpout'     0.1   fraction at the spout soon after a catch, minus
%                          chance: has linked catches and reward
%     'nSessions'    2     consecutive sessions at the current stage
%     'minDownRate'  1     catches per minute below which it goes back
%   For information only, T.nextShare / T.nextRate: the catches that would
%   also have counted under the next stage's catch rules (smaller bug and
%   margin, no snout reach, its contact-size limit). Not a criterion: it
%   badly underestimates, as the mouse changes how it hunts (EB056 at stage
%   1: 0.05-0.4/min predicted for stage 2; it then caught 2.1-2.3/min there).
%   [REC, T] also returns the table of all sessions: the measures, whether
%   each criterion was met, and 'legacy' for sessions before the stages
%   were renumbered on 2026-10-22 (no catchMargin in the log; their stage
%   is shown in today's numbering, stage + 1, and they don't count).
%
%   The thresholds are provisional: they are set from EB056 and EB058,
%   which by 2026-11 had only moved from stage 1 to 2 (EB056 met them at
%   stage 1 on 2026-10-26 and 27, so "up" from then; it was moved up on
%   2026-11-06 and kept catching ~2/min). The fleeing bug of stages 3+ will make catches
%   slower: check maxTimeToCatch against the first mice there.
%   Each session's measures are cached (they don't change once it is saved),
%   so a call after a session only measures the new one (the first call
%   on a computer measures them all: ~15 s for 18 sessions).
%   Other options: 'root' (as in mouseChaseLoad), 'verbose' (true),
%   'cacheDir' (tempdir\MouseChase\nextStage), 'redo' (false), 'table'
%   (a T from an earlier call: recommend from it without loading the
%   sessions again, e.g. from its first rows, to see what it would have said
%   then).

o = struct('minRate', 2, 'maxTimeToCatch', 12, 'minPursuit', 0.1, 'minSpout', 0.1, ...
  'nSessions', 2, 'minDownRate', 1, ...
  'root', '\\zenneth.cortexlab.net\Subjects', 'verbose', true, 'table', [], ...
  'cacheDir', fullfile(tempdir, 'MouseChase', 'nextStage'), 'redo', false);
for k = 1:2:numel(varargin); o.(varargin{k}) = varargin{k+1}; end
if ~isempty(o.table)
  T = o.table(:, 1:find(strcmp(o.table.Properties.VariableNames, 'nextRate')));
elseif ischar(sessions) || isstring(sessions)
  files = dir(fullfile(o.root, char(sessions), '*', '*', '*_MouseChase.mat'));
  assert(~isempty(files), 'mouseChaseNextStage:noSessions', 'No MouseChase sessions in %s', ...
    fullfile(o.root, char(sessions)));
  sessions = fullfile({files.folder}, {files.name});
end

%% Measures per session
if isempty(o.table); T = measure(sessions, o); end
T.okRate = T.catchesPerMin >= o.minRate;
T.okTime = T.medianTimeToCatch <= o.maxTimeToCatch;
T.okPursuit = T.pursuit >= o.minPursuit;
T.okSpout = T.spout >= o.minSpout;
T.allOk = T.okRate & T.okTime & T.okPursuit & T.okSpout & ~T.legacy;

%% Recommendation, from the last sessions at the current stage
cur = T.stage(end);
run = find(T.stage ~= cur | T.legacy, 1, 'last') + 1; % first of the current run
if isempty(run); run = 1; end
last = max(run, height(T) - o.nSessions + 1):height(T);
rec = struct('subject', regexprep(T.expRef(end), '^\d{4}-\d{2}-\d{2}_\d+_', ''), ...
  'currentStage', cur, 'sessionsAtStage', height(T) - run + 1, 'basedOn', T.expRef(last)', ...
  'action', "stay", 'nextStage', cur, 'failed', strings(1, 0));
crit = {'okRate', sprintf('catches/min >= %g', o.minRate); ...
  'okTime', sprintf('median time to catch <= %g s', o.maxTimeToCatch); ...
  'okPursuit', sprintf('pursuit - chance >= %g', o.minPursuit); ...
  'okSpout', sprintf('spout after catch - chance >= %g', o.minSpout)};
for c = 1:size(crit, 1)
  if ~all(T.(crit{c,1})(last)); rec.failed(end+1) = string(crit{c,2}); end
end
if numel(last) < o.nSessions
  rec.failed(end+1) = sprintf('%d sessions at stage %d (needs %d)', numel(last), cur, o.nSessions);
end
if numel(last) >= o.nSessions && all(T.catchesPerMin(last) < o.minDownRate) && cur > 1
  rec.action = "down"; rec.nextStage = cur - 1;
elseif isempty(rec.failed) && cur < 6
  rec.action = "up"; rec.nextStage = cur + 1;
end

if o.verbose
  disp(T(:, {'expRef', 'stage', 'legacy', 'catches', 'catchesPerMin', 'medianTimeToCatch', 'pursuit', ...
    'spout', 'nextShare', 'nextRate', 'allOk'}));
  fprintf('%s: stage %d for %d session(s); next session: stage %d (%s)\n', rec.subject, cur, ...
    rec.sessionsAtStage, rec.nextStage, rec.action);
  if rec.action ~= "up" && ~isempty(rec.failed)
    fprintf('  not yet: %s\n', strjoin(rec.failed, '; '));
  end
end
end

function T = measure(sessions, o)
%MEASURE One row per session: its measures (see the help above), cached.
version = 1; % (raise when the measures change: older caches are redone)
n = numel(sessions);
rows = cell(n, 1);
for k = 1:n
  [~, name] = fileparts(sessions{k});
  cacheFile = fullfile(o.cacheDir, [regexprep(name, '_MouseChase$', '') '.mat']);
  if ~o.redo && exist(cacheFile, 'file')
    c = load(cacheFile);
    if isfield(c, 'version') && c.version == version; rows{k} = c.r; continue; end
  end
  [m, ~] = mouseChaseLoad(sessions{k}, o.root);
  S = mouseChaseMetrics(m);
  P = m.params;
  legacy = ~isfield(P, 'catchMargin') || isnan(P.catchMargin);
  stage = P.trainingStage + legacy; % (renumbered on 2026-10-22)
  r = struct('expRef', string(m.expRef), 'stage', stage, 'legacy', legacy, ...
    'minutes', S.duration / 60, 'catches', S.catches, 'catchesPerMin', S.catchesPerMin, ...
    'medianTimeToCatch', S.medianTimeToCatch, ...
    'pursuit', S.pursuitIndex - S.chancePursuitIndex, ...
    'spout', S.fracSpoutInWindow - S.chanceFracSpoutInWindow, ...
    'nextShare', NaN, 'nextRate', NaN);
  if ~legacy && stage < 6
    ok = countsAtStage(mouseChaseCatchTable(m, '', 'track', false, 'metrics', S), m, stage + 1);
    r.nextShare = mean(ok);
    r.nextRate = sum(ok) / S.duration * 60;
  end
  rows{k} = r;
  try
    if ~isfolder(o.cacheDir); mkdir(o.cacheDir); end
    save(cacheFile, 'r', 'version');
  catch % (no cache: measured again next time)
  end
end
T = struct2table([rows{:}]);
T = sortrows(T, 'expRef'); % date_seq_subject: by date
end

function ok = countsAtStage(C, m, stage)
%COUNTSATSTAGE Would each catch (mouseChaseCatchTable) have counted under
%   STAGE's catch rules? Its bug (same centre and heading, that stage's
%   size), catchMargin, snout reach and contact-size limit.
v = stageCatchRules(stage);
ok = false(height(C), 1);
for k = 1:height(C)
  rB = find(abs(m.bug(:,1) - C.t(k)) < 1e-6, 1);
  if isempty(rB) || isnan(C.x(k)); continue; end
  bug = m.bug(rB,2:4);
  d = outlineDistance([C.x(k) C.y(k)], bug(1:2), bug(3), v.bugLength, v.bugWidth);
  reach = v.catchMargin + v.snoutReach * C.snout(k); % (snout: it was moving at the bug)
  ok(k) = d <= reach && max(C.w(k), C.h(k)) <= v.maxCatchContactSize;
end
end

function v = stageCatchRules(stage)
%STAGECATCHRULES The catch rules of MouseChaseTouch's stageValues (a copy:
%   keep in step with its ladder).
%        bugLength bugWidth catchMargin snoutReach maxCatchContactSize
R = [9.0  3.6   2.0   3  Inf
     6.0  2.4   1.0   0  1.0
     5.25 2.1   0.8   0  1.0
     4.5  1.8   0.55  0  1.0
     3.9  1.5   0.45  0  1.0
     3.6  1.35  0.35  0  1.0];
r = R(min(max(round(stage), 1), size(R, 1)), :);
v = struct('bugLength', r(1), 'bugWidth', r(2), 'catchMargin', r(3), 'snoutReach', r(4), ...
  'maxCatchContactSize', r(5));
end

function d = outlineDistance(xy, pos, heading, len, wid)
%OUTLINEDISTANCE A copy of MouseChaseTouch's (which can't share a file).
a = len / 2;
b = wid / 2;
rel = xy - pos;
u = abs(rel(:,1) .* cos(heading) + rel(:,2) .* sin(heading));
v = abs(-rel(:,1) .* sin(heading) + rel(:,2) .* cos(heading));
d = zeros(size(xy, 1), 1);
out = (u / a) .^ 2 + (v / b) .^ 2 > 1;
if ~any(out); return; end
t = linspace(0, pi / 2, 33);
qx = a * cos(t); qy = b * sin(t);
ax = qx(1:end-1); ay = qy(1:end-1);
dx = diff(qx); dy = diff(qy);
wx = u(out) - ax; wy = v(out) - ay;
f = min(max((wx .* dx + wy .* dy) ./ (dx .^ 2 + dy .^ 2), 0), 1);
d(out) = sqrt(min((wx - f .* dx) .^ 2 + (wy - f .* dy) .^ 2, [], 2));
end
