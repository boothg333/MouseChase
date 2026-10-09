function simMouseChase()
% Headless simulation of MouseChaseTouch with scripted touches.
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
pars.targetCatches = 3; % keep it quick
pars.trainingStage = 3; % a stage where the bug flees (stage 1 doesn't)
pars.rewardProbability = 0.5; % overrides the stage's value
pars.wanderThrust = 24; % explicit, for the trial-parameter check below
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
B = zeros(0, 5);
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

%% 3. New trial parameters (as with conditional params) change the bug
fast = pars;
fast.wanderThrust = 2 * pars.wanderThrust;
post(p, fast);
B = zeros(0, 5);
for k = 1:round(10 / dt)
  step();
  B(end+1,:) = events.bug.Node.CurrValue'; % column -> row %#ok<AGROW>
end
sp = hypot(diff(B(:,1)), diff(B(:,2))) / dt;
fprintf('Trial params: wanderThrust %g -> %g, median wander speed now %.1f cm/s\n', ...
  pars.wanderThrust, fast.wanderThrust, median(sp(B(2:end,5) == 1)));

%% 4. A still touch landing on the visible bug catches it
for c = 1:pars.targetCatches
  waitVisible();
  b = events.bug.Node.CurrValue'; % column -> row
  touch(2, 20 + c, b(1:2));
  step();
  touch(4, 20 + c, b(1:2));
  step();
  a = events.bug.Node.CurrValue'; % column -> row
  if c == 1
    fprintf('Catch 1: catches=%s rewarded=%s reward=%s alive after=%d\n', ...
      mat2str(catches), mat2str(rewardedFlags), mat2str(rewards), a(5));
    for k = 1:round(1.5 / dt); step(); end
    a = events.bug.Node.CurrValue'; % column -> row
    fprintf('        alive 1.5 s later: %d', a(5));
    for k = 1:round(1 / dt); step(); end
    a = events.bug.Node.CurrValue'; % column -> row
    fprintf(', 2.5 s later: %d\n', a(5));
  end
end
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
      if ~v(4) && v(5) && all(abs(v(1:2)) < dims / 2 - 3); return; end
      step();
    end
    error('bug never became visible');
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
    bl = layerOf('b_bug');
    fprintf('        bug layer: show %d, size %s deg, offset %s deg\n', bl.show, mat2str(bl.size(:)', 3), mat2str(bl.texOffset(:)', 3));
    rl = layerOf('c_rect01');
    fprintf('        rock layer: show %d, size %s deg\n', rl.show, mat2str(rl.size(:)', 3));
    fl = layerOf('a_floor');
    fprintf('        floor layer: show %d, size %s deg\n', fl(end).show, mat2str(fl(end).size', 3));
  end
end
