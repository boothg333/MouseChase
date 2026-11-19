function L = mouseChaseLabelCatches(C, varargin)
%MOUSECHASELABELCATCHES Label catches by eye from the top camera video.
%   L = MOUSECHASELABELCATCHES(C, 'labelFile', FILE) takes a catch table of
%   one or more sessions (mouseChaseCatchTable, vertically concatenated),
%   picks a sample of catches stratified by the video's automatic label
%   (C.videoType), prepares a short clip of each (once; cached in
%   'clipDir') and plays them one by one, for a label by key:
%     1  deliberate strike: a paw (or the snout) going for the bug
%     2  incidental paw: a paw that happens to land on / sit by the bug
%     3  tail
%     4  other body part (belly, hind leg while turning, ...)
%     5  no mouse there (artefact)
%     0  can't tell
%   and: space pause/play, left/right step a frame (paused), o overlays on/off,
%   s/f slower/faster, backspace back to the previous catch, q quit.
%   Labels are saved to FILE (CSV) after every key, and the labelling picks
%   up where it stopped. The automatic label is not shown (blind).
%   Clips run from -1 s to +0.3 s around the catch, at 0.5x speed, in
%   screen cm around the bug (x right, y up), with the bug's outline (orange),
%   the contact that made the catch (red ring) and the other contacts (blue)
%   drawn on top (toggle with o).
%   Options (name, value):
%     'labelFile' CSV for the labels (required)
%     'n'         number of catches to label (150)
%     'clipDir'   cache for the clips (tempdir\MouseChase\labelClips)
%     'halfWidth' cm shown either side of the bug (9)
%     'seed'      for the sample (1)
%     'prepareOnly'  true: only prepare the clips (e.g. in a batch job)
%   Returns the table of labels.

o = struct('labelFile', '', 'n', 150, 'clipDir', fullfile(tempdir, 'MouseChase', 'labelClips'), ...
  'halfWidth', 9, 'seed', 1, 'prepareOnly', false);
for k = 1:2:numel(varargin); o.(varargin{k}) = varargin{k+1}; end
assert(~isempty(o.labelFile), 'mouseChaseLabelCatches:noFile', 'Give a ''labelFile'' for the labels');
if ~isfolder(o.clipDir); mkdir(o.clipDir); end

%% The sample: stratified by the automatic label, in random order
sampleFile = fullfile(o.clipDir, sprintf('sample_n%d_seed%d.mat', o.n, o.seed));
if exist(sampleFile, 'file')
  s = load(sampleFile); pick = s.pick;
else
  rs = RandStream('mt19937ar', 'Seed', o.seed);
  types = categories(C.videoType);
  per = ceil(o.n / numel(types));
  pick = zeros(0, 1);
  for k = 1:numel(types)
    idx = find(C.videoType == types{k});
    pick = [pick; idx(randperm(rs, numel(idx), min(per, numel(idx))))]; %#ok<AGROW>
  end
  rest = setdiff((1:height(C))', pick); % fill up from the rest if a type is rare
  extra = o.n - numel(pick);
  if extra > 0; pick = [pick; rest(randperm(rs, numel(rest), min(extra, numel(rest))))]; end
  pick = pick(randperm(rs, numel(pick)));
  pick = pick(1:min(o.n, end));
  save(sampleFile, 'pick');
end
Cs = C(pick,:);

%% Clips (prepared once per session)
clipFile = @(r) fullfile(o.clipDir, sprintf('%s_catch%03d.mat', Cs.expRef(r), Cs.catch(r)));
todo = find(~arrayfun(@(r) exist(clipFile(r), 'file') == 2, 1:height(Cs)));
if ~isempty(todo)
  sessions = unique(Cs.expRef(todo));
  for s = 1:numel(sessions)
    rows = todo(Cs.expRef(todo) == sessions(s));
    fprintf('%s: preparing %d clips\n', sessions(s), numel(rows));
    [m, folder] = mouseChaseLoad(char(sessions(s)));
    prepareClips(m, folder, Cs(rows,:), arrayfun(clipFile, rows, 'Uni', 0), o.halfWidth);
  end
end
if o.prepareOnly; L = []; return; end

%% Labelling
names = ["can't tell" "deliberate strike" "incidental paw" "tail" "other body part" "no mouse"];
if exist(o.labelFile, 'file')
  L = readtable(o.labelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve'); % ('catch' is a keyword)
else
  L = table(strings(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    'VariableNames', {'expRef', 'catch', 'label', 'labelName', 'labelledAt'});
end
done = @(r) any(L.expRef == Cs.expRef(r) & L.catch == Cs.catch(r));
ui = struct('key', '', 'playing', true, 'overlay', true, 'speed', 0.5); % (before the figure: keys)
fig = figure('Name', 'MouseChase: label catches', 'Color', 'k', 'Position', [100 80 760 820], ...
  'KeyPressFcn', @onKey, 'NumberTitle', 'off', 'MenuBar', 'none');
ax = axes(fig, 'Position', [0.02 0.1 0.96 0.84]);
help = sprintf(['1 deliberate strike   2 incidental paw   3 tail   4 other body part   ' ...
  '5 no mouse   0 can''t tell\nspace pause   \x2190\x2192 step   o overlays   s/f slower/faster   ' ...
  'backspace previous   q quit']);
annotation(fig, 'textbox', [0 0 1 0.08], 'String', help, 'Color', [0.8 0.8 0.8], ...
  'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontSize', 10);
r = find(~arrayfun(done, 1:height(Cs)), 1);
while ~isempty(r) && r <= height(Cs) && isvalid(fig)
  clip = load(clipFile(r)); clip = clip.clip;
  nF = numel(clip.t);
  f = 1; ui.key = ''; ui.playing = true;
  while isvalid(fig) && isempty(ui.key)
    drawClipFrame(ax, clip, f, ui.overlay, o.halfWidth);
    title(ax, sprintf('%d / %d  (%d labelled)     %+.2f s     %s', r, height(Cs), height(L), ...
      clip.t(f), iff(ui.playing, sprintf('%.2gx', ui.speed), 'paused')), 'Color', 'w');
    drawnow;
    if ui.playing
      pause(1 / (60 * ui.speed));
      f = f + 1;
      if f > nF; f = 1; pause(0.4); end
    else
      pause(0.03);
    end
    if ~isempty(ui.key) && any(strcmp(ui.key, {'leftarrow', 'rightarrow'}))
      f = min(max(f + iff(strcmp(ui.key, 'rightarrow'), 1, -1), 1), nF);
      ui.key = '';
    end
  end
  if ~isvalid(fig); break; end
  key = ui.key;
  if strcmp(key, 'q'); break; end
  if strcmp(key, 'backspace')
    r = max(1, r - 1);
    L(L.expRef == Cs.expRef(r) & L.catch == Cs.catch(r),:) = []; % relabel it
    continue
  end
  lab = str2double(key);
  L(L.expRef == Cs.expRef(r) & L.catch == Cs.catch(r),:) = [];
  L = [L; {Cs.expRef(r), Cs.catch(r), lab, names(lab + 1), string(datetime('now'))}]; %#ok<AGROW>
  writetable(L, o.labelFile);
  r = r + 1;
  while r <= height(Cs) && done(r); r = r + 1; end
end
if isvalid(fig); close(fig); end
fprintf('%d catches labelled (%s)\n', height(L), o.labelFile);

  function onKey(~, ev)
  switch ev.Key
    case 'space', ui.playing = ~ui.playing;
    case 'o', ui.overlay = ~ui.overlay;
    case 's', ui.speed = max(0.125, ui.speed / 2);
    case 'f', ui.speed = min(2, ui.speed * 2);
    case {'leftarrow', 'rightarrow'}, ui.playing = false; ui.key = ev.Key;
    case {'0', '1', '2', '3', '4', '5', 'q', 'backspace'}, ui.key = ev.Key;
    otherwise
      if any(strcmp(ev.Character, {'0', '1', '2', '3', '4', '5'})); ui.key = ev.Character; end
  end
  end
end

%% ===================== Helpers =====================

function prepareClips(m, folder, Cs, files, halfWidth)
%PREPARECLIPS Video frames around each catch, warped to screen cm centred on
%   the bug at the catch, with the contacts and bug of each frame.
V = mouseChaseVideo(m, folder);
S = mouseChaseMetrics(m, 'nShuffle', 2);
E = S.touches;
B = m.bug;
res = 0.08; % cm per pixel
tform = invert(V.H);
for k = 1:height(Cs)
  t0 = Cs.t(k);
  c = [Cs.x(k) Cs.y(k)];
  rB = find(abs(B(:,1) - t0) < 1e-6, 1);
  ctr = B(rB,2:3);
  ref = imref2d(round([2 2] * halfWidth / res), ctr(1) + [-1 1] * halfWidth, ctr(2) + [-1 1] * halfWidth);
  fr = V.frameIndex(t0 - 1):V.frameIndex(t0 + 0.3);
  clip = struct('expRef', m.expRef, 'catch', Cs.catch(k), 'centre', ctr, 'id', Cs.id(k), ...
    'contactXY', c, 'bugLength', m.params.bugLength, 'bugWidth', m.params.bugWidth, ...
    'frames', zeros(ref.ImageSize(1), ref.ImageSize(2), numel(fr), 'uint8'), ...
    't', zeros(1, numel(fr)), 'bug', nan(numel(fr), 4), 'contacts', {cell(1, numel(fr))});
  for j = 1:numel(fr)
    t = V.camTimes(fr(j)) - V.blockToCam;
    clip.t(j) = t - t0;
    clip.frames(:,:,j) = imwarp(V.readFrame(t), tform, 'OutputView', ref, 'FillValues', 0);
    r = find(B(:,1) <= t, 1, 'last');
    if ~isempty(r) && B(r,6); clip.bug(j,:) = [B(r,2:4) B(r,1) >= t0]; end
    recent = E(E(:,7) <= t & E(:,7) > t - 0.25,:);
    if ~isempty(recent)
      [~, last] = unique(recent(:,2), 'last');
      down = recent(last,:);
      clip.contacts{j} = down(down(:,1) ~= 4, 2:4); % [id x y]
    end
  end
  save(files{k}, 'clip');
end
end

function drawClipFrame(ax, clip, f, overlay, halfWidth)
cla(ax);
xl = clip.centre(1) + [-1 1] * halfWidth; yl = clip.centre(2) + [-1 1] * halfWidth;
imagesc(ax, xl, yl, clip.frames(:,:,f));
colormap(ax, gray(256)); clim(ax, [0 255]);
set(ax, 'YDir', 'normal', 'XTick', [], 'YTick', [], 'DataAspectRatio', [1 1 1], 'XLim', xl, 'YLim', yl);
hold(ax, 'on');
if ~overlay; return; end
if ~isnan(clip.bug(f,1))
  a = linspace(0, 2 * pi, 60)';
  e = [clip.bugLength / 2 * cos(a), clip.bugWidth / 2 * sin(a)];
  h = clip.bug(f,3);
  xy = clip.bug(f,1:2) + e * [cos(h) sin(h); -sin(h) cos(h)];
  plot(ax, xy(:,1), xy(:,2), 'Color', [0.92 0.41 0.2], 'LineWidth', 1);
end
D = clip.contacts{f};
if ~isempty(D)
  isC = D(:,1) == clip.id;
  plot(ax, D(~isC,2), D(~isC,3), '.', 'Color', [0.16 0.47 0.84], 'MarkerSize', 14);
  if any(isC) && clip.t(f) <= 0.05 % the catching contact, up to the catch
    plot(ax, D(isC,2), D(isC,3), 'o', 'Color', [0.9 0.15 0.15], 'MarkerSize', 12, 'LineWidth', 1.5);
  end
end
if abs(clip.t(f)) < 1 / 60
  text(ax, 0.02, 0.98, 'CATCH', 'Units', 'normalized', 'Color', 'y', 'FontWeight', 'bold', ...
    'VerticalAlignment', 'top');
end
end

function v = iff(c, a, b)
if c; v = a; else; v = b; end
end
