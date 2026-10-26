function MouseChaseTouch(t, events, p, visStim, inputs, outputs, ~) %#ok<INUSL>
%MOUSECHASETOUCH Signals experiment definition: a mouse chases a virtual bug.
%   A bug wanders over a touchscreen floor, hides under objects and flees
%   from moving touches. Touches come from the multi-touch overlay (paws,
%   tail), read by tools/touchReader.ps1 in the background (Windows raw
%   input, no Psychtoolbox touch support needed).
%   When any contact lands on the visible bug, or within p.catchMargin cm
%   of its outline, it is caught: for p.caughtDuration seconds it freezes, grows to p.caughtGrowth
%   times its size and its stripes swap black and white p.caughtFlashRate
%   times a second (as full cycles). Half way through, a reward of
%   p.rewardSize ul is delivered with probability p.rewardProbability; at
%   the end the bug disappears, the trial ends, and the bug respawns from
%   the screen edge after p.respawnDelay seconds, at least
%   p.spawnClearance cm from the mouse's contacts.
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
%   Events (in the block file, and shown live in mc; kept low-rate, as
%   Rigbox sends every event update to mc):
%     catches      catch count, updating at each catch
%     rewarded     half way through each catch: true if it was rewarded
%     evading      true while the bug is fleeing
%     environment  name of the environment
%
%   High-rate data is logged by the task itself and saved at the end of the
%   session next to the block file, as <expRef>_MouseChase.mat (variable
%   'mouseChase'), with times on the same clock as the block's events
%   (except the touch events):
%     bug          [time x y heading hidden alive threatLevel caught] every
%                  update (s, cm, rad, 0-1; caught: frozen after a catch)
%     touchEvents  [type id x y w h time] raw touch events (type 2 begin,
%                  3 move, 4 end; cm, s in GetSecs, see clockSync)
%     catchLog     [time x y rewarded] at each catch (the reward itself
%                  follows p.caughtDuration / 2 later)
%     catchContact [id x y w h age snout] of the contact that made each
%                  catch (cm, s; a large or old contact is likely the tail;
%                  snout 1: caught from beyond catchMargin, see snoutReach)
%     clockSync    [blockTime GetSecs] every update, to convert the touch
%                  times to block time
%     plus the environment, screen geometry and the final parameters.

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
gamePars = {'rewardProbability', 'catchMargin', 'respawnDelay', 'bugLength', 'bugWidth', ...
  'visualRange', 'threatSpeed', 'fullThreatSpeed', 'landingThreatTime', 'lineOfSight', ...
  'obstacleRange', 'maxEscapeThrust', 'maxEscapeTime', 'escapeRest', 'easeTime', ...
  'wanderThrust', 'wanderNoise', 'friction', 'maxTurnRate', 'creviceDepth', ...
  'maxHideTime', 'showTouches', 'startDelay', 'trainingStage', ...
  'targetCatches', 'maxDuration', 'rewardSize', 'hidingObjects', ...
  'gaborCycles', 'gaborContrast', 'gaborColour', 'maxCatchContactSize', ...
  'caughtDuration', 'caughtGrowth', 'caughtFlashRate', 'spawnClearance', ...
  'spawnOnScreen', 'keepOut', 'keepOutMargin', 'snoutReach', 'snoutSpeed'};
for iPar = 1:numel(gamePars); p.(gamePars{iPar}); end

%% Environment
% Derived from expStart rather than directly from p.environment: during
% parameter inference anything derived from p is p itself, and subscripting
% it (floor.image etc.) would add bogus parameters.
% An empty p.environment takes the training stage's (see stageEnvironment)
envName = p.environment.map2(p.trainingStage, @stageEnvironment).skipRepeats();
env = events.expStart.map2(envName, @(~, id) loadEnvironment(id, envDir));

%% Game state, advanced p.updateRate times per second after experiment start
% Every update recomputes the scene and makes Rigbox redraw; updating less
% often than the screen refreshes leaves more time per update, so frames
% aren't late (late frames show as a flickering band at the top)
running = events.expStart.then(true);
tick = t.map2(p.updateRate, @(x, rate) floor(x * rate)).skipRepeats();
tRun = t.at(tick).keepWhen(running);
seed = struct('t', [], 'pos', [0 0], 'vel', [0 0], 'heading', 0, ...
  'wanderAngle', 0, 'hidden', true, 'alive', false, 'respawnAt', -inf, ...
  'catchCount', 0, 'rewardCount', 0, 'trialCount', 0, 'caught', false, 'caughtAt', -inf, ...
  'lastCatchRewarded', false, 'lastRewardSize', 0, ...
  'lastCatchContact', nan(1, 7), 'evading', false, ...
  'spawnTime', 0, 'threatLevel', 0, 'escapeTime', 0, 'restUntil', -inf, ...
  'hideTime', 0, 'tStart', 0, 'stop', false, 'safetySave', [], ...
  'contacts', zeros(0, 8), 'touchEvents', zeros(0, 7), ...
  'mouseXY', zeros(0, 2), 'mouseSeenAt', -inf);
state = tRun.scan(@(s, tNow, P, e, ref) updateGame(s, tNow, P, e, ref, ctx), seed, ...
  'pars', p, env, events.expStart).subscriptable();

%% Catches, reward, trials and stopping
% A catch starts the caught animation; the reward comes half way through
% it and the trial ends when it's over (so the next trial's parameters
% don't change the bug mid-animation). Each stage has its own count.
catchCount = state.catchCount.skipRepeats();
events.catches = catchCount.keepWhen(catchCount > 0);
trialCount = state.trialCount.skipRepeats();
events.endTrial = trialCount.keepWhen(trialCount > 0);
rewardCount = state.rewardCount.skipRepeats();
rewardEvent = rewardCount.keepWhen(rewardCount > 0);
% Whether a catch is rewarded is drawn in updateGame (p.rewardProbability)
rewarded = state.lastCatchRewarded.at(rewardEvent);
events.rewarded = rewarded;
% The reward size (ul) comes from the game state, where the training stage
% has been applied; only fires when rewarded is true
outputs.reward = state.lastRewardSize.at(rewarded);
events.totalReward = outputs.reward.scan(@plus, 0);

% Stop conditions (catch target, time limit) are evaluated in the game update
events.expStop = state.stop.skipRepeats().then(true);
% At the end (also when mc's End button is used: Rigbox then sets this same
% stop signal), stop the touch reader and save the task's own log. The
% expStart value is the experiment reference.
events.sessionSaved = events.expStop.map2(events.expStart, @(~, ref) finishSession(ctx, ref));

%% Events (low-rate: every event update is also sent to mc)
events.evading = state.evading.skipRepeats();
events.environment = env.map(@(e) e.id);
if ~isempty(getenv('MOUSECHASE_DEBUG_EVENTS')) % tools/simulation only
  events.bug = state.map(@(s) [s.pos s.heading s.hidden s.alive s.caught]');
end

%% Visual stimuli
% Signals draws layers in alphabetical order of their names, hence the
% prefixes: floor, then bug, then hiding objects (which cover the bug),
% then optional touch markers.
% The floor is built directly as a texture layer (not with vis.image, which
% treats an image coming from a signal as changing and re-uploads it on
% every redraw): its texture id is fixed per environment, so it's uploaded
% to the graphics card once
% (scan, seeded with an empty hidden layer: Rigbox reads the layer's value
% when the experiment starts, before the environment has loaded)
floorElem = t.Node.Net.subscriptableOrigin('floor');
floorElem.layers = env.scan(@(~, e) floorLayer(e, ctx), vis.emptyLayer());
visStim.a_floor = floorElem;

% skipRepeats: while the bug can't be seen its drawing stays the same, so
% Rigbox doesn't redraw (e.g. during the respawn delay, when trial changes
% and reward delivery keep the PC busy)
% The bug is a striped ellipse: a sharp-edged elliptical window (the bug's
% length and width) over a grating, both turning with its heading. Built
% like Rigbox's vis.grating, but with a rotating window and the grating's
% phase tied to the bug's centre, so the stripes move with the bug. (scan,
% seeded with empty hidden layers: Rigbox reads the layers when the
% experiment starts)
bugDraw = state.map2(p, @(s, P) bugToDraw(s, P, ctx)).skipRepeats();
bugElem = t.Node.Net.subscriptableOrigin('bug');
bugElem.layers = bugDraw.map(@bugLayers).scan(@(~, l) l, vis.emptyLayer(2));
visStim.b_bug = bugElem;

% Fixed pools of rectangle and ellipse patches; the environment decides
% how many are shown and where.
nPool = 6;
% (map2 with p: the training stage decides whether objects are included)
objDraw = env.map2(p, @(e, P) objectsToDraw(stageObjects(e, applyStage(P)), nPool, ctx));
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
  p.rewardSize = NaN;        % ul per rewarded catch (NaN: from the stage)
  p.hidingObjects = NaN;     % 1/0: use the environment's hiding objects (NaN: from the stage)
  p.rewardProbability = NaN; % chance that a catch is rewarded (NaN: from the stage)
  p.targetCatches = 250;     % stop after this many catches (Inf allowed)
  p.maxDuration = 3600;      % stop after this many seconds (Inf allowed)
  p.environment = '';        % name of a MouseChaseEnvironments/<name>.mat ('default': plain grey;
                             % empty: from the stage, grey at stages 1-2, grass after)
  p.trainingStage = 1;       % 1 (naive mouse) ... 6 (expert): sets the NaN values below
  % NaN = take the value from the training stage (see stageValues);
  % a number overrides the stage for that setting
  p.catchMargin = NaN;       % cm beyond the bug's outline that a contact still catches it (>= 0)
  p.maxCatchContactSize = Inf; % cm, larger contacts (width or height) can't catch: a dragged tail
                             % shows as a large contact, a paw strike as a small one (1.3 rejected
                             % ~40% of tail catches and no paw catches in EB056's videos)
  p.caughtDuration = 2;      % s a caught bug stays frozen and flashing (reward half way)
  p.caughtGrowth = 1.5;      % size of the caught bug, relative to its normal size
  p.caughtFlashRate = 3;     % Hz, black-white-black cycles of the caught bug's stripes
  p.respawnDelay = 2;        % s the bug stays away after the caught animation
  p.spawnClearance = 12;     % cm, the bug comes onto the screen at least this far from the mouse's contacts
  p.spawnOnScreen = NaN;     % 1: the bug appears on the screen, 0: it comes in from beyond the edge
  p.keepOut = NaN;           % 1: the bug never moves itself to within catchMargin + keepOutMargin of a contact
  p.keepOutMargin = 1;       % cm (see keepOut)
  p.snoutReach = NaN;        % cm of extra catch radius for a contact moving towards the bug...
  p.snoutSpeed = 5;          % cm/s ...at this speed or more (the snout reaches ahead of the paws)
  p.bugLength = NaN;         % cm
  p.bugWidth = NaN;          % cm
  p.gaborCycles = 3;         % grating cycles along the bug's length
  p.gaborContrast = 4;       % 1 = smooth sinusoid from black to white; higher saturates it into sharper stripes
  p.gaborColour = [1 1 1]';  % colour of the bright stripes (dark ones are black)
  p.visualRange = NaN;       % cm, distance at which contacts can scare the bug
  p.threatSpeed = NaN;       % cm/s towards the bug at which it starts reacting
  p.fullThreatSpeed = NaN;   % cm/s towards the bug for the full reaction
  p.landingThreatTime = 0.2; % s, a newly landed contact counts as a half threat
  p.lineOfSight = true;      % hiding objects block the bug's view of contacts
  p.obstacleRange = 2;       % cm, bug steers around still contacts this close
  p.maxEscapeThrust = NaN;   % cm/s^2 at full threat (top speed = thrust/friction)
  p.maxEscapeTime = NaN;     % s of continuous fleeing before the bug tires...
  p.escapeRest = 1.5;        % s ...and ignores threats for this long
  p.easeTime = NaN;          % s into a trial after which it no longer flees (Inf = never)
  p.wanderThrust = NaN;      % cm/s^2 (wander speed = thrust/friction)
  p.wanderNoise = 3;         % rad/s, random drift of the wander heading
  p.friction = 6;            % 1/s
  p.maxTurnRate = 8;         % rad/s
  p.creviceDepth = 4.5;      % cm the bug may go past the screen edge
  p.maxHideTime = 2;         % s past the screen edge before it comes back out
  p.showTouches = false;     % draw red markers on active contacts (costly: checks only)
  p.updateRate = 30;         % game/screen updates per second (60 = every frame)
  p.startDelay = 3;          % s before the bug first appears (while things start up)
catch
end
end

%% ===================== Game logic =====================

function s = updateGame(s, tNow, P, env, ref, ctx)
%UPDATEGAME Advance the game by one Signals update and log it.
if isempty(s.safetySave)
  % Safety net: however the session ends (the task's own stop, mc's End,
  % Rigbox's trial cap, an error), Rigbox discards the signal network
  % afterwards, and with it this state - which runs this cleanup object.
  % It saves the log unless the normal end-of-session save already did.
  ctx('ref') = ref;
  s.safetySave = onCleanup(@() safetySave(ctx));
end
P = applyStage(P);
s = stepGame(s, tNow, P, env, ctx);
logUpdate(ctx, s, P, env);
end

function P = applyStage(P)
%APPLYSTAGE Fill parameters left at NaN from the training stage's values.
v = stageValues(P.trainingStage);
for f = fieldnames(v)'
  if isnan(P.(f{1})); P.(f{1}) = v.(f{1}); end
end
end

function v = stageValues(stage)
%STAGEVALUES Difficulty ladder: 1 = naive mouse (huge bug that drifts
%   slowly and never comes to the mouse) ... 6 = expert. Rows are stages.
%   Stage 1 is "touch the bug, get a reward": a huge bug (twice stage 2's
%   size) that appears on the screen, drifts at half
%   stage 2's speed without fleeing, keeps out of reach of contacts by
%   itself (keepOut) and can be caught from further away by a contact
%   moving towards it (snoutReach), and a large reward. Stage 2 is a big,
%   slow bug that doesn't flee (visualRange 0). (Stage 1 was added on
%   2026-10-22; until then stages 2-6 were numbered 1-5.)
%   wanderThrust = wander speed (cm/s) x friction (6); top escape speed =
%   maxEscapeThrust / friction.
%   rewardSize in ul; hidingObjects 0 = the environment's objects (rocks
%   etc.) are left out, 1 = included.
%   spawnOnScreen 1 = the bug appears on the screen, 0 = it comes in from
%   beyond the screen edge.
%   catchMargin cm = how far beyond the bug's outline a contact still
%   catches it (a contact on the bug always does). From stage 2 the
%   margins give about the same catch area as the circles around the
%   bug's centre used before 2026-10-23 (catchRadius 3, 2.5, 2, 1.7, 1.5).
%   keepOut 1 = the bug never moves itself to within catchMargin +
%   p.keepOutMargin of a contact (so a still paw can't catch it), 0 = off.
%   snoutReach cm = extra catch margin for a contact moving towards the
%   bug at p.snoutSpeed or more (the snout reaches ahead of the paws).
%            bugLength bugWidth catchMargin visualRange threatSpeed fullThreatSpeed maxEscapeThrust maxEscapeTime easeTime wanderThrust rewardProbability rewardSize hidingObjects spawnOnScreen keepOut snoutReach
ladder = [  9.0       3.6      2.0          0          15          45                0             0.5           20        6           1.0               20.0       0             1             1       3
             6.0       2.4      1.0          0          15          45               12             0.5           20       12           1.0               15.0       0             0             0       0
             5.25      2.1      0.8          6          15          45               60             0.5           20       18           1.0               12.5       0             0             0       0
             4.5       1.8      0.55        10          10          35              108             0.8           40       24           1.0               10.0       1             0             0       0
             3.9       1.5      0.45        14           7          28              162             1.0           60       24           0.9                7.5       1             0             0       0
             3.6       1.35     0.35        18           5          22              210             1.3           90       30           0.8                5.0       1             0             0       0];
names = {'bugLength', 'bugWidth', 'catchMargin', 'visualRange', 'threatSpeed', ...
  'fullThreatSpeed', 'maxEscapeThrust', 'maxEscapeTime', 'easeTime', ...
  'wanderThrust', 'rewardProbability', 'rewardSize', 'hidingObjects', ...
  'spawnOnScreen', 'keepOut', 'snoutReach'};
row = ladder(min(max(round(stage), 1), size(ladder, 1)), :);
v = cell2struct(num2cell(row(:)), names(:), 1);
end

function static = isStatic(P)
%ISSTATIC True for a bug that can't move (no wander or escape thrust): it
%   is placed on the screen and stays there, facing one way, until caught.
%   (No stage uses this now; it's for setting both thrusts to 0 in mc.)
static = P.wanderThrust == 0 && P.maxEscapeThrust == 0;
end

function id = stageEnvironment(id, stage)
%STAGEENVIRONMENT The environment's name: ID if given, otherwise the
%   training stage's: plain grey at stages 1-2, grass from stage 3.
if ~isempty(id); return; end
if round(stage) <= 2
  id = 'default';
else
  id = 'grass';
end
end

function env = stageObjects(env, P)
%STAGEOBJECTS Leave out the environment's hiding objects at training stages
%   without them (P.hidingObjects == 0; P already has the stage applied).
if ~P.hidingObjects; env.objects = env.objects([]); end
end

function s = stepGame(s, tNow, P, env, ctx)
%STEPGAME Advance the bug by one Signals update.
g = geometry(ctx);
env = stageObjects(env, P); % no rocks etc. at the first training stages
if isempty(s.t) % first update: the bug enters after p.startDelay
  s.t = tNow;
  s.tStart = tNow;
  s.respawnAt = tNow + P.startDelay;
end
dt = min(max(tNow - s.t, 0), 0.1); % cap to avoid jumps after a stall
s.t = tNow;
[s.contacts, s.touchEvents] = pollTouches(ctx);
if ~isempty(s.contacts) % where the mouse was last seen, for spawnBug
  s.mouseXY = s.contacts(:,2:3);
  s.mouseSeenAt = tNow;
end
s.stop = s.trialCount >= P.targetCatches || tNow - s.tStart >= P.maxDuration;

if s.caught
  s = stepCaught(s, tNow, P);
  return
end
if ~s.alive
  s.evading = false;
  s.threatLevel = 0;
  if tNow >= s.respawnAt
    s = spawnBug(s, g, P, env.objects);
  end
  return
end

half = g.dimsCm / 2;
onScreen = all(abs(s.pos) <= half);
s.hidden = ~onScreen || isUnderObject(s.pos, env.objects);
if isStatic(P) % stays where spawnBug placed it, waiting to be caught
  s = checkCatch(s, tNow, P);
  return
end

% Threat level (0-1) of each contact: how fast it moves towards the bug
% (graded between threatSpeed and fullThreatSpeed; sideways movement counts
% half) times how close it is; zero if a hiding object blocks the view
C = s.contacts;
nC = size(C, 1);
level = zeros(nC, 1);
isObstacle = false(nC, 1);
if nC > 0
  rel = [s.pos(1) - C(:,2), s.pos(2) - C(:,3)];
  d = hypot(rel(:,1), rel(:,2));
  toBug = rel ./ max(d, eps);
  closing = sum(C(:,6:7) .* toBug, 2);
  effSpeed = max(closing, 0.5 * hypot(C(:,6), C(:,7)));
  wSpeed = min(max((effSpeed - P.threatSpeed) / max(P.fullThreatSpeed - P.threatSpeed, eps), 0), 1);
  landed = C(:,8) < P.landingThreatTime;
  wSpeed(landed) = max(wSpeed(landed), 0.5);
  level = wSpeed .* max(P.visualRange - d, 0) / max(P.visualRange, eps); % 0 if visualRange is 0
  if P.lineOfSight
    for i = find(level > 0)'
      if ~canSee(s.pos, C(i,2:3), env.objects, g.blockedCm, P.bugLength / 2)
        level(i) = 0;
      end
    end
  end
  % Contacts to steer around: still paws close by, and with keepOut, any
  % contact the bug is about to drift into reach of (see below)
  avoidRange = P.obstacleRange;
  if P.keepOut % (d is from the bug's centre)
    avoidRange = max(avoidRange, P.bugLength / 2 + P.catchMargin + P.keepOutMargin + 1);
  end
  isObstacle = level == 0 & d < avoidRange & d > 0;
end
% The reaction fades over the trial (easeTime), and a tired bug ignores
% threats for a while (escapeRest); hidden, it doesn't react at all
ease = max(0, 1 - (tNow - s.spawnTime) / P.easeTime);
if s.hidden || tNow < s.restUntil; ease = 0; end
s.threatLevel = ease * max([level; 0]);

s.evading = s.threatLevel > 0;
if s.evading
  s.escapeTime = s.escapeTime + dt;
  if s.escapeTime > P.maxEscapeTime
    s.restUntil = tNow + P.escapeRest;
    s.escapeTime = 0;
  end
  % Flee along the summed push of all threats, stronger ones pushing harder
  push = sum(level .* toBug, 1);
  desiredHeading = atan2(push(2), push(1));
  thrust = P.wanderThrust + (P.maxEscapeThrust - P.wanderThrust) * s.threatLevel;
  s.wanderAngle = desiredHeading;
else
  s.escapeTime = 0;
  s.wanderAngle = s.wanderAngle + randn() * P.wanderNoise * dt;
  wanderDir = [cos(s.wanderAngle), sin(s.wanderAngle)];
  if any(isObstacle) % steer around still paws
    away = sum(rel(isObstacle,:) ./ d(isObstacle), 1);
    wanderDir = wanderDir + 2 * away;
  end
  desiredHeading = atan2(wanderDir(2), wanderDir(1));
  thrust = P.wanderThrust;
end

% Don't stay in the wall (past the screen edge) longer than maxHideTime
if onScreen
  s.hideTime = 0;
else
  s.hideTime = s.hideTime + dt;
end
if s.hideTime > P.maxHideTime && ~s.evading
  desiredHeading = atan2(-s.pos(2), -s.pos(1));
  s.wanderAngle = desiredHeading;
  thrust = max(thrust, 2 * P.wanderThrust);
end

% Non-holonomic motion: turn at a limited rate, thrust along the heading,
% no sideways skidding
deltaAngle = mod(desiredHeading - s.heading + pi, 2 * pi) - pi;
prevHeading = s.heading;
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
% keepOut: the bug never moves or turns itself closer to a contact within
% reach (catchMargin + keepOutMargin from its outline), so it can't be
% caught by a paw that holds still; the mouse has to move to it. (It
% doesn't flee either: a contact moving towards it can still catch it.)
if P.keepOut && nC > 0
  dNew = outlineDistance(C(:,2:3), s.pos, s.heading, P.bugLength, P.bugWidth);
  dOld = outlineDistance(C(:,2:3), prevPos, prevHeading, P.bugLength, P.bugWidth);
  if any(dNew < P.catchMargin + P.keepOutMargin & dNew < dOld)
    s.pos = prevPos;
    s.heading = prevHeading;
    s.vel = [0 0];
  end
end
if hitWall
  s.wanderAngle = atan2(-s.pos(2), -s.pos(1)); % head back to the centre
  s.vel = [0 0];
end

s = checkCatch(s, tNow, P);
end

function s = checkCatch(s, tNow, P)
%CHECKCATCH Any contact on the visible bug or within P.catchMargin of its
%   outline (and not too large: see maxCatchContactSize) starts the caught
%   animation. A contact moving towards the bug at P.snoutSpeed or more
%   catches it from P.snoutReach further away: the mouse's snout, ahead of
%   its paws, gets there first.
C = s.contacts;
nC = size(C, 1);
onBug = [];
if ~s.hidden && nC > 0
  d = outlineDistance(C(:,2:3), s.pos, s.heading, P.bugLength, P.bugWidth);
  rel = [s.pos(1) - C(:,2), s.pos(2) - C(:,3)];
  toBug = rel ./ max(hypot(rel(:,1), rel(:,2)), eps);
  closing = sum(C(:,6:7) .* toBug, 2); % speed towards the bug
  snout = P.snoutReach > 0 & closing >= P.snoutSpeed;
  reach = P.catchMargin + snout * P.snoutReach;
  ok = max(C(:,4:5), [], 2) <= P.maxCatchContactSize;
  onBug = find(d <= P.catchMargin & ok, 1); % a contact on or by the bug first...
  if isempty(onBug)
    onBug = find(d <= reach & ok, 1); % ...otherwise a snout catch
  end
end
if ~isempty(onBug)
  % [id x y w h age snout], logged with the catch (snout: caught only
  % thanks to snoutReach)
  s.lastCatchContact = [C(onBug,[1:5 8]), d(onBug) > P.catchMargin];
  s.catchCount = s.catchCount + 1;
  s.lastCatchRewarded = rand() < P.rewardProbability;
  s.lastRewardSize = P.rewardSize;
  s.caught = true;
  s.caughtAt = tNow;
  s.vel = [0 0];
  s.evading = false;
  s.threatLevel = 0;
end
end

function d = outlineDistance(xy, pos, heading, len, wid)
%OUTLINEDISTANCE Distance (cm) from each point XY (N x 2) to the outline of
%   a bug (an ellipse LEN x WID, centred at POS, long axis along HEADING in
%   rad); 0 for points on the bug. POS and HEADING may also have one row
%   per point. The outline is a polygon of 128 points (error < 0.02 cm).
%   (mouseChaseMetrics has a copy: Rigbox takes this folder off the path
%   during the session, so the task can't share a file with it.)
a = len / 2;
b = wid / 2;
rel = xy - pos;
u = abs(rel(:,1) .* cos(heading) + rel(:,2) .* sin(heading)); % along the body
v = abs(-rel(:,1) .* sin(heading) + rel(:,2) .* cos(heading)); % across it
d = zeros(size(xy, 1), 1);
out = (u / a) .^ 2 + (v / b) .^ 2 > 1;
if ~any(out); return; end
% By symmetry, the distance to one quarter of the outline will do
t = linspace(0, pi / 2, 33);
qx = a * cos(t); qy = b * sin(t);
ax = qx(1:end-1); ay = qy(1:end-1); % segment starts (1 x 32)
dx = diff(qx); dy = diff(qy);
wx = u(out) - ax; wy = v(out) - ay;
f = min(max((wx .* dx + wy .* dy) ./ (dx .^ 2 + dy .^ 2), 0), 1);
d(out) = sqrt(min((wx - f .* dx) .^ 2 + (wy - f .* dy) .^ 2, [], 2));
end

function s = stepCaught(s, tNow, P)
%STEPCAUGHT The caught bug stays frozen (bugToDraw makes it grow and
%   flash). The reward is due half way through, and at the end the bug
%   disappears and the trial ends.
elapsed = tNow - s.caughtAt;
if s.rewardCount < s.catchCount && elapsed >= P.caughtDuration / 2
  s.rewardCount = s.catchCount;
end
if elapsed >= P.caughtDuration
  s.rewardCount = s.catchCount; % (in case caughtDuration is 0)
  s.trialCount = s.catchCount;
  s.caught = false;
  s.alive = false;
  s.respawnAt = tNow + P.respawnDelay;
end
end

%% ===================== Session log =====================
% High-rate data stays out of Rigbox's events (each event update is sent to
% mc, which costs time during the session) and is saved by finishSession.

function logUpdate(ctx, s, P, env)
appendLog(ctx, 'logBug', [s.t s.pos s.heading s.hidden s.alive s.threatLevel s.caught]);
% Touch times are in GetSecs, the rest in block time: log both clocks
appendLog(ctx, 'logClock', [s.t GetSecs]);
if ~isempty(s.touchEvents); appendLog(ctx, 'logTouch', s.touchEvents); end
if ~isKey(ctx, 'catchesLogged'); ctx('catchesLogged') = 0; end
if s.catchCount > ctx('catchesLogged')
  appendLog(ctx, 'logCatch', [s.t s.pos s.lastCatchRewarded]);
  appendLog(ctx, 'logCatchContact', s.lastCatchContact);
  ctx('catchesLogged') = s.catchCount;
end
ctx('env') = env;
ctx('params') = P; %#ok<NASGU> ctx is a handle (containers.Map)
end

function appendLog(ctx, name, rows)
%APPENDLOG Add rows to a log kept in ctx, in chunks (cheap appending).
chunk = 512;
if isKey(ctx, name)
  L = ctx(name);
else
  L = struct('done', {{}}, 'cur', zeros(chunk, size(rows, 2)), 'n', 0);
end
if L.n + size(rows, 1) > size(L.cur, 1)
  L.done{end+1} = L.cur(1:L.n,:);
  L.cur = zeros(max(chunk, size(rows, 1)), size(rows, 2));
  L.n = 0;
end
L.cur(L.n+1:L.n+size(rows, 1),:) = rows;
L.n = L.n + size(rows, 1);
ctx(name) = L; %#ok<NASGU>
end

function data = getLog(ctx, name, nCols)
if ~isKey(ctx, name); data = zeros(0, nCols); return; end
L = ctx(name);
data = vertcat(L.done{:}, L.cur(1:L.n,:));
end

function safetySave(ctx)
%SAFETYSAVE Save the log when the session is torn down, if not done yet.
if isKey(ctx, 'saved') || ~isKey(ctx, 'ref'); return; end
fprintf('MouseChase: session ended without the task''s stop signal; saving the log now\n');
finishSession(ctx, ctx('ref'));
end

function ok = finishSession(ctx, ref)
%FINISHSESSION Stop the touch reader and save the task's log next to the
%   block file, as <expRef>_MouseChase.mat. Runs once per session.
ok = true;
if isKey(ctx, 'saved'); return; end
ctx('saved') = true;
releaseTouch(ctx);
mouseChase = struct('expRef', ref, 'savedAt', datestr(now, 31), ...
  'bug', getLog(ctx, 'logBug', 8), ...
  'bugColumns', {{'time', 'x', 'y', 'heading', 'hidden', 'alive', 'threatLevel', 'caught'}}, ...
  'touchEvents', getLog(ctx, 'logTouch', 7), ...
  'touchEventColumns', {{'type', 'id', 'x', 'y', 'w', 'h', 'time'}}, ...
  'catchLog', getLog(ctx, 'logCatch', 4), ...
  'catchColumns', {{'time', 'x', 'y', 'rewarded'}}, ...
  'catchContact', getLog(ctx, 'logCatchContact', 7), ...
  'catchContactColumns', {{'id', 'x', 'y', 'w', 'h', 'age', 'snout'}}, ...
  'clockSync', getLog(ctx, 'logClock', 2), ...
  'clockSyncColumns', {{'blockTime', 'GetSecs'}}, ...
  'environment', [], 'params', [], 'geometry', geometry(ctx));
if isKey(ctx, 'env')
  % without the floor image (MBs for photos); env.floor keeps how it was made
  mouseChase.environment = ctx('env');
  mouseChase.environment.floorImage = [];
end
if isKey(ctx, 'params'); mouseChase.params = ctx('params'); end
dirs = getenv('MOUSECHASE_LOG_DIR'); % set by tools/simulation (pathsep-separated)
if isempty(dirs)
  try
    dirs = dat.expPath(ref, 'main'); % local and server experiment folders
  catch ex
    warning('MouseChase:logNotSaved', 'No experiment folder for "%s": %s', ref, ex.message);
    return
  end
else
  dirs = strsplit(dirs, pathsep);
end
% NB dat.expPath returns a column cell array; a for loop runs over columns,
% so make it a row to visit every folder
for d = reshape(cellstr(dirs), 1, [])
  f = fullfile(d{1}, [ref '_MouseChase.mat']);
  try
    if ~exist(d{1}, 'dir'); mkdir(d{1}); end
    save(f, 'mouseChase');
    fprintf('MouseChase log saved to %s\n', f);
  catch ex
    warning('MouseChase:logNotSaved', 'Could not save %s: %s', f, ex.message);
  end
end
end

function s = spawnBug(s, g, P, objects)
%SPAWNBUG Place the bug in the crevice beyond a random screen edge, facing
%   in (with P.spawnOnScreen, or a static bug: anywhere on the screen,
%   facing any way), where it comes onto the screen at least
%   P.spawnClearance cm from the mouse's contacts (seen in the last 2 s),
%   so it isn't caught as soon as it appears. If no such place turns up,
%   the farthest one tried.
mouseXY = s.mouseXY;
if s.t - s.mouseSeenAt > 2; mouseXY = zeros(0, 2); end
half = g.dimsCm / 2;
onScreen = P.spawnOnScreen || isStatic(P);
best = -inf;
for k = 1:50
  if onScreen
    pos = randomScreenPoint(g, P, objects);
  else
    pos = randomSpawnPoint(g, P);
  end
  entry = min(max(pos, -half), half); % where it comes onto the screen
  d = min([inf; hypot(mouseXY(:,1) - entry(1), mouseXY(:,2) - entry(2))]);
  if d > best
    best = d;
    s.pos = pos;
  end
  if d >= P.spawnClearance; break; end
end
if onScreen
  s.heading = 2 * pi * rand();
else
  s.heading = atan2(-s.pos(2), -s.pos(1)) + (rand() - 0.5);
end
s.wanderAngle = s.heading;
s.vel = [0 0];
s.alive = true;
s.hidden = true;
s.spawnTime = s.t; % the trial's ease-in (easeTime) counts from here
s.threatLevel = 0;
s.escapeTime = 0;
s.restUntil = -inf;
s.hideTime = 0;
end

function pos = randomScreenPoint(g, P, objects)
%RANDOMSCREENPOINT A random place on the screen for the bug: wholly
%   on the screen, clear of blocked areas and not under a hiding object.
margin = P.bugLength / 2 + 1; % cm from the screen edge
range = g.dimsCm / 2 - margin;
for k = 1:100
  pos = (2 * rand(1, 2) - 1) .* range;
  ok = ~isUnderObject(pos, objects);
  for b = 1:size(g.blockedCm, 1)
    ok = ok && ~isInsideRect(pos, g.blockedCm(b,:), P.bugLength);
  end
  if ok; return; end
end
end

function pos = randomSpawnPoint(g, P)
%RANDOMSPAWNPOINT A random place in the crevice beyond a screen edge.
half = g.dimsCm / 2;
depth = P.creviceDepth / 2;
along = (rand() - 0.5) * 1.6; % keep away from the corners
switch randi(4)
  case 1, pos = [-half(1) - depth, along * half(2)];
  case 2, pos = [half(1) + depth, along * half(2)];
  case 3, pos = [along * half(1), -half(2) - depth];
  case 4, pos = [along * half(1), half(2) + depth];
end
for b = 1:size(g.blockedCm, 1) % never start next to a blocked area
  if isInsideRect(pos, g.blockedCm(b,:), P.creviceDepth + P.bugLength)
    pos = -pos;
  end
end
end

function visible = canSee(from, to, objects, blockedCm, skip)
%CANSEE True if no hiding object or blocked area lies between the bug (at
%   FROM) and a contact (at TO). Samples the line every 0.5 cm, ignoring the
%   first SKIP cm (the bug itself).
v = to - from;
n = max(2, ceil(norm(v) / 0.5));
visible = true;
for k = 1:n-1
  q = from + v * k / n;
  if norm(q - from) < skip; continue; end
  if isUnderObject(q, objects); visible = false; return; end
  for b = 1:size(blockedCm, 1)
    if isInsideRect(q, blockedCm(b,:), 0); visible = false; return; end
  end
end
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
P = applyStage(P);
% Out of sight (respawning, or wholly beyond the screen edge): a constant
% hidden layer, so nothing needs redrawing
visible = s.alive && all(abs(s.pos) <= g.dimsCm / 2 + P.bugLength / 2);
d = struct('orientation', 0, 'azimuth', 0, 'altitude', 0, 'dims', [1; 1], ...
  'cycles', P.gaborCycles, 'contrast', P.gaborContrast, ...
  'colour', P.gaborColour(:), 'reversed', false, 'show', false);
if ~visible; return; end
d.orientation = mod(s.heading * 180 / pi, 360);
[d.azimuth, d.altitude, k] = patchPosition(s.pos, d.orientation, g);
d.dims = k * [P.bugLength; P.bugWidth];
if s.caught
  % Grows to caughtGrowth over the first quarter of the animation, while
  % the stripes swap colour twice per caughtFlashRate cycle
  elapsed = s.t - s.caughtAt;
  grow = min(1, elapsed / max(P.caughtDuration / 4, eps));
  d.dims = d.dims * (1 + (P.caughtGrowth - 1) * grow);
  d.reversed = mod(floor(elapsed * 2 * P.caughtFlashRate), 2) == 1;
end
d.show = true;
end

function layers = bugLayers(d)
%BUGLAYERS The bug as a striped ellipse: an elliptical window layer (drawn
%   first, into the alpha channel only, as a stencil) and a grating layer
%   blended through it, as in vis.grating. Both are rotated to the heading
%   (d.orientation) and offset by the pre-rotated position from
%   patchPosition. For the grating that offset also fixes its phase at the
%   bug's centre (a bright stripe through the middle), so the stripes move
%   and turn with the bug. The grating varies along the body axis, i.e.
%   stripes run across the bug like body segments.
%   The window is a sharp-edged ellipse the bug's length and width, so the
%   stripes keep full contrast up to the bug's outline.
win = vis.emptyLayer();
win.textureId = 'bugEllipseStencil';
win.texOffset = [d.azimuth; d.altitude];
win.texAngle = d.orientation;
win.size = d.dims;
win.isPeriodic = false; % transparent outside the ellipse
win.interpolation = 'linear'; % smooths the outline's pixels
[win.rgba, win.rgbaSize] = ellipseStencil();
win.blending = 'none';
win.colourMask = [false false false true]';
win.show = d.show;

wavelength = d.dims(1) / d.cycles; % deg
[grating, gratingImg] = vis.sinusoidLayer(0, 1 / wavelength, 0, d.orientation);
grating.textureId = 'sinusoidGrating';
grating.texOffset = [d.azimuth; 0]; % phase tied to the bug's centre
[grating.rgba, grating.rgbaSize] = vis.rgba(gratingImg, 1);
grating.blending = 'destination';
% Contrast above 1 pushes these below 0 / above 1; the graphics card clips
% the result, giving saturated black and white stripes
lo = 0.5 - 0.5 * d.contrast;
hi = 0.5 + 0.5 * d.contrast;
if d.reversed % caught bug flashing: black and white stripes swapped
  [lo, hi] = deal(hi, lo);
end
grating.minColour = [lo .* d.colour; 0];
grating.maxColour = [hi .* d.colour; 1];
grating.show = d.show;

layers = [win, grating];
end

function [rgba, sz] = ellipseStencil()
%ELLIPSESTENCIL Texture of a filled ellipse (alpha 1 inside, 0 outside),
%   with a one-texel soft outline against jagged edges. Made once: it's the
%   same for every update.
persistent cache
if isempty(cache)
  n = 256;
  c = linspace(-1 + 1/n, 1 - 1/n, n); % texel centres
  [xx, yy] = meshgrid(c, c);
  alpha = min(max((1 - hypot(xx, yy)) * n / 2 + 0.5, 0), 1);
  [cache.rgba, cache.sz] = vis.rgba(0, alpha);
end
rgba = cache.rgba;
sz = cache.sz;
end

function layer = floorLayer(env, ctx)
%FLOORLAYER Texture layer for the floor colour or image. The image covers
%   env.floorExtentCm (default 1.1 x the screen: the flat screen isn't a
%   rectangle in degrees, so it's overscanned), centred on the screen.
g = geometry(ctx);
extent = 1.1 * g.dimsCm;
if isfield(env, 'floorExtentCm') && ~isempty(env.floorExtentCm); extent = env.floorExtentCm; end
half = abs(cm2deg(extent / 2, g));
if isempty(env.floorImage)
  img = reshape(env.floorColour, 1, 1, 3);
else
  img = double(env.floorImage) / iff(isa(env.floorImage, 'uint8'), 255, 1);
end
layer = vis.emptyLayer();
layer.textureId = ['floor_' env.id]; % no '~': uploaded once
layer.size = 2 * half(:);
layer.isPeriodic = false;
if isfield(env, 'floorInterpolation') && ~isempty(env.floorInterpolation)
  layer.interpolation = env.floorInterpolation;
end
[layer.rgba, layer.rgbaSize] = vis.rgba(img, 1);
layer.show = true;
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
%   Environments are made and saved with the mouseChaseEnv package (see
%   mouseChaseEnv.create). An environment is a struct with fields:
%     id                  name, logged with the session
%     description         free text
%     floorColour         [r g b] in 0-1, used when there is no floorImage
%     floorImage          HxW or HxWx3 image (uint8, or double in 0-1),
%                         row 1 at the top of the screen
%     floorExtentCm       [w h] cm the floor image covers, centred on the
%                         screen (default 1.1 x the screen size)
%     floorInterpolation  'linear' (smooth) or 'nearest' (sharp edges)
%     objects             struct array of hiding places, each with
%                           shape  'rectangle' or 'ellipse'
%                           centre [x y] cm from the screen centre (y up)
%                           size   [w h] cm
%                           angle  deg, anticlockwise
%                           colour [r g b] in 0-1
%   'default' is built in: grey floor, one rock in the middle.
noObjects = struct('shape', {}, 'centre', {}, 'size', {}, 'angle', {}, 'colour', {});
defaults = struct('id', id, 'description', '', 'floorColour', [0.5 0.5 0.5], ...
  'floorImage', [], 'floorExtentCm', [], 'floorInterpolation', 'linear', ...
  'objects', noObjects);
if strcmp(id, 'default')
  env = defaults;
  env.description = 'Grey floor, one rock in the middle';
  env.objects = struct('shape', 'rectangle', 'centre', [0 0], ...
    'size', [7 4.5], 'angle', 0, 'colour', [0.7 0.7 0.7]);
  return
end
f = fullfile(envDir, [id '.mat']);
assert(exist(f, 'file') == 2, 'MouseChase:noEnvironment', ...
  'Environment file not found: %s', f);
s = load(f, 'env');
env = s.env;
for fn = fieldnames(defaults)'
  if ~isfield(env, fn{1}); env.(fn{1}) = defaults.(fn{1}); end
end
end
