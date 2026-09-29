function simMouseChase()
% Headless simulation of MouseChaseDemo with scripted touches.
here = fileparts(mfilename('fullpath'));
[~, fakeCleanup] = makeFakePtb(); %#ok<ASGLU> removed from the path on return
defFile = fullfile(fileparts(fileparts(here)), 'MouseChaseDemo.m');
global SIM
SIM = struct('time', 0, 'released', 0);
SIM.queue = struct('Type', {}, 'Keycode', {}, 'X', {}, 'Y', {}, 'Valuators', {}, 'Time', {});
rng(1);

pars = exp.inferParameters(defFile);
pars = rmfield(pars, {'numRepeats', 'defFunction', 'type'});
pars.targetCatches = 3; % keep it quick
pars.rewardProbability = 0.5;

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
  B(end+1,:) = events.bug.Node.CurrValue; %#ok<AGROW>
end
fprintf('Wander: x in [%.1f %.1f], y in [%.1f %.1f] cm, visible %.0f%% of frames, alive all: %d\n', ...
  min(B(:,1)), max(B(:,1)), min(B(:,2)), max(B(:,2)), 100 * mean(~B(:,4)), all(B(:,5)));
sp = hypot(diff(B(:,1)), diff(B(:,2))) / dt;
fprintf('        median speed %.1f cm/s, max %.1f cm/s\n', median(sp), max(sp));
checkVisual();

%% 2. A moving touch approaching the visible bug makes it flee
waitVisible();
b = events.bug.Node.CurrValue;
start = b(1:2) + [6 0];
touch(2, 7, start);
evading = false; spd = [];
for k = 1:30
  prev = events.bug.Node.CurrValue;
  touch(3, 7, start - [k * 0.3, 0]); % 18 cm/s towards the bug
  step();
  now = events.bug.Node.CurrValue;
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
  B(end+1,:) = events.bug.Node.CurrValue; %#ok<AGROW>
end
sp = hypot(diff(B(:,1)), diff(B(:,2))) / dt;
fprintf('Trial params: wanderThrust %g -> %g, median wander speed now %.1f cm/s\n', ...
  pars.wanderThrust, fast.wanderThrust, median(sp(B(2:end,5) == 1)));

%% 4. A still touch landing on the visible bug catches it
for c = 1:pars.targetCatches
  waitVisible();
  b = events.bug.Node.CurrValue;
  touch(2, 20 + c, b(1:2));
  step();
  touch(4, 20 + c, b(1:2));
  step();
  a = events.bug.Node.CurrValue;
  if c == 1
    fprintf('Catch 1: catches=%s rewarded=%s reward=%s alive after=%d\n', ...
      mat2str(catches), mat2str(rewardedFlags), mat2str(rewards), a(5));
    for k = 1:round(1.5 / dt); step(); end
    a = events.bug.Node.CurrValue;
    fprintf('        alive 1.5 s later: %d', a(5));
    for k = 1:round(1 / dt); step(); end
    a = events.bug.Node.CurrValue;
    fprintf(', 2.5 s later: %d\n', a(5));
  end
end
fprintf('%d catches, %d rewarded (p = %g), %d reward outputs totalling %g ul; rewarded events match outputs: %d\n', ...
  numel(catches), sum(rewardedFlags), pars.rewardProbability, numel(rewards), sum(rewards), ...
  sum(rewardedFlags) == numel(rewards) && numel(rewardedFlags) == numel(catches));
fprintf('expStop after target: %d, touch queue released: %d\n', stopped, SIM.released);
delete(fakeCleanup); % callbacks keep this workspace alive, so clean up explicitly

  function step()
    SIM.time = SIM.time + dt;
    post(t, SIM.time);
  end
  function touch(type, id, xy)
    px = toPx(xy);
    SIM.queue(end+1) = struct('Type', type, 'Keycode', id, 'X', px(1), 'Y', px(2), ...
      'Valuators', [px 25 25 0], 'Time', SIM.time);
  end
  function waitVisible()
    for kk = 1:round(60 / dt)
      v = events.bug.Node.CurrValue;
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
