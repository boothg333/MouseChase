function simMouseChase(stage)
% Headless simulation of MouseChaseTouch with scripted touches.
% SIMMOUSECHASE(STAGE) runs at that training stage (default 4, where the
% bug flees; at stage 2 it doesn't, at stage 1 it doesn't move at all).
if nargin < 1; stage = 4; end
here = fileparts(mfilename('fullpath'));
[~, fakeCleanup] = makeFakePtb(); %#ok<ASGLU> removed from the path on return
defFile = fullfile(fileparts(fileparts(here)), 'MouseChaseTouch.m');
global SIM
SIM = struct('time', 0, 'released', 0);
SIM.queue = struct('Type', {}, 'Keycode', {}, 'X', {}, 'Y', {}, 'Valuators', {}, 'Time', {});
rng(1);
% Debug switches read by MouseChaseTouch: log the bug position as an event
% (so this script can follow it) and save the session log to a temp folder
setenv('MOUSECHASE_DEBUG_EVENTS', '1');
logDir = tempname; mkdir(logDir);
logDir2 = tempname; mkdir(logDir2); % stands in for the server copy
setenv('MOUSECHASE_LOG_DIR', [logDir pathsep logDir2]);

pars = exp.inferParameters(defFile);
pars = rmfield(pars, {'numRepeats', 'defFunction', 'type'});
pars.targetCatches = 6; % keep it quick (5 respawns checked)
pars.trainingStage = stage;
pars.rewardProbability = 0.5; % overrides the stage's value
if stage > 1 % (at stage 1 the bug is static)
  pars.wanderThrust = 24; % explicit, for the trial-parameter check below
end
pars.updateRate = 60; % one game update per simulated frame (the checks assume it)

net = sig.Net;
clk = @() SIM.time;
t = net.origin('t');
events = sig.Registry(clk);
events.expStart = net.origin('expStart');
events.newTrial = net.origin('newTrial');
p = net.subscriptableOrigin('pars');
visual = StructRef;
inputs = sig.Registry(clk);
outputs = sig.Registry(clk);
expDef = fileFunction(defFile);
expDef(t, events, p, visual, inputs, outputs, []);

rewards = []; catches = []; rewardedFlags = []; stopped = false;
hR = outputs.reward.onValue(@(v) addReward(v)); %#ok<NASGU>
hW = events.rewarded.onValue(@(v) addRewarded(v)); %#ok<NASGU>
hC = events.catches.onValue(@(v) addCatch(v)); %#ok<NASGU>
hS = events.expStop.onValue(@(v) setStop()); %#ok<NASGU>

touchPort = 50555; % the task listens here instead of starting tools/touchReader.ps1
setenv('MOUSECHASE_TOUCH_PORT', num2str(touchPort));
sender = java.net.DatagramSocket();
% Like exp.SignalsExp/loadVisual at experiment start: every visual
% element's layers must already be readable (a struct with 'show')
for vn = fieldnames(visual)'
  val = visual.(vn{1}).Node.CurrValue.layers.Node.CurrValue;
  try
    any([val.show]); %#ok<VUNUS>
  catch ex
    fprintf('Rigbox could not load visual %s at start: %s\n', vn{1}, ex.message);
  end
end
post(p, pars);
post(t, 0);
post(events.expStart, 'sim');

W = [1280 1024]; dims = [37.6 30.1]; cpp = dims ./ W;
toPx = @(xy) [xy(1) / cpp(1) + W(1) / 2, W(2) / 2 - xy(2) / cpp(2)];
dt = 1/60;

%% 1. Wander for 20 s without touches
B = zeros(0, 6);
for k = 1:round(20 / dt)
  step();
  B(end+1,:) = events.bug.Node.CurrValue'; % column -> row %#ok<AGROW>
end
fprintf('Wander: x in [%.1f %.1f], y in [%.1f %.1f] cm, visible %.0f%% of frames, alive all: %d\n', ...
  min(B(:,1)), max(B(:,1)), min(B(:,2)), max(B(:,2)), 100 * mean(~B(:,4)), all(B(:,5)));
sp = hypot(diff(B(:,1)), diff(B(:,2))) / dt;
fprintf('        median speed %.1f cm/s, max %.1f cm/s\n', median(sp), max(sp));
checkVisual();

%% 2. A moving touch approaching the visible bug makes it flee
waitVisible();
b = events.bug.Node.CurrValue'; % column -> row
start = b(1:2) + [6 0];
touch(2, 7, start);
evading = false; spd = [];
for k = 1:30
  prev = events.bug.Node.CurrValue'; % column -> row
  touch(3, 7, start - [k * 0.3, 0]); % 18 cm/s towards the bug
  step();
  now = events.bug.Node.CurrValue'; % column -> row
  spd(end+1) = hypot(now(1) - prev(1), now(2) - prev(2)) / dt; %#ok<AGROW>
  evading = evading || isequal(events.evading.Node.CurrValue, true);
end
touch(4, 7, start - [9 0]);
step();
fprintf('Threat: evading seen %d, bug speed rose to %.1f cm/s\n', evading, max(spd));

%% 2b. Stage 1: catches within catchMargin of the bug's outline; the bug
% doesn't drift into a still paw (keepOut), and a paw moving towards it
% catches it from further away (snoutReach). Distances are from the outline.
if stage == 1
  M = 2; reach = M + 3; % stage 1's catchMargin and catchMargin + snoutReach
  bugLW = [12 4.8]; % stage 1's bug
  % A paw landing beside the bug, 1.5 cm out from its side: caught
  waitVisible();
  b = events.bug.Node.CurrValue'; % column -> row
  sideXY = b(1:2) + (bugLW(2) / 2 + 1.5) * [-sin(b(3)) cos(b(3))];
  nCatch0 = numel(catches);
  touch(2, 51, sideXY); step(); touch(4, 51, sideXY); step();
  fprintf('Outline: paw landing %.1f cm from the bug''s side (margin %g): caught %d\n', ...
    outlineDist(sideXY, b, bugLW), M, numel(catches) > nCatch0);
  for k = 1:round((pars.caughtDuration + 0.5) / dt); step(); end
  % A still paw in its path, just out of reach
  waitVisible();
  b = events.bug.Node.CurrValue'; % column -> row
  hd = [cos(b(3)) sin(b(3))];
  pawXY = b(1:2) + (bugLW(1) / 2 + M + pars.keepOutMargin + 0.5) * hd;
  nCatch0 = numel(catches); minD = inf;
  touch(2, 50, pawXY);
  for k = 1:round(10 / dt)
    touch(3, 50, pawXY);
    step();
    v = events.bug.Node.CurrValue'; % column -> row
    minD = min(minD, outlineDist(pawXY, v, bugLW));
  end
  fprintf('KeepOut: still paw placed %.1f cm ahead for 10 s: closest %.2f cm (keeps >= %g), caught %d\n', ...
    M + pars.keepOutMargin + 0.5, minD, M + pars.keepOutMargin, numel(catches) > nCatch0);
  % Sideways past the bug at 10 cm/s, within snout reach: no catch
  b = events.bug.Node.CurrValue'; % column -> row
  toPaw = (pawXY - b(1:2)) / norm(pawXY - b(1:2));
  side = [-toPaw(2) toPaw(1)];
  for k = 1:12
    pawXY = pawXY + side * 10 * dt;
    touch(3, 50, pawXY);
    step();
  end
  v = events.bug.Node.CurrValue'; % column -> row
  fprintf('         paw moving sideways at %.1f cm: caught %d\n', ...
    outlineDist(pawXY, v, bugLW), numel(catches) > nCatch0);
  % Towards the bug at 10 cm/s: caught before the paw is within catchMargin
  dCatch = NaN;
  for k = 1:60
    v = events.bug.Node.CurrValue'; % column -> row
    toBug = (v(1:2) - pawXY) / norm(v(1:2) - pawXY);
    pawXY = pawXY + toBug * 10 * dt;
    touch(3, 50, pawXY);
    step();
    if numel(catches) > nCatch0
      v = events.bug.Node.CurrValue'; % where it was caught (it may have turned)
      dCatch = outlineDist(pawXY, v, bugLW);
      break
    end
  end
  touch(4, 50, pawXY);
  fprintf('         paw moving towards the bug: caught at %.2f cm (catchMargin %g, with snout %g)\n', ...
    dCatch, M, reach);
  for k = 1:round((pars.caughtDuration + 0.5) / dt); step(); end
end

%% 3. New trial parameters (as with conditional params) change the bug
fast = pars;
fast.wanderThrust = 2 * pars.wanderThrust;
post(p, fast);
B = zeros(0, 6);
for k = 1:round(10 / dt)
  step();
  B(end+1,:) = events.bug.Node.CurrValue'; % column -> row %#ok<AGROW>
end
sp = hypot(diff(B(:,1)), diff(B(:,2))) / dt;
fprintf('Trial params: wanderThrust %g -> %g, median wander speed now %.1f cm/s\n', ...
  pars.wanderThrust, fast.wanderThrust, median(sp(B(2:end,5) == 1)));

%% 4. A still touch landing on the visible bug catches it: it freezes,
% grows and flashes for caughtDuration, with the reward half way through
paw = [-17 0]; spawnDist = [];
for c = 1:pars.targetCatches
  waitVisible();
  b = events.bug.Node.CurrValue'; % column -> row
  trials0 = events.endTrial.Node.CurrValue; % (the threat test may have caught it already)
  if isempty(trials0); trials0 = 0; end
  touch(2, 20 + c, b(1:2));
  step();
  touch(4, 20 + c, b(1:2));
  step();
  a0 = events.bug.Node.CurrValue'; % column -> row
  bl = layerOf('b_bug');
  size0 = bl(1).size(1);
  nRewarded0 = numel(rewardedFlags);
  tReward = NaN; maxMove = 0; maxGrowth = 1; flips = 0; lastLo = bl(2).minColour(1);
  nSteps = round(pars.caughtDuration / dt);
  for k = 1:nSteps - 2 % (up to just before the animation ends)
    step();
    a = events.bug.Node.CurrValue'; % column -> row
    maxMove = max(maxMove, hypot(a(1) - a0(1), a(2) - a0(2)));
    bl = layerOf('b_bug');
    maxGrowth = max(maxGrowth, bl(1).size(1) / size0);
    flips = flips + (bl(2).minColour(1) ~= lastLo);
    lastLo = bl(2).minColour(1);
    if isnan(tReward) && numel(rewardedFlags) > nRewarded0; tReward = (k + 1) * dt; end
  end
  if c == 1
    fprintf(['Catch 1: catches=%s, still alive while caught %d, moved %.2f cm, grew x%.2f, ' ...
      '%d colour swaps, reward event at %.2f s (expected %.2f), trial ended early %d\n'], ...
      mat2str(catches), a(5), maxMove, maxGrowth, flips, tReward, ...
      pars.caughtDuration / 2, isequal(events.endTrial.Node.CurrValue, trials0 + 1));
  end
  for k = 1:3; step(); end
  a = events.bug.Node.CurrValue'; % column -> row
  if c == 1
    fprintf('        after the animation: alive %d, trial ended %d\n', a(5), ...
      isequal(events.endTrial.Node.CurrValue, trials0 + 1));
  end
  if ~stopped % (after the last catch the session stops and ignores touches)
    % A paw held just inside the left edge while the bug respawns: the bug
    % must come onto the screen at least spawnClearance away from it
    for k = 1:round((pars.respawnDelay + 0.5) / dt)
      touch(3, 40, paw);
      step();
      a = events.bug.Node.CurrValue'; % column -> row
      if a(5); break; end
    end
    touch(4, 40, paw);
    entry = min(max(a(1:2), -dims / 2), dims / 2);
    spawnDist(end+1) = hypot(entry(1) - paw(1), entry(2) - paw(2)); %#ok<AGROW>
  end
end
fprintf('Respawns with a paw at %s: entry distances %s cm (clearance %g)\n', ...
  mat2str(paw), mat2str(spawnDist, 3), pars.spawnClearance);
fprintf('%d catches, %d rewarded (p = %g), %d reward outputs totalling %g ul; rewarded events match outputs: %d\n', ...
  numel(catches), sum(rewardedFlags), pars.rewardProbability, numel(rewards), sum(rewards), ...
  sum(rewardedFlags) == numel(rewards) && numel(rewardedFlags) == numel(catches));
fprintf('expStop after target: %d\n', stopped);
% Rigbox saves events with sig.Registry/logs at the end; it must not fail
warning('off', 'MATLAB:structOnObject');
raw = struct(events); % StructRef hides its properties from dot indexing
entryLogs = raw.EntryLogs;
for f = fieldnames(events)'
  lg = entryLogs.(f{1}).Node.CurrValue;
  try
    [lg.value]; %#ok<VUNUS>
  catch
    fprintf('Event %s cannot be saved; value sizes: %s\n', f{1}, ...
      strjoin(unique(arrayfun(@(l) mat2str(size(l.value)), lg, 'UniformOutput', false)), ' '));
  end
end
L = logs(events);
fprintf('Saved events OK: %s\n', strjoin(fieldnames(L)', ', '));
% The task's own log, saved by finishSession at expStop
f = dir(fullfile(logDir, '*_MouseChase.mat'));
f2 = dir(fullfile(logDir2, '*_MouseChase.mat'));
fprintf('Session log saved in both folders (local + server): %d\n', ~isempty(f) && ~isempty(f2));
if isempty(f)
  fprintf('Session log NOT saved\n');
else
  mc = load(fullfile(logDir, f(1).name));
  mc = mc.mouseChase;
  fprintf('Session log %s: bug %s, touchEvents %s, catchLog %s (rewarded %s), environment %s\n', ...
    f(1).name, mat2str(size(mc.bug)), mat2str(size(mc.touchEvents)), ...
    mat2str(size(mc.catchLog)), mat2str(mc.catchLog(:,4)'), mc.environment.id);
end
% mc shows every event value with toStr; it must not fail
for f = fieldnames(events)'
  v = events.(f{1}).Node.CurrValue;
  try
    toStr(v);
  catch ex
    fprintf('mc cannot display %s: %s\n', f{1}, ex.message);
  end
end
sender.close();
setenv('MOUSECHASE_TOUCH_PORT', '');
setenv('MOUSECHASE_DEBUG_EVENTS', '');
setenv('MOUSECHASE_LOG_DIR', '');
delete(fakeCleanup); % callbacks keep this workspace alive, so clean up explicitly

  function step()
    SIM.time = SIM.time + dt;
    post(t, SIM.time);
  end
  function touch(type, id, xy)
    % Send a report like tools/touchReader.ps1 does (type 4 = lifted)
    L = round(toPx(xy) ./ W * 32767);
    msg = int8(sprintf('R %.5f 1\n%d %d %d %d 800 800\n', SIM.time, id, type ~= 4, L(1), L(2)));
    sender.send(java.net.DatagramPacket(msg, numel(msg), ...
      java.net.InetAddress.getByName('127.0.0.1'), touchPort));
    pause(0.002);
  end
  function waitVisible()
    for kk = 1:round(60 / dt)
      v = events.bug.Node.CurrValue'; % column -> row
      if ~v(4) && v(5) && ~v(6) && all(abs(v(1:2)) < dims / 2 - 3); return; end
      step();
    end
    error('bug never became visible');
  end
  function od = outlineDist(xy, bug, lw)
    % Distance from xy to the outline of a bug [x y heading ...] of size
    % lw ([length width]), 0 on the bug (densely sampled outline). (Names
    % prefixed with o: nested functions share the variables above.)
    oT = linspace(0, 2 * pi, 2000)';
    oC = cos(bug(3)); oS = sin(bug(3));
    oP = [lw(1) / 2 * cos(oT), lw(2) / 2 * sin(oT)];
    oP = bug(1:2) + [oP(:,1) * oC - oP(:,2) * oS, oP(:,1) * oS + oP(:,2) * oC];
    oR = xy - bug(1:2);
    oU = oR(1) * oC + oR(2) * oS; oW = -oR(1) * oS + oR(2) * oC;
    od = 0;
    if (oU / (lw(1) / 2))^2 + (oW / (lw(2) / 2))^2 > 1
      od = min(hypot(oP(:,1) - xy(1), oP(:,2) - xy(2)));
    end
  end
  function addReward(v); rewards(end+1) = v; end
  function addCatch(v); catches(end+1) = v; end
  function addRewarded(v); rewardedFlags(end+1) = v; end
  function setStop(); stopped = true; end
  function l = layerOf(name)
    v = visual.(name).Node.CurrValue;
    l = v.layers;
    if isobject(l); l = l.Node.CurrValue; end
  end
  function checkVisual()
    names = fieldnames(visual);
    fprintf('Visual layers (%d): %s\n', numel(names), strjoin(names', ', '));
    bl = layerOf('b_bug'); % Gabor: [window, grating]
    fprintf('        bug layers: %d, window show %d, size %s deg, offset %s deg; grating %s, phase tied to bug %d\n', ...
      numel(bl), bl(1).show, mat2str(bl(1).size(:)', 3), mat2str(bl(1).texOffset(:)', 3), ...
      bl(2).textureId, abs(bl(2).texOffset(1) - bl(1).texOffset(1)) < 1e-9);
    rl = layerOf('c_rect01');
    fprintf('        rock layer: show %d, size %s deg\n', rl.show, mat2str(rl.size(:)', 3));
    fl = layerOf('a_floor');
    fprintf('        floor layer: show %d, size %s deg\n', fl(end).show, mat2str(fl(end).size', 3));
  end
end
