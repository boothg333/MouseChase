function checkDrawAlignment()
% Run MouseChaseDemo headless and check that the bug layer Signals receives
% is drawn (per the reconstructed slimshady/vis.screen maths) exactly where
% the game thinks the bug is, with its long axis along the heading.
here = fileparts(mfilename('fullpath'));
[~, fakeCleanup] = makeFakePtb(); %#ok<ASGLU> removed from the path on return
defFile = fullfile(fileparts(fileparts(here)), 'MouseChaseDemo.m');
global SIM
SIM = struct('time', 0, 'released', 0);
SIM.queue = struct('Type', {}, 'Keycode', {}, 'X', {}, 'Y', {}, 'Valuators', {}, 'Time', {});
rng(2);
W = 1280; H = 1024; dims = [37.6 30.1]; D = 100; cpp = dims ./ [W H];
scr = vis.screen([0 0 D], 0, dims, [0 0 W H]);
P = double(scr.projection);

pars = exp.inferParameters(defFile);
pars = rmfield(pars, {'numRepeats', 'defFunction', 'type'});
setenv('MOUSECHASE_DEBUG_EVENTS', '1'); % log the bug position as an event
net = sig.Net; clk = @() SIM.time;
t = net.origin('t');
events = sig.Registry(clk);
events.expStart = net.origin('expStart');
events.newTrial = net.origin('newTrial');
p = net.subscriptableOrigin('pars');
visual = StructRef;
expDef = fileFunction(defFile);
expDef(t, events, p, visual, sig.Registry(clk), sig.Registry(clk), []);
setenv('MOUSECHASE_TOUCH_PORT', '50556'); % don't start the real touch reader
post(p, pars); post(t, 0); post(events.expStart, 'sim');

maxPosErr = 0; maxAngErr = 0; n = 0;
for k = 1:1800
  SIM.time = SIM.time + 1/60;
  post(t, SIM.time);
  if mod(k, 10); continue; end
  b = events.bug.Node.CurrValue; % [x y heading hidden alive]
  if ~b(5); continue; end
  L = visual.b_bug.Node.CurrValue.layers;
  if isobject(L); L = L.Node.CurrValue; end
  want = [b(1) / cpp(1) + W/2, H/2 - b(2) / cpp(2)];
  got = texPointPx(L.texOffset, L.texAngle, [0 0]);
  maxPosErr = max(maxPosErr, norm(got - want));
  tip = texPointPx(L.texOffset, L.texAngle, [0.3 * L.size(1), 0]) - got; % towards +u (long axis)
  drawnHeading = atan2(-tip(2), tip(1));
  maxAngErr = max(maxAngErr, abs(mod(drawnHeading - b(3) + pi, 2*pi) - pi) * 180 / pi);
  n = n + 1;
end
fprintf('Checked %d frames: max position error %.2f px, max heading error %.2f deg\n', ...
  n, maxPosErr, maxAngErr);
delete(fakeCleanup); % callbacks keep this workspace alive, so clean up explicitly

  function px = texPointPx(off, ang, duv)
    R = [cosd(ang) -sind(ang); sind(ang) cosd(ang)];
    a = R \ (off(:) + duv(:));
    th = a(1); ph = -a(2);
    v = [400 * [-cosd(ph)*cosd(th); sind(ph); -cosd(ph)*sind(th)]; 1];
    clip = P * v;
    ndc = clip(1:2) / clip(4);
    px = [(ndc(1) + 1) / 2 * W, (1 - ndc(2)) / 2 * H];
  end
end
