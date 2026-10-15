function S = mouseChaseMetrics(m, varargin)
%MOUSECHASEMETRICS Behavioural measures of a MouseChaseTouch session, from
%   the touches alone (no video needed).
%   S = MOUSECHASEMETRICS(M) takes the 'mouseChase' struct (mouseChaseLoad).
%   Options (name, value):
%     'nearDist'  cm, a paw this close to the bug counts as "at the bug" (5)
%     'nShuffle'  time shifts of the bug for chance levels (20)
%     'minShift'  s, smallest time shift (60)
%     'pursuitMaxDist'  cm, heading/pursuit only while the bug is this close (15)
%     'track'     video tracking (mouseChaseTrack): the mouse's body position
%                 replaces the touch-based estimate
%     'rewardPos' cm, where the reward spout is ([-20 3]: measured in the
%                 video of the EB056 sessions, just past the left screen edge)
%     'spoutDist' cm, the mouse is at the spout within this distance (see
%                 mouseChaseMetrics>spoutVisits; default depends on 'track')
%
%   Chance levels: the bug's trajectory is shifted in time against the
%   touches (circularly, over the times it was visible), which keeps where
%   the mouse touched and where the bug went, but breaks their relation.
%   Measured above chance means the mouse goes for the bug.
%
%   Touch times are logged in GetSecs, the bug in block time; the offset
%   between the two is taken from the log's clockSync if present (sessions
%   from 2026-10-15 on), otherwise estimated from the catches (see
%   touchClockOffset below). S.touchClock says which, and the uncertainty.
%
%   S has the session summary as fields, plus:
%     trials     table, one row per bug appearance (trial)
%     landings   [time x y distToBug] of each touch landing while the bug
%                was visible
%     aligned    nearest-paw distance aligned to bug appearance (.spawn,
%                trials x .tSpawn) and to the catch (.catch, x .tCatch)
%     binned     catches per minute in .binMin minute bins
%     bugT, nearest, mouseXY   per bug update: time, nearest paw distance
%                (cm) and the touch-based mouse position estimate (cm)
%     touches    touch events with times converted to block time

o = struct('nearDist', 5, 'nShuffle', 20, 'minShift', 60, 'pursuitMaxDist', 15, ...
  'track', [], 'rewardPos', [-20 3], 'spoutDist', []);
for k = 1:2:numel(varargin); o.(varargin{k}) = varargin{k+1}; end

B = m.bug; % [time x y heading hidden alive threatLevel]
E = m.touchEvents; % [type id x y w h time]
K = m.catchLog; % [time x y rewarded]
P = struct('catchRadius', 3, 'rewardSize', NaN, 'trainingStage', NaN, ...
  'rewardProbability', NaN, 'visualRange', NaN);
if isfield(m, 'params') && isstruct(m.params)
  for f = fieldnames(P)'
    if isfield(m.params, f{1}); P.(f{1}) = m.params.(f{1}); end
  end
end
[~, order] = sort(E(:,7));
E = E(order,:);

%% Touch times -> block time
S.expRef = m.expRef;
S.date = datetime(m.expRef(1:10), 'InputFormat', 'yyyy-MM-dd');
if isfield(m, 'clockSync') && size(m.clockSync, 1) > 1 % [blockTime GetSecs] per update
  c = polyfit(m.clockSync(:,2), m.clockSync(:,1), 1);
  E(:,7) = polyval(c, E(:,7));
  S.touchClock = struct('method', 'clockSync', 'uncertainty', 0);
else
  [off, unc, score] = touchClockOffset(B, E, K, P.catchRadius);
  E(:,7) = E(:,7) - off;
  S.touchClock = struct('method', 'estimated from catches', 'offset', off, ...
    'uncertainty', unc, 'catchesConsistent', score);
end
S.touches = E;

%% Contacts at each bug update, nearest paw to the bug
nB = size(B, 1);
alive = B(:,6) == 1;
visible = alive & B(:,5) == 0;
[Ci, Cx, Cy] = contactsAtUpdates(B(:,1), E);
dC = hypot(Cx - B(Ci,2), Cy - B(Ci,3));
nearest = accumarray(Ci, dC, [nB 1], @min, NaN);
nearest(~alive) = NaN;

%% Mouse position: from the video tracking if given (mouseChaseTrack),
% otherwise from the touches: mean of the footprints (landings) in the last
% 0.5 s (paws in stance; a dragged tail moves rather than lands)
isLand = E(:,1) == 2;
L = E(isLand,:);
if ~isempty(o.track)
  mouseXY = interp1(o.track.t, o.track.xy, B(:,1), 'linear', NaN);
  S.mousePosition = 'video';
else
  mouseXY = windowMean(L(:,7), L(:,3:4), B(:,1), 0.5);
  S.mousePosition = 'touches';
end
dtV = 0.3; % s, for the mouse's velocity
prevXY = interp1(B(:,1), mouseXY, B(:,1) - dtV, 'linear', NaN);
mouseV = (mouseXY - prevXY) / dtV;

%% Trials: from each bug appearance to the catch (or the session end)
spawn = find(diff([0; alive]) == 1);
death = find(diff([alive; 0]) == -1) + 1; % first row not alive
death(death > nB) = nB;
nT = numel(spawn);
tr = table((1:nT)', B(spawn,1), B(death,1), false(nT,1), false(nT,1), nan(nT,1), ...
  nan(nT,1), nan(nT,1), nan(nT,1), zeros(nT,1), ...
  'VariableNames', {'trial', 'tSpawn', 'tEnd', 'caught', 'rewarded', 'timeToCatch', ...
  'timeToNear', 'minDist', 'fracHidden', 'nLandings'});
for k = 1:nT
  rows = spawn(k):death(k)-1;
  c = find(abs(K(:,1) - B(death(k),1)) < 1e-6, 1);
  if ~isempty(c)
    tr.caught(k) = true;
    tr.rewarded(k) = K(c,4) == 1;
    tr.timeToCatch(k) = K(c,1) - tr.tSpawn(k);
  end
  nearRow = rows(find(visible(rows) & nearest(rows) <= o.nearDist, 1));
  if ~isempty(nearRow); tr.timeToNear(k) = B(nearRow,1) - tr.tSpawn(k); end
  tr.minDist(k) = min(nearest(rows), [], 'omitnan');
  tr.fracHidden(k) = mean(B(rows,5));
  tr.nLandings(k) = sum(L(:,7) >= tr.tSpawn(k) & L(:,7) < tr.tEnd(k));
end

%% Chance: the bug shifted in time over the visible updates
V = find(visible);
nV = numel(V);
inV = zeros(nB, 1); inV(V) = 1:nV;
minShiftN = round(o.minShift / median(diff(B(:,1))));
if nV > 2 * minShiftN
  shifts = round(linspace(minShiftN, nV - minShiftN, o.nShuffle));
else
  shifts = [];
end
shiftedRow = @(rows, s) V(mod(inV(rows) - 1 + s, nV) + 1);

% Landings: how close to the bug the paws come down (descriptive only: a
% visible bug never has a paw within the catch radius, as that ends the
% trial, so a time-shifted bug isn't a fair chance level here)
rowL = lastAtOrBefore(B(:,1), L(:,7)); % bug update before the landing
okL = ~isnan(rowL);
okL(okL) = visible(rowL(okL));
rowL = rowL(okL);
dLand = hypot(L(okL,3) - B(rowL,2), L(okL,4) - B(rowL,3));
S.landings = [L(okL,7), L(okL,3:4), dLand];

% Pursuit: does the mouse move towards the bug? The angle between the
% mouse's heading and the direction to the bug, while it moves > 3 cm/s and
% the bug is within pursuitMaxDist (further away it may not see or care)
spd = hypot(mouseV(:,1), mouseV(:,2));
rowP = find(visible & spd > 3 & all(~isnan(mouseXY), 2));
angTo = @(r) headingAngles(mouseXY(rowP,:), mouseV(rowP,:), B(r,2:3), o.pursuitMaxDist);
angA = angTo(rowP);
angSh = cell(numel(shifts), 1);
pursuitSh = nan(numel(shifts), 1);
for s = 1:numel(shifts)
  angSh{s} = angTo(shiftedRow(rowP, shifts(s)));
  pursuitSh(s) = mean(cos(angSh{s}));
end
% angle between the mouse's heading and the bug (0 = heading straight at it)
S.headingToBug = struct('actual', angA, 'chance', vertcat(angSh{:}));
pursuit = cos(angA);
S.pursuitMaxDist = o.pursuitMaxDist;

% Catch speed against chance: each trial's bug path is replayed against the
% touches of other times (the whole session shifted circularly). How often
% would those touches have caught the bug at least as fast as the mouse
% did? 0.5 = no faster than chance, 0 = always faster.
visMin = nV * median(diff(B(:,1))) / 60;
nPer = accumarray(Ci, 1, [nB 1]);
c0 = [0; cumsum(nPer)]; % contacts of update i: c0(i)+1 : c0(i+1)
rowsAll = find(B(:,1) >= B(find(alive, 1),1));
nAll = numel(rowsAll);
shiftsAll = round(linspace(minShiftN, nAll - minShiftN, o.nShuffle));
tr.chanceFaster = nan(nT, 1);
for k = find(tr.caught)'
  rows = (spawn(k):death(k))'; % incl. the catch update (bug position at the catch)
  canCatch = [visible(rows(1:end-1)); true];
  tHit = inf(numel(shiftsAll), 1);
  for s = 1:numel(shiftsAll)
    r = rowsAll(mod(rows - rowsAll(1) + shiftsAll(s), nAll) + 1); % touches from here
    cnt = nPer(r);
    ent = repelem(c0(r) - [0; cumsum(cnt(1:end-1))], cnt) + (1:sum(cnt))';
    iRow = repelem((1:numel(rows))', cnt);
    hit = hypot(Cx(ent) - B(rows(iRow),2), Cy(ent) - B(rows(iRow),3)) <= P.catchRadius ...
      & canCatch(iRow);
    if any(hit); tHit(s) = B(rows(iRow(find(hit, 1))),1) - B(spawn(k),1); end
  end
  % within an update counts as equally fast (touch reports arrive a few ms
  % after their time stamp, so the game can see a contact one update late)
  T = tr.timeToCatch(k);
  tol = 0.05;
  tr.chanceFaster(k) = mean(tHit < T - tol) + 0.5 * mean(abs(tHit - T) <= tol);
end
S.trials = tr;

%% Aligned nearest-paw distance
dtA = 1 / 30;
tSp = 0:dtA:90;
tCa = -5:dtA:0;
Asp = nan(nT, numel(tSp));
Aca = nan(nT, numel(tCa));
for k = 1:nT
  rows = spawn(k):death(k)-1;
  if numel(rows) < 2; continue; end
  t = B(rows,1) - B(spawn(k),1);
  Asp(k,:) = interp1(t, nearest(rows), tSp, 'previous', NaN);
  if tr.caught(k)
    Aca(k,:) = interp1(B(rows,1) - B(death(k),1), nearest(rows), tCa, 'previous', NaN);
  end
end
S.aligned = struct('tSpawn', tSp, 'spawn', Asp, 'tCatch', tCa, 'catch', Aca, ...
  'chanceDist', median(nearest(visible), 'omitnan'));

%% Going to the reward spout after a catch
% The mouse is at the spout when its position is within spoutDist of it.
% From the touches the position can't go past the screen edge (the spout is
% beyond it), hence a larger default distance than with video tracking.
if isempty(o.spoutDist)
  if isempty(o.track); o.spoutDist = 7; else; o.spoutDist = 6; end
end
dSpout = hypot(mouseXY(:,1) - o.rewardPos(1), mouseXY(:,2) - o.rewardPos(2));
atSpout = dSpout <= o.spoutDist;
maxWait = 30; % s
latency = @(t0) spoutLatency(B(:,1), atSpout, t0, maxWait);
tr.spoutLatency = nan(nT, 1);
tr.spoutLatency(tr.caught) = latency(tr.tSpawn(tr.caught) + tr.timeToCatch(tr.caught));
% chance: from random times at which the mouse was as far from the spout as
% at a catch (+-2 cm) and not at it - at random times it is often already
% there, while at a catch it has left the spout to catch the bug
rs = RandStream('mt19937ar', 'Seed', 1);
tCatch = tr.tSpawn(tr.caught) + tr.timeToCatch(tr.caught);
dAtCatch = interp1(B(:,1), dSpout, tCatch);
okT = B(:,1) >= tStart0(B, alive) & B(:,1) <= B(end,1) - maxWait & ~atSpout & ~isnan(dSpout);
tRand = zeros(0, 1);
for k = 1:numel(tCatch)
  cand = find(okT & abs(dSpout - dAtCatch(k)) <= 2);
  if isempty(cand); continue; end
  tRand = [tRand; B(cand(randi(rs, numel(cand), 20, 1)),1)]; %#ok<AGROW>
end
latRand = latency(tRand);
tAl = -5:dtA:20;
alignedSpout = @(t0) interp1(B(:,1), dSpout, t0(:) + tAl, 'linear', NaN);
S.spout = struct('pos', o.rewardPos, 'dist', o.spoutDist, 'tAligned', tAl, ...
  'afterCatch', alignedSpout(K(:,1)), 'afterRandom', alignedSpout(tRand), ...
  'latencyRandom', latRand, 'maxWait', maxWait, 'fracTimeAtSpout', mean(atSpout, 'omitnan'));
S.trials = tr;

%% Summary
tStart = B(find(alive, 1),1); if isempty(tStart); tStart = B(1,1); end
S.trainingStage = P.trainingStage;
S.rewardSize = P.rewardSize;
S.environment = '';
if isfield(m, 'environment') && isstruct(m.environment); S.environment = m.environment.id; end
S.duration = B(end,1) - tStart; % s, from the first bug appearance
S.catches = size(K, 1);
S.rewarded = sum(K(:,4));
S.rewardVolume = S.rewarded * P.rewardSize; % ul
S.catchesPerMin = S.catches / S.duration * 60;
S.catchesPerVisibleMin = S.catches / visMin;
S.medianTimeToCatch = median(tr.timeToCatch, 'omitnan'); % caught trials
S.fracCaughtWithin10s = mean(tr.timeToCatch <= 10); % of all trials
% Finding the bug vs hitting it: time until a paw is within nearDist, and
% from there to the catch (caught trials that came near first)
both = tr.caught & ~isnan(tr.timeToNear);
S.medianTimeToNear = median(tr.timeToNear(both));
S.medianNearToCatch = median(tr.timeToCatch(both) - tr.timeToNear(both));
S.catchSpeedVsChance = mean(tr.chanceFaster, 'omitnan'); % 0.5 = chance
% to the spout: medians count "not within maxWait" as later than anything
lc = tr.spoutLatency(tr.caught); lc(isnan(lc)) = Inf;
lr = latRand; lr(isnan(lr)) = Inf;
S.medianSpoutLatency = median(lc);
S.chanceMedianSpoutLatency = median(lr);
S.fracSpoutWithin10s = mean(lc <= 10);
S.chanceFracSpoutWithin10s = mean(lr <= 10);
S.landingsPerMin = sum(L(:,7) >= tStart) / S.duration * 60;
S.medianLandingDist = median(dLand);
S.pursuitIndex = mean(pursuit); % -1 away from the bug ... 1 straight at it
S.chancePursuitIndex = mean(pursuitSh);
step = hypot(diff(mouseXY(:,1)), diff(mouseXY(:,2)));
S.distanceMovedPerMin = sum(step, 'omitnan') / S.duration * 60; % cm/min, touch-based
S.fractionVisible = mean(visible(B(:,1) >= tStart));
S.nearDist = o.nearDist;

binMin = 5;
edges = tStart + [0:binMin*60:S.duration, S.duration]; % last bin: the remainder
edges = unique(edges);
lenMin = diff(edges) / 60;
keep = lenMin >= binMin / 2; % drop a last bin shorter than half a bin (noisy)
cpm = histcounts(K(:,1), edges) ./ lenMin;
S.binned = struct('binMin', binMin, 'tMin', (edges(keep) - tStart) / 60 + lenMin(keep) / 2, ...
  'catchesPerMin', cpm(keep));
S.bugT = B(:,1);
S.nearest = nearest;
S.mouseXY = mouseXY;
S.tStart = tStart;
end

%% ===================== Helpers =====================

function [Ci, Cx, Cy] = contactsAtUpdates(tB, E)
%CONTACTSATUPDATES Contacts down at each bug update, as flat lists: update
%   index Ci and position (Cx, Cy) of each contact.
[~, ~, id] = unique(E(:,2));
pos = nan(max([id; 0]), 2);
down = false(max([id; 0]), 1);
nB = numel(tB);
cap = 8 * nB;
Ci = zeros(cap, 1); Cx = Ci; Cy = Ci;
n = 0; iE = 1; nE = size(E, 1);
for i = 1:nB
  while iE <= nE && E(iE,7) <= tB(i)
    down(id(iE)) = E(iE,1) ~= 4;
    pos(id(iE),:) = E(iE,3:4);
    iE = iE + 1;
  end
  a = find(down);
  if n + numel(a) > cap % grow
    cap = 2 * cap; Ci(cap) = 0; Cx(cap) = 0; Cy(cap) = 0;
  end
  Ci(n+1:n+numel(a)) = i;
  Cx(n+1:n+numel(a)) = pos(a,1);
  Cy(n+1:n+numel(a)) = pos(a,2);
  n = n + numel(a);
end
Ci = Ci(1:n); Cx = Cx(1:n); Cy = Cy(1:n);
end

function M = windowMean(t, X, tq, win)
%WINDOWMEAN Mean of the rows of X with times in (tq - win, tq] (NaN if none).
c = [zeros(1, size(X, 2)); cumsum(X, 1)];
hi = nAtOrBefore(t, tq);
lo = nAtOrBefore(t, tq - win);
n = hi - lo;
M = (c(hi + 1,:) - c(lo + 1,:)) ./ n;
M(n == 0,:) = NaN;
end

function [off, unc, score] = touchClockOffset(B, E, K, R)
%TOUCHCLOCKOFFSET Offset GetSecs - block time, from the catches: the bug is
%   caught at the first update at which a contact is within R of it, so at
%   the right offset each catch has a contact within R at its update and
%   none at the update before (while the bug was visible). Returns the
%   middle of the best-scoring offsets, their half-width (s) and the
%   fraction of catches that agree.
if isempty(K) || isempty(E)
  off = 0; unc = Inf; score = NaN;
  warning('mouseChaseMetrics:noOffset', 'No catches or touches: touch times not aligned to the bug');
  return
end
tB = B(:,1);
cRow = arrayfun(@(t) find(abs(tB - t) < 1e-6, 1), K(:,1));
prev = max(cRow - 1, 1);
prevVisible = B(prev,6) == 1 & B(prev,5) == 0;
[~, ~, id] = unique(E(:,2));
byId = cell(1, max(id));
for k = 1:max(id) % per contact id: its events, and their unique times
  r = find(id == k);
  [tu, last] = unique(E(r,7), 'last');
  byId{k} = struct('tu', tu, 'rows', r(last));
end
nK = size(K, 1);
rough = E(1,7) - tB(1);
for pass = 1:2
  if pass == 1
    cand = rough + (-30:0.01:30);
  else
    cand = off + (-0.1:0.0005:0.1);
  end
  % all catches x all candidate offsets at once
  now = anyWithin(K(:,1) + cand, repmat(K(:,2:3), numel(cand), 1), E, byId, R);
  before = anyWithin(tB(prev) + cand, repmat(B(prev,2:3), numel(cand), 1), E, byId, R);
  ok = reshape(now & ~(before & repmat(prevVisible, numel(cand), 1)), nK, []);
  sc = mean(ok, 1);
  best = sc == max(sc);
  run = bwlabelRuns(best);
  sizes = accumarray(run(run > 0)', 1);
  [~, biggest] = max(sizes);
  sel = cand(run == biggest);
  off = mean([sel(1) sel(end)]);
end
unc = (sel(end) - sel(1)) / 2 + 0.0005;
score = max(sc);
end

function t = tStart0(B, alive)
t = B(find(alive, 1),1);
if isempty(t); t = B(1,1); end
end

function lat = spoutLatency(t, atSpout, t0, maxWait)
%SPOUTLATENCY Time from each t0 until the mouse is at the spout (0 if it
%   already is; NaN if not within maxWait s).
lat = nan(numel(t0), 1);
for k = 1:numel(t0)
  w = find(t >= t0(k) & t <= t0(k) + maxWait);
  j = w(find(atSpout(w), 1));
  if ~isempty(j); lat(k) = t(j) - t0(k); end
end
end

function a = headingAngles(xy, v, bugXY, maxDist)
%HEADINGANGLES Angle from the heading (velocity v) to the bug, for the rows
%   where the bug is within maxDist of the mouse (position xy).
d = bugXY - xy;
near = hypot(d(:,1), d(:,2)) <= maxDist;
a = mod(atan2(d(near,2), d(near,1)) - atan2(v(near,2), v(near,1)) + pi, 2 * pi) - pi;
end

function n = nAtOrBefore(t, q)
%NATORBEFORE Number of elements of sorted t that are <= q (for each q).
i = lastAtOrBefore(t, q);
n = i; n(isnan(n)) = 0;
end

function i = lastAtOrBefore(t, q)
%LASTATORBEFORE Index of the last element of sorted t that is <= q (NaN if
%   none), for each q. Works with repeated values in t.
[tu, last] = unique(t(:), 'last');
k = discretize(q(:), [tu; inf]);
i = nan(numel(q), 1);
i(~isnan(k)) = last(k(~isnan(k)));
end

function lab = bwlabelRuns(b)
d = diff([0 b(:)' 0]);
starts = find(d == 1); stops = find(d == -1) - 1;
lab = zeros(1, numel(b));
for k = 1:numel(starts); lab(starts(k):stops(k)) = k; end
end

function w = anyWithin(q, xy, E, byId, R)
%ANYWITHIN For each query time q (GetSecs), is any contact down within R of xy?
q = q(:);
w = false(numel(q), 1);
for k = 1:numel(byId)
  last = discretize(q, [byId{k}.tu; inf]); % last event of this contact <= q
  ok = ~isnan(last);
  j = byId{k}.rows(last(ok));
  down = E(j,1) ~= 4;
  ok(ok) = down;
  j = j(down);
  w(ok) = w(ok) | hypot(E(j,3) - xy(ok,1), E(j,4) - xy(ok,2)) <= R;
end
end
