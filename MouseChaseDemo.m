function MouseChaseDemo(t, events, p, visStim, inputs, outputs, ~) %#ok<INUSL>
%MOUSECHASEDEMO Signals experiment definition: a mouse chases a virtual bug.
%   A bug wanders over a touchscreen floor, hides under objects and flees
%   from moving touches. Touches come from the multi-touch overlay (paws,
%   tail), read by tools/touchReader.ps1 in the background (Windows raw
%   input, no Psychtoolbox touch support needed).
%   When any contact lands within p.catchRadius of the visible bug, the
%   trial ends, a reward of p.rewardSize ul is delivered with probability
%   p.rewardProbability, and the bug respawns from the screen edge after
%   p.respawnDelay seconds.
%
%   One trial = one catch, and the game reads the current trial's
%   parameters, so trial types (e.g. bug difficulty) can be made with
%   Rigbox conditional parameters: give a parameter one column per type.
%
%   The session stops after p.targetCatches catches, after p.maxDuration
%   seconds (both may be Inf), when mc's End button is pressed, or after
%   numRepeats trials (Rigbox default 1000; raise it in mc for more).
%
%   World coordinates are centimetres on the screen surface, origin at the
%   screen centre, x rightwards and y upwards. They are converted to the
%   visual degrees Signals draws in using the screen geometry stored in the
%   rig's hardware.mat (field 'touchScreen', written by
%   tools/configureTouchScreenRig.m), which must match rig.screens.
%
%   Environments (floor and hiding objects) are loaded by name from the
%   MouseChaseEnvironments folder next to this file; see loadEnvironment.
%
%   Logged events (besides Rigbox's own):
%     bug          [x y heading hidden alive]' every update (cm, rad); saved
%                  as a 5 x nUpdates matrix
%     touches      {N x 8 [id x y w h vx vy age]} active contacts (cm, cm/s,
%                  s); one cell per update
%     touchEvents  {M x 7 [type id x y w h time]} raw touch events
%                  (type 2 begin, 3 move, 4 end, 5 all touches lost)
%     catches      catch count, updating at each catch
%     rewarded     at each catch: true if it was rewarded

%% Shared, mutable context (touch queue, screen geometry)
% A containers.Map is a handle object, so the callbacks below all see and
% update the same instance. Nothing touching hardware runs at definition
% time: mc also runs this function (with dummy signals) to read parameters.
ctx = containers.Map();
% Resolve file locations now: Rigbox removes this folder from the path once
% the definition has run, so they can't be found from the callbacks later
envDir = fullfile(fileparts(mfilename('fullpath')), 'MouseChaseEnvironments');
ctx('readerScript') = fullfile(fileparts(mfilename('fullpath')), 'tools', 'touchReader.ps1');

%% Parameters
% The game functions receive the whole parameter struct, but mc only lists
% parameters that are referenced as p.<name> here, so reference them all.
gamePars = {'rewardProbability', 'catchRadius', 'respawnDelay', 'bugLength', 'bugWidth', ...
  'visualRange', 'threatSpeed', 'landingThreatTime', 'obstacleRange', ...
  'escapeGain', 'maxEscapeThrust', 'wanderThrust', 'wanderNoise', ...
  'friction', 'maxTurnRate', 'creviceDepth', 'showTouches'};
for iPar = 1:numel(gamePars); p.(gamePars{iPar}); end

%% Environment
% Derived from expStart rather than directly from p.environment: during
% parameter inference anything derived from p is p itself, and subscripting
% it (floor.image etc.) would add bogus parameters.
env = events.expStart.map2(p.environment.skipRepeats(), ...
  @(~, id) loadEnvironment(id, envDir));

%% Game state, advanced p.updateRate times per second after experiment start
% Every update recomputes the scene and makes Rigbox redraw; updating less
% often than the screen refreshes leaves more time per update, so frames
% aren't late (late frames show as a flickering band at the top)
running = events.expStart.then(true);
tick = t.map2(p.updateRate, @(x, rate) floor(x * rate)).skipRepeats();
tRun = t.at(tick).keepWhen(running);
seed = struct('t', [], 'pos', [0 0], 'vel', [0 0], 'heading', 0, ...
  'wanderAngle', 0, 'hidden', true, 'alive', false, 'respawnAt', -inf, ...
  'catchCount', 0, 'lastCatchRewarded', false, 'evading', false, ...
  'contacts', zeros(0, 8), 'touchEvents', zeros(0, 7));
state = tRun.scan(@(s, tNow, P, e) updateGame(s, tNow, P, e, ctx), seed, ...
  'pars', p, env).subscriptable();

%% Catches, reward, trials and stopping
catchCount = state.catchCount.skipRepeats();
catchEvent = catchCount.keepWhen(catchCount > 0);
events.endTrial = catchEvent;
events.catches = catchEvent;
% Whether a catch is rewarded is drawn in updateGame (p.rewardProbability)
rewarded = state.lastCatchRewarded.at(catchEvent);
events.rewarded = rewarded;
outputs.reward = p.rewardSize.at(rewarded); % only fires when rewarded is true
events.totalReward = outputs.reward.scan(@plus, 0);

elapsed = t - t.at(events.expStart);
stop = (state.catchCount >= p.targetCatches) | (elapsed >= p.maxDuration);
events.expStop = stop.skipRepeats().then(true);
% Hand the touch device back when the session ends (it is also reset at
% the start of the next session, in case this never runs)
events.touchReleased = events.expStop.map(@(~) releaseTouch(ctx));

%% Logging
% Rigbox saves an event's values side by side ([log.value]), so values
% must keep the same number of rows: the bug state is a column, and the
% touch matrices (one row per contact) are wrapped in cells. Doubly: the
% logger stores values with struct('value', v), which strips one layer.
events.bug = state.map(@(s) [s.pos s.heading s.hidden s.alive]');
events.touches = state.contacts.skipRepeats().map(@(c) {{c}});
touchEvents = state.touchEvents;
events.touchEvents = touchEvents.keepWhen(touchEvents.map(@(e) ~isempty(e))).map(@(e) {{e}});
events.evading = state.evading.skipRepeats();
events.environment = env.map(@(e) {{e.id}});

%% Visual stimuli
% Signals draws layers in alphabetical order of their names, hence the
% prefixes: floor, then bug, then hiding objects (which cover the bug),
% then optional touch markers.
floorDraw = env.map(@(e) floorToDraw(e, ctx)).subscriptable();
floorImg = vis.image(t);
floorImg.sourceImage = floorDraw.image;
floorImg.dims = floorDraw.dims;
floorImg.repeat = floorDraw.repeat;
floorImg.azimuth = 0;
floorImg.altitude = 0;
floorImg.show = true;
visStim.a_floor = floorImg;

bugDraw = state.map2(p, @(s, P) bugToDraw(s, P, ctx)).subscriptable();
bug = vis.patch(t, 'circle');
bug.azimuth = bugDraw.azimuth;
bug.altitude = bugDraw.altitude;
bug.dims = bugDraw.dims;
bug.orientation = bugDraw.orientation;
bug.colour = p.bugColour;
bug.show = bugDraw.show;
visStim.b_bug = bug;

% Fixed pools of rectangle and ellipse patches; the environment decides
% how many are shown and where.
nPool = 6;
objDraw = env.map(@(e) objectsToDraw(e, nPool, ctx));
shapes = {'rectangle', 'circle'};
for iShape = 1:2
  for k = 1:nPool
    o = objDraw.map(@(d) d(iShape, k)).skipRepeats().subscriptable();
    obj = vis.patch(t, shapes{iShape});
    obj.azimuth = o.azimuth;
    obj.altitude = o.altitude;
    obj.dims = o.dims;
    obj.orientation = o.orientation;
    obj.colour = o.colour;
    obj.show = o.show;
    visStim.(sprintf('c_%s%02d', shapes{iShape}(1:4), k)) = obj;
  end
end

% Touch markers, for checking that drawn positions line up with touches
nMarkers = 10;
% Only computed while p.showTouches is on: the markers cost time every frame
markerDraw = state.keepWhen(p.showTouches).map2(p, @(s, P) touchesToDraw(s, P, nMarkers, ctx));
for k = 1:nMarkers
  % skipRepeats: an unchanged (e.g. hidden) marker must not trigger the
  % costly layer update every frame
  m = markerDraw.map(@(d) d(k)).skipRepeats().subscriptable();
  marker = vis.patch(t, 'circle');
  marker.azimuth = m.azimuth;
  marker.altitude = m.altitude;
  marker.dims = m.dims;
  marker.colour = [1 0 0]';
  marker.show = m.show;
  visStim.(sprintf('d_touch%02d', k)) = marker;
end

%% Experimenter parameters (defaults)
try
  p.rewardSize = 5;          % ul per rewarded catch
  p.rewardProbability = 0.8; % chance that a catch is rewarded
  p.targetCatches = 250;     % stop after this many catches (Inf allowed)
  p.maxDuration = 3600;      % stop after this many seconds (Inf allowed)
  p.environment = 'default'; % name of a MouseChaseEnvironments/<name>.mat
  p.catchRadius = 1.5;       % cm, contact-to-bug-centre distance for a catch
  p.respawnDelay = 2;        % s the bug stays away after a catch
  p.bugLength = 2.4;         % cm
  p.bugWidth = 0.9;          % cm
  p.bugColour = [0 0 0]';
  p.visualRange = 21;        % cm, distance at which contacts can scare the bug
  p.threatSpeed = 4.5;       % cm/s, contacts moving faster than this scare it
  p.landingThreatTime = 0.2; % s, newly landed contacts scare it this long
  p.obstacleRange = 2;       % cm, bug steers around still contacts this close
  p.escapeGain = 35;         % 1/s^2, escape thrust per cm inside visualRange
  p.maxEscapeThrust = 600;   % cm/s^2
  p.wanderThrust = 24;       % cm/s^2 (terminal wander speed = thrust/friction)
  p.wanderNoise = 3;         % rad/s, random drift of the wander heading
  p.friction = 6;            % 1/s
  p.maxTurnRate = 8;         % rad/s
  p.creviceDepth = 4.5;      % cm the bug may go past the screen edge
  p.showTouches = false;     % draw red markers on active contacts (costly: checks only)
  p.updateRate = 30;         % game/screen updates per second (60 = every frame)
catch
end
end

%% ===================== Game logic =====================

function s = updateGame(s, tNow, P, env, ctx)
%UPDATEGAME Advance the bug by one Signals update.
g = geometry(ctx);
if isempty(s.t) % first update: start with the bug entering from an edge
  s.t = tNow;
  s = spawnBug(s, g, P);
end
dt = min(max(tNow - s.t, 0), 0.1); % cap to avoid jumps after a stall
s.t = tNow;
[s.contacts, s.touchEvents] = pollTouches(ctx);

if ~s.alive
  s.evading = false;
  if tNow >= s.respawnAt
    s = spawnBug(s, g, P);
  end
  return
end

half = g.dimsCm / 2;
onScreen = all(abs(s.pos) <= half);
s.hidden = ~onScreen || isUnderObject(s.pos, env.objects);

% Threats and obstacles from the current contacts
C = s.contacts;
nC = size(C, 1);
if nC > 0
  rel = [s.pos(1) - C(:,2), s.pos(2) - C(:,3)];
  d = hypot(rel(:,1), rel(:,2));
  speed = hypot(C(:,6), C(:,7));
  isThreat = (speed > P.threatSpeed | C(:,8) < P.landingThreatTime) & ...
    d < P.visualRange & d > 0;
  isObstacle = ~isThreat & d < P.obstacleRange & d > 0;
else
  isThreat = false(0, 1);
  isObstacle = false(0, 1);
end

s.evading = ~s.hidden && any(isThreat);
if s.evading
  % Flee along the summed push of all threats, nearer ones pushing harder
  w = P.visualRange - d(isThreat);
  push = sum(w .* rel(isThreat,:) ./ d(isThreat), 1);
  desiredHeading = atan2(push(2), push(1));
  thrust = min(P.escapeGain * max(w), P.maxEscapeThrust);
  s.wanderAngle = desiredHeading;
else
  s.wanderAngle = s.wanderAngle + randn() * P.wanderNoise * dt;
  wanderDir = [cos(s.wanderAngle), sin(s.wanderAngle)];
  if any(isObstacle) % steer around still paws
    away = sum(rel(isObstacle,:) ./ d(isObstacle), 1);
    wanderDir = wanderDir + 2 * away;
  end
  desiredHeading = atan2(wanderDir(2), wanderDir(1));
  thrust = P.wanderThrust;
end

% Non-holonomic motion: turn at a limited rate, thrust along the heading,
% no sideways skidding
deltaAngle = mod(desiredHeading - s.heading + pi, 2 * pi) - pi;
s.heading = s.heading + sign(deltaAngle) * min(abs(deltaAngle), P.maxTurnRate * dt);
headingVec = [cos(s.heading), sin(s.heading)];
vel = s.vel + headingVec * thrust * dt - P.friction * s.vel * dt;
s.vel = max(0, dot(vel, headingVec)) * headingVec;
prevPos = s.pos;
s.pos = s.pos + s.vel * dt;

% The bug can go a little past the screen edge ("crevice"), then turns back
limit = half + P.creviceDepth;
clamped = min(max(s.pos, -limit), limit);
hitWall = any(clamped ~= s.pos);
s.pos = clamped;
% Areas the mouse physically cannot reach (e.g. the box over the sync
% square) are walls, so the bug cannot shelter there
for b = 1:size(g.blockedCm, 1)
  if isInsideRect(s.pos, g.blockedCm(b,:), P.bugLength / 2)
    s.pos = prevPos;
    hitWall = true;
  end
end
if hitWall
  s.wanderAngle = atan2(-s.pos(2), -s.pos(1)); % head back to the centre
  s.vel = [0 0];
end

% Catch: any contact on the visible bug
if ~s.hidden && nC > 0 && any(hypot(C(:,2) - s.pos(1), C(:,3) - s.pos(2)) <= P.catchRadius)
  s.catchCount = s.catchCount + 1;
  s.lastCatchRewarded = rand() < P.rewardProbability;
  s.alive = false;
  s.evading = false;
  s.respawnAt = tNow + P.respawnDelay;
end
end

function s = spawnBug(s, g, P)
%SPAWNBUG Place the bug in the crevice beyond a random screen edge, facing in.
half = g.dimsCm / 2;
depth = P.creviceDepth / 2;
side = randi(4);
along = (rand() - 0.5) * 1.6; % keep away from the corners
switch side
  case 1, s.pos = [-half(1) - depth, along * half(2)];
  case 2, s.pos = [half(1) + depth, along * half(2)];
  case 3, s.pos = [along * half(1), -half(2) - depth];
  case 4, s.pos = [along * half(1), half(2) + depth];
end
for b = 1:size(g.blockedCm, 1) % never start next to a blocked area
  if isInsideRect(s.pos, g.blockedCm(b,:), P.creviceDepth + P.bugLength)
    s.pos = -s.pos;
  end
end
s.heading = atan2(-s.pos(2), -s.pos(1)) + (rand() - 0.5);
s.wanderAngle = s.heading;
s.vel = [0 0];
s.alive = true;
s.hidden = true;
end

function hidden = isUnderObject(pos, objects)
hidden = false;
for k = 1:numel(objects)
  o = objects(k);
  a = -o.angle * pi / 180; % into the object's own frame
  r = [cos(a) -sin(a); sin(a) cos(a)] * (pos(:) - o.centre(:));
  switch o.shape
    case 'rectangle'
      inside = all(abs(r') <= o.size / 2);
    otherwise % ellipse
      inside = sum((2 * r' ./ o.size) .^ 2) <= 1;
  end
  if inside; hidden = true; return; end
end
end

function inside = isInsideRect(pos, rect, margin)
% rect = [xmin ymin xmax ymax] in cm
inside = pos(1) >= rect(1) - margin && pos(1) <= rect(3) + margin && ...
  pos(2) >= rect(2) - margin && pos(2) <= rect(4) + margin;
end

%% ===================== Touch input =====================
% Touches come from tools/touchReader.ps1, a hidden background process that
% reads the overlay through Windows raw input and sends every HID report to
% a UDP port here. (Psychtoolbox's TouchQueue isn't usable on this Windows
% 11 rig: it covers the stimulus window with a window of its own.)

function [contacts, raw] = pollTouches(ctx)
%POLLTOUCHES Read all touch reports since the last call.
%   contacts: N x 8 [id x y w h vx vy age] of the contacts currently down
%   raw: M x 7 [type id x y w h time] touch events derived from the reports
%     (type 2 begin, 3 move, 4 end); positions in cm, time in GetSecs
contacts = zeros(0, 8);
raw = zeros(0, 7);
if isKey(ctx, 'released'); return; end % session over: ignore input
if ~isKey(ctx, 'tracks'); openTouch(ctx); end
g = geometry(ctx);
tracks = ctx('tracks'); % [id x y w h vx vy tBegin tLast]
ch = ctx('channel');
buf = ctx('buffer');
while true
  buf.clear();
  from = ch.receive(buf);
  if isempty(from); break; end
  ctx('readerAddr') = from;
  bytes = typecast(buf.array(), 'uint8');
  [tracks, raw] = handleReport(ctx, char(bytes(1:buf.position())'), tracks, raw, g);
end
% Drop contacts that stopped reporting (in case a lift report was lost):
% the overlay reports every contact ~60 times/s, even when it holds still
tNow = GetSecs;
stale = tNow - tracks(:,9) > 0.25;
for i = find(stale)'
  raw(end+1,:) = [4 tracks(i,1:5) tNow]; %#ok<AGROW>
end
tracks(stale,:) = [];
ctx('tracks') = tracks; %#ok<NASGU> ctx is a handle (containers.Map)
contacts = [tracks(:,1:7), tNow - tracks(:,8)];
end

function [tracks, raw] = handleReport(ctx, msg, tracks, raw, g)
%HANDLEREPORT Turn one message from the touch reader into touch events.
lines = strsplit(strtrim(msg), newline);
switch strtok(lines{1})
  case 'HELLO' % 'HELLO <xMax> <yMax>': the overlay's logical coordinate range
    v = sscanf(lines{1}(6:end), '%f');
    if numel(v) == 2 && all(v > 0); ctx('logicalMax') = v(:)'; end %#ok<NASGU>
  case 'R' % 'R <reader time> <contact count>', then 'id tip x y w h' per contact
    v = sscanf(lines{1}(2:end), '%f');
    % Reader clock -> GetSecs: the smallest receive delay seen is the offset
    offset = min(ctx('timeOffset'), GetSecs - v(1));
    ctx('timeOffset') = offset;
    time = v(1) + offset;
    scale = 1 ./ ctx('logicalMax');
    for k = 2:numel(lines)
      c = sscanf(lines{k}, '%f')';
      if numel(c) < 6; continue; end
      xy = px2cm(c(3:4) .* scale .* g.pxSize, g);
      wh = c(5:6) .* scale .* g.dimsCm;
      known = any(tracks(:,1) == c(1));
      if c(2) % finger down
        type = 2 + known;
      elseif known % lifted
        type = 4;
      else
        continue
      end
      raw(end+1,:) = [type c(1) xy wh time]; %#ok<AGROW>
      tracks = updateTrack(tracks, type, c(1), xy, wh, time);
    end
end
end

function tracks = updateTrack(tracks, type, id, xy, wh, time)
i = find(tracks(:,1) == id, 1);
switch type
  case 2 % touch begins
    if ~isempty(i); tracks(i,:) = []; end
    tracks(end+1,:) = [id xy wh 0 0 time time];
  case 3 % touch moves
    if isempty(i) % missed the begin event
      tracks(end+1,:) = [id xy wh 0 0 time time];
      return
    end
    dtE = time - tracks(i,9);
    if dtE > 0
      v = (xy - tracks(i,2:3)) / dtE;
      tracks(i,6:7) = 0.5 * tracks(i,6:7) + 0.5 * v; % light smoothing
      tracks(i,9) = time;
    end
    tracks(i,2:5) = [xy wh];
  case 4 % touch ends
    if ~isempty(i); tracks(i,:) = []; end
end
end

function openTouch(ctx)
%OPENTOUCH Open a local UDP port and start the background touch reader.
ctx('tracks') = zeros(0, 9);
ctx('timeOffset') = inf;
ctx('logicalMax') = [32767 32767]; % until the reader reports the overlay's range
ch = java.nio.channels.DatagramChannel.open();
ch.configureBlocking(false);
port = str2double(getenv('MOUSECHASE_TOUCH_PORT')); % set by tools/simulation
startReader = isnan(port);
if startReader; port = 0; end % any free port
ch.bind(java.net.InetSocketAddress('127.0.0.1', port));
ctx('channel') = ch;
ctx('buffer') = java.nio.ByteBuffer.allocate(8192);
if ~startReader; return; end
script = ctx('readerScript');
if ~ispc || ~exist(script, 'file')
  warning('MouseChase:noTouch', 'Touch reader %s not found: no touch input.', script);
  return
end
% Hidden and in the background (start /b), so no window appears and the
% game doesn't wait for PowerShell; builtin because a mock system.m may
% shadow the real one on the rig
builtin('system', sprintf(['start "" /b powershell -NoProfile -ExecutionPolicy Bypass ' ...
  '-WindowStyle Hidden -File "%s" -Port %d -ParentPid %d -LogFile "%s"'], script, ...
  ch.socket().getLocalPort(), feature('getpid'), 'C:\LocalExpData\touchReader.log'));
end

function ok = releaseTouch(ctx)
%RELEASETOUCH Stop the touch reader and close the UDP port.
ok = true;
ctx('released') = true;
if ~isKey(ctx, 'channel'); return; end
ch = ctx('channel');
try
  if isKey(ctx, 'readerAddr')
    ch.send(java.nio.ByteBuffer.wrap(int8('QUIT')), ctx('readerAddr'));
  end
  ch.close();
catch
end
end

%% ===================== Screen geometry =====================

function g = geometry(ctx)
%GEOMETRY Screen size in pixels and cm, and the viewing distance that
%   defines the degrees Signals draws in. Read once from the rig's
%   hardware.mat ('touchScreen'); falls back to POPPY-STIM's values.
if isKey(ctx, 'geom'); g = ctx('geom'); return; end
g = struct('pxSize', [1280 1024], 'dimsCm', [37.6 30.1], 'distanceCm', 100, ...
  'blockedPx', zeros(0, 4));
try
  rigCfg = getOr(dat.paths, 'rigConfig');
  s = load(fullfile(rigCfg, 'hardware.mat'), 'touchScreen');
  if isfield(s, 'touchScreen')
    for f = fieldnames(s.touchScreen)'
      g.(f{1}) = s.touchScreen.(f{1});
    end
  else
    warning('MouseChase:noGeometry', ...
      'No touchScreen field in %s; using default screen geometry.', rigCfg);
  end
catch ex
  warning('MouseChase:noGeometry', 'Could not load screen geometry: %s', ex.message);
end
g.cmPerPx = g.dimsCm ./ g.pxSize;
g.blockedCm = zeros(size(g.blockedPx, 1), 4);
for b = 1:size(g.blockedPx, 1) % [left top right bottom] px -> [xmin ymin xmax ymax] cm
  c1 = px2cm(g.blockedPx(b,[1 4]), g);
  c2 = px2cm(g.blockedPx(b,[3 2]), g);
  g.blockedCm(b,:) = [c1 c2];
end
ctx('geom') = g; %#ok<NASGU>
end

function xy = px2cm(px, g)
xy = [(px(1) - g.pxSize(1) / 2) * g.cmPerPx(1), ...
  (g.pxSize(2) / 2 - px(2)) * g.cmPerPx(2)];
end

function [azAlt, degPerCm] = cm2deg(xy, g)
%CM2DEG Screen position (cm, y up) to Signals [azimuth altitude] (deg) for
%   a flat screen straight ahead at g.distanceCm, plus the local size scale
%   (deg per cm). NB Signals' altitude increases DOWN the screen.
D = g.distanceCm;
x = xy(1); y = xy(2);
azAlt = [atan2d(x, D), -atan2d(y, hypot(x, D))];
degPerCm = (180 / pi) * mean([D / (x^2 + D^2), hypot(x, D) / (x^2 + y^2 + D^2)]);
end

function [az, alt, degPerCm] = patchPosition(xy, angleDeg, g)
%PATCHPOSITION Azimuth/altitude to give a Signals patch so that, rotated by
%   angleDeg (anticlockwise on screen), its centre is drawn at xy (cm).
%   Signals' shader rotates a texture about [0 0] *before* offsetting it, so
%   a rotated patch at azimuth/altitude A is drawn at R(angle)^-1 * A; the
%   offset is therefore pre-rotated here.
[azAlt, degPerCm] = cm2deg(xy, g);
off = [cosd(angleDeg) -sind(angleDeg); sind(angleDeg) cosd(angleDeg)] * azAlt(:);
az = off(1);
alt = off(2);
end

%% ===================== Drawing =====================

function d = bugToDraw(s, P, ctx)
g = geometry(ctx);
d.orientation = mod(s.heading * 180 / pi, 360);
[d.azimuth, d.altitude, k] = patchPosition(s.pos, d.orientation, g);
d.dims = k * [P.bugLength; P.bugWidth];
d.show = s.alive;
end

function d = floorToDraw(env, ctx)
g = geometry(ctx);
half = abs(cm2deg(g.dimsCm / 2, g));
d.dims = 2.2 * half(:); % overscan: the flat screen isn't a rectangle in degrees
d.repeat = env.floorRepeat;
if isempty(env.floorImage)
  d.image = uint8(255 * reshape(env.floorColour, 1, 1, 3));
else
  d.image = env.floorImage;
end
end

function d = objectsToDraw(env, nPool, ctx)
%OBJECTSTODRAW Row 1: rectangle pool, row 2: ellipse pool.
g = geometry(ctx);
blank = struct('azimuth', 0, 'altitude', 0, 'dims', [1; 1], ...
  'orientation', 0, 'colour', [0; 0; 0], 'show', false);
d = repmat(blank, 2, nPool);
n = [0 0];
for k = 1:numel(env.objects)
  o = env.objects(k);
  row = 1 + ~strcmp(o.shape, 'rectangle');
  n(row) = n(row) + 1;
  if n(row) > nPool
    warning('MouseChase:tooManyObjects', ...
      'Only %d objects of each shape can be drawn; ignoring the rest.', nPool);
    continue
  end
  [az, alt, kScale] = patchPosition(o.centre, o.angle, g);
  d(row, n(row)) = struct('azimuth', az, 'altitude', alt, ...
    'dims', kScale * o.size(:), 'orientation', o.angle, ...
    'colour', o.colour(:), 'show', true);
end
end

function d = touchesToDraw(s, P, n, ctx)
g = geometry(ctx);
d = repmat(struct('azimuth', 0, 'altitude', 0, 'dims', [1; 1], 'show', false), 1, n);
if ~P.showTouches; return; end
for k = 1:min(n, size(s.contacts, 1))
  [az, alt, kScale] = patchPosition(s.contacts(k,2:3), 0, g);
  d(k) = struct('azimuth', az, 'altitude', alt, 'dims', kScale * [1; 1], 'show', true);
end
end

%% ===================== Environments =====================

function env = loadEnvironment(id, envDir)
%LOADENVIRONMENT Load MouseChaseEnvironments/<id>.mat (variable 'env').
%   An environment is a struct with fields (all optional except objects):
%     id           name, for the log
%     floorColour  [r g b] in 0-1, used when there is no floorImage
%     floorImage   HxW or HxWx3 uint8 image stretched over the screen
%                  (keep it small, e.g. <= 256 px: it is re-uploaded to the
%                  graphics card on every frame)
%     floorRepeat  true to tile floorImage instead of stretching it
%     objects      struct array of hiding places, each with
%                    shape  'rectangle' or 'ellipse'
%                    centre [x y] cm from the screen centre (y up)
%                    size   [w h] cm
%                    angle  deg, anticlockwise
%                    colour [r g b] in 0-1
%   'default' is built in: grey floor, one rock in the middle.
if strcmp(id, 'default')
  env = struct('id', 'default', 'floorColour', [0.5 0.5 0.5], ...
    'floorImage', [], 'floorRepeat', false, ...
    'objects', struct('shape', 'rectangle', 'centre', [0 0], ...
    'size', [7 4.5], 'angle', 0, 'colour', [0.7 0.7 0.7]));
  return
end
f = fullfile(envDir, [id '.mat']);
assert(exist(f, 'file') == 2, 'MouseChase:noEnvironment', ...
  'Environment file not found: %s', f);
s = load(f, 'env');
env = s.env;
defaults = struct('id', id, 'floorColour', [0.5 0.5 0.5], ...
  'floorImage', [], 'floorRepeat', false);
for f = fieldnames(defaults)'
  if ~isfield(env, f{1}); env.(f{1}) = defaults.(f{1}); end
end
if ~isfield(env, 'objects'); env.objects = struct('shape', {}, 'centre', {}, ...
    'size', {}, 'angle', {}, 'colour', {}); end
end
