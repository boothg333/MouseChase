function C = mouseChaseCatchTable(m, folder, varargin)
%MOUSECHASECATCHTABLE One row per catch: what made it, from the touches
%   (what the task could use online) and from the video (what it really was).
%   C = MOUSECHASECATCHTABLE(M, FOLDER) for a loaded session (mouseChaseLoad)
%   returns a table with, per catch:
%     session      expRef, trainingStage, catchMargin, snoutReach, bugLength
%     catch        catch (number), t (block time), rewarded
%     contact      the contact that made the catch: source ('logged': from
%                  the log's catchContact; 'rebuilt': the contact nearest the
%                  bug's outline at the catch, for logs without it), id, x, y,
%                  w, h (cm), area (w*h), maxW/maxH (largest so far in its
%                  life), age (s since it landed), pathLen (cm moved since it
%                  landed), speed and closing (cm/s over the last 0.1 s;
%                  closing: towards the bug), dOutline (cm from the bug's
%                  outline), snout (caught thanks to snoutReach)
%     others       nOthers (other contacts down), dNearestOther (cm),
%                  dCentroid (cm from the centroid of the other contacts),
%                  dTouchMouse (cm from the touch-based mouse position, see
%                  mouseChaseMetrics), behind (cm the contact lies behind the
%                  other contacts' centroid, along the mouse's touch-based
%                  heading: a tail trails)
%     video        (with a track, see mouseChaseTrack) videoType ('paw',
%                  'tail', 'none'; 'unseen' if the contact wasn't in the
%                  tracked frames, or there is no track), dBody, dTail (cm), bodyDist (cm, body
%                  centre to the bug), bodySpeed (cm/s), bodyHeadingToBug
%                  (deg, 0 = heading for the bug), bodyApproach (cm the body
%                  came closer to the bug over the last 1 s)
%     outcome      spoutLatency (s from the catch to the spout; NaN: not
%                  within the spout window, see mouseChaseMetrics)
%   Options (name, value):
%     'track'    mouseChaseTrack's result (default: computed or loaded from
%                its cache; [] or false: no video columns)
%     'metrics'  mouseChaseMetrics' result (default: computed)
%   Feature definitions are meant to be computable in MouseChaseTouch from
%   the contacts alone, except the video and outcome columns.

o = struct('track', 'auto', 'metrics', []);
for k = 1:2:numel(varargin); o.(varargin{k}) = varargin{k+1}; end
if ischar(o.track) && strcmp(o.track, 'auto'); o.track = mouseChaseTrack(m, folder); end
if islogical(o.track) && ~o.track; o.track = []; end
Tk = o.track;
S = o.metrics;
if isempty(S)
  if isempty(Tk); S = mouseChaseMetrics(m, 'nShuffle', 2);
  else; S = mouseChaseMetrics(m, 'nShuffle', 2, 'track', Tk); end
end

E = S.touches; % [type id x y w h time], block time, sorted
B = m.bug;
K = m.catchLog;
nK = size(K, 1);
P = struct('trainingStage', NaN, 'catchMargin', NaN, 'snoutReach', 0, 'bugLength', NaN, ...
  'bugWidth', NaN, 'catchRadius', 3);
if isstruct(m.params)
  for f = fieldnames(P)'
    if isfield(m.params, f{1}); P.(f{1}) = m.params.(f{1}); end
  end
end
hasLogged = isfield(m, 'catchContact') && size(m.catchContact, 1) == nK;

names = {'catch', 't', 'rewarded', 'id', 'x', 'y', 'w', 'h', 'area', 'maxW', 'maxH', 'age', ...
  'pathLen', 'speed', 'closing', 'dOutline', 'snout', 'nOthers', 'dNearestOther', 'dCentroid', ...
  'dTouchMouse', 'behind', 'dBody', 'dTail', 'bodyDist', 'bodySpeed', 'bodyHeadingToBug', ...
  'bodyApproach', 'spoutLatency'};
X = nan(nK, numel(names));
source = strings(nK, 1);
videoType = repmat("unseen", nK, 1);

% catch -> trial, for the spout latency
tr = S.trials;
tCatchTr = tr.tSpawn + tr.timeToCatch;

for k = 1:nK
  t = K(k,1);
  rB = find(abs(B(:,1) - t) < 1e-6, 1);
  bug = B(rB,2:4);
  down = contactsDown(E, t);
  if isempty(down); continue; end
  d = bugDistance(down(:,2:3), bug, P);
  if hasLogged && ~isnan(m.catchContact(k,1))
    i = find(down(:,1) == m.catchContact(k,1), 1);
    source(k) = "logged";
    if isempty(i) % (touch reports and game updates are not quite in step)
      [~, i] = min(d); source(k) = "logged (id not found: nearest)";
    end
  else
    [~, i] = min(d);
    source(k) = "rebuilt";
  end
  id = down(i,1);
  r = struct();
  r.catch = k; r.t = t; r.rewarded = K(k,4);
  r.id = id; r.x = down(i,2); r.y = down(i,3); r.w = down(i,4); r.h = down(i,5);
  r.area = r.w * r.h;
  r.dOutline = d(i);
  r.snout = r.dOutline > P.catchMargin; % NaN margin (old sessions): false
  if hasLogged && size(m.catchContact, 2) >= 7; r.snout = m.catchContact(k,7) == 1; end

  % its life since it landed
  life = contactLife(E, id, t);
  r.age = t - life(1,7);
  r.maxW = max(life(:,5)); r.maxH = max(life(:,6));
  r.pathLen = sum(hypot(diff(life(:,3)), diff(life(:,4))));
  if hasLogged; r.age = m.catchContact(k,6); end % (the game's own value)
  % velocity over the last 0.1 s (or since landing)
  t0 = max(t - 0.1, life(1,7));
  p0 = interp1Safe(life(:,7), life(:,3:4), t0);
  if t - t0 > 0.005
    v = ([r.x r.y] - p0) / (t - t0);
  else
    v = [0 0];
  end
  r.speed = hypot(v(1), v(2));
  toBug = bug(1:2) - [r.x r.y];
  r.closing = dot(v, toBug / max(norm(toBug), eps));

  % the other contacts
  oth = down(setdiff(1:size(down, 1), i), 2:3);
  r.nOthers = size(oth, 1);
  if r.nOthers > 0
    r.dNearestOther = min(hypot(oth(:,1) - r.x, oth(:,2) - r.y));
    cen = mean(oth, 1);
    r.dCentroid = hypot(cen(1) - r.x, cen(2) - r.y);
  else
    r.dNearestOther = NaN; r.dCentroid = NaN; cen = [NaN NaN];
  end
  rM = find(S.bugT <= t, 1, 'last');
  mxy = S.mouseXY(rM,:);
  r.dTouchMouse = hypot(mxy(1) - r.x, mxy(2) - r.y);
  % heading of the paws' centroid over the last 0.5 s (touch-based)
  rPrev = find(S.bugT <= t - 0.5, 1, 'last');
  if ~isempty(rPrev) && r.nOthers > 0
    mv = S.mouseXY(rM,:) - S.mouseXY(rPrev,:);
    if norm(mv) > 0.5 % moved: else no heading
      r.behind = dot(cen - [r.x r.y], mv / norm(mv));
    else
      r.behind = NaN;
    end
  else
    r.behind = NaN;
  end

  % video
  r.dBody = NaN; r.dTail = NaN; r.bodyDist = NaN; r.bodySpeed = NaN;
  r.bodyHeadingToBug = NaN; r.bodyApproach = NaN;
  if ~isempty(Tk)
    TC = Tk.contacts;
    j = find(TC.id == id & TC.t <= t + 0.02 & TC.t >= t - 0.1);
    if ~isempty(j)
      [~, jj] = max(TC.t(j)); j = j(jj);
      videoType(k) = string(TC.type(j));
      r.dBody = TC.dBody(j); r.dTail = TC.dTail(j);
    end
    b1 = interp1Safe(Tk.t, Tk.xy, t);
    b0 = interp1Safe(Tk.t, Tk.xy, t - 0.3);
    bA = interp1Safe(Tk.t, Tk.xy, t - 1);
    r.bodyDist = norm(bug(1:2) - b1);
    bv = (b1 - b0) / 0.3;
    r.bodySpeed = norm(bv);
    if r.bodySpeed > 2
      tb = bug(1:2) - b1;
      r.bodyHeadingToBug = rad2deg(mod(atan2(tb(2), tb(1)) - atan2(bv(2), bv(1)) + pi, 2 * pi) - pi);
    end
    r.bodyApproach = norm(bug(1:2) - bA) - r.bodyDist;
  end

  % outcome
  it = find(abs(tCatchTr - t) < 1e-3, 1);
  r.spoutLatency = NaN;
  if ~isempty(it); r.spoutLatency = tr.spoutLatency(it); end

  X(k,:) = cellfun(@(n) double(r.(n)), names);
end

C = array2table(X, 'VariableNames', names);
C.source = source;
C.videoType = categorical(videoType, ["paw" "tail" "none" "unseen"]);
C.snout = C.snout == 1;
C.rewarded = C.rewarded == 1;
n = height(C);
C = [table(repmat(string(m.expRef), n, 1), repmat(P.trainingStage, n, 1), ...
  repmat(P.catchMargin, n, 1), repmat(P.snoutReach, n, 1), repmat(P.bugLength, n, 1), ...
  'VariableNames', {'expRef', 'trainingStage', 'catchMargin', 'snoutReach', 'bugLength'}), C];
end

%% ===================== Helpers =====================

function down = contactsDown(E, t)
%CONTACTSDOWN Contacts down at block time t: [id x y w h], from each id's
%   last event at or before t (within 0.25 s, not a lift).
recent = E(E(:,7) <= t & E(:,7) > t - 0.25,:);
down = zeros(0, 5);
if isempty(recent); return; end
[~, last] = unique(recent(:,2), 'last');
L = recent(last,:);
L = L(L(:,1) ~= 4,:);
down = L(:,2:6);
end

function life = contactLife(E, id, t)
%CONTACTLIFE Events of contact id from its last landing at or before t
%   to t (ids are reused, so from the last begin event).
ev = E(E(:,2) == id & E(:,7) <= t,:);
b = find(ev(:,1) == 2, 1, 'last');
if isempty(b); b = 1; end
life = ev(b:end,:);
end

function y = interp1Safe(x, Y, xq)
%INTERP1SAFE Linear interpolation that tolerates repeated x (keeps the last).
[xu, last] = unique(x(:), 'last');
if numel(xu) < 2; y = Y(end,:); return; end
y = interp1(xu, Y(last,:), xq, 'linear', NaN);
end

function d = bugDistance(xy, bug, P)
%BUGDISTANCE Distance (cm) the game used: from the bug's outline, or for
%   old sessions (no catchMargin) from within catchRadius of its centre.
if isnan(P.catchMargin)
  d = hypot(xy(:,1) - bug(1), xy(:,2) - bug(2)) - P.catchRadius;
else
  d = outlineDistance(xy, bug(1:2), bug(3), P.bugLength, P.bugWidth);
end
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
