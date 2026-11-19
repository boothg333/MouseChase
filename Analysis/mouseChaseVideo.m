function V = mouseChaseVideo(m, folder, varargin)
%MOUSECHASEVIDEO Link a MouseChase session's top camera video to its log.
%   V = MOUSECHASEVIDEO(M, FOLDER) for the 'mouseChase' struct M whose files
%   are in FOLDER (see mouseChaseLoad) returns:
%     V.camTimes       camera time of each frame (s, camera clock)
%     V.blockToCam     offset: camera time = block time + V.blockToCam
%     V.H              projective transform, screen cm -> video px
%     V.screenCornersPx  the screen's corners in the video
%     V.frameIndex(t)  frame nearest to block time(s) t
%     V.readFrame(t)   the video frame (grey, uint8) at block time t
%   Options (name, value):
%     'cacheDir'  where the alignment is saved, as the server copy is read
%                 only (default: tempdir\MouseChase)
%     'redo'      true: align again even if cached
%
%   Clock: the camera sees the screen switch from the pre-experiment
%   background to the floor at the first stimulus update of the block, a
%   persistent step in image brightness. The camera clock and the stimulus
%   computer's clock don't measurably drift over a session (the camSync
%   pulses at the start and end match Timeline to < 1 ms over 20 min), so
%   that step gives the offset. Precision: about a frame (17 ms at 60 Hz).
%   Geometry: the bright screen in the pre-experiment frames gives its four
%   corners; which screen corner is which is chosen so that the logged bug
%   positions fall on the dark bug in the video. The arena walls cover the
%   screen's edges (~2 cm on the right in EB056's sessions), so the visible
%   corners are inside the image's, and the camera or arena may move between
%   sessions: so every session's transform is refitted to the bug itself.
%   In ~400 frames the bug is found as a bug-sized blob that differs from
%   the median of those frames (whatever the bug looks like; fixed bright
%   spots cancel, the mouse is too big); its logged positions are matched to
%   the nearest blob, the transform refitted, and this repeated with a
%   shrinking search window (the corners alone can be several cm off). The
%   bug is drawn a little after it is logged: the lag is fitted too
%   (V.displayLag, s: the logged position at frame time minus the lag fits
%   best; it includes the clock offset's error). V.refineResidualCm is the
%   median remaining error, lens distortion included. A fit that moves the
%   screen's corners > 6 cm from the visible ones is rejected.

o = struct('cacheDir', fullfile(tempdir, 'MouseChase'), 'redo', false);
for k = 1:2:numel(varargin); o.(varargin{k}) = varargin{k+1}; end
ref = m.expRef;
files = {fullfile(folder, [ref '_topCam.mj2']), fullfile(folder, [ref '_topCam_lastFrames.mj2'])};
files = files(cellfun(@(f) exist(f, 'file') == 2, files));
assert(~isempty(files), 'mouseChaseVideo:noVideo', 'No top camera video for %s in %s', ref, folder);
cacheFile = fullfile(o.cacheDir, [ref '_video.mat']);

if exist(cacheFile, 'file') && ~o.redo
  V = load(cacheFile); V = V.V;
end
if ~exist('V', 'var') || ~isfield(V, 'refineVersion') || V.refineVersion < 4 % (older caches: redo)
  V = align(m, folder, files);
  if ~isfolder(o.cacheDir); mkdir(o.cacheDir); end
  save(cacheFile, 'V');
end
V.files = files;
readers = cellfun(@VideoReader, files, 'Uni', 0); % (handles: created once, shared)
V.frameIndex = @(t) frameIndex(V, t);
V.readFrame = @(t) readAt(readers, V.nFrames, frameIndex(V, t));
end

%% ===================== Alignment =====================

function V = align(m, folder, files)
ref = m.expRef;
fprintf('%s: aligning the video (once; cached)\n', ref);
ct = readtable(fullfile(folder, [ref '_topCam_times.txt']), 'Delimiter', '\t', 'FileType', 'text');
camT = ct.Time;
nFrames = zeros(1, numel(files));
for k = 1:numel(files); v = VideoReader(files{k}); nFrames(k) = v.NumFrames; end
camT = camT(1:min(numel(camT), sum(nFrames)));
V = struct('expRef', ref, 'camTimes', camT, 'nFrames', nFrames);

% Clock: the floor appearing at the first stimulus update
b = load(fullfile(folder, [ref '_Block.mat']), 'block');
tFirstDraw = b.block.stimWindowUpdateTimes(1);
v = VideoReader(files{1});
nRead = min(v.NumFrames, 6000);
bright = zeros(nRead, 1);
for a = 1:500:nRead
  F = read(v, [a min(a + 499, nRead)]);
  bright(a:min(a + 499, nRead)) = squeeze(mean(F, [1 2 3]));
end
w = 60; % frames either side (the camSync dip is ~12 frames: ignored by the median)
score = inf(nRead, 1);
for i = w + 1:nRead - w
  score(i) = median(bright(i+1:i+w)) - median(bright(i-w:i));
end
[drop, iStep] = min(score);
assert(drop < -5, 'mouseChaseVideo:noFloorStep', ...
  '%s: no brightness step at the start of the experiment in the first %d frames', ref, nRead);
pre = median(bright(iStep-w:iStep)); post = median(bright(iStep+1:iStep+w));
mid = (pre + post) / 2;
onset = NaN;
for k = iStep - w:iStep + w % first frame that stays below the midpoint
  if all(bright(k:k+20) < mid); onset = k; break; end
end
V.floorFrame = onset;
V.blockToCam = camT(onset) - tFirstDraw;
fprintf('  floor appears at frame %d (camera %.3f s, block %.3f s)\n', onset, camT(onset), tFirstDraw);

% Screen corners: the bright screen before the experiment
preFrames = max(1, onset - 400):onset - 30;
P = read(v, [preFrames(1) preFrames(end)]);
I = median(double(squeeze(P(:,:,1,:))), 3);
mask = imbinarize(I / 255);
cc = bwconncomp(mask);
[~, big] = max(cellfun(@numel, cc.PixelIdxList));
mask = false(size(mask)); mask(cc.PixelIdxList{big}) = true;
mask = imfill(imopen(mask, strel('disk', 5)), 'holes');
[yy, xx] = find(mask);
[~, iTL] = min(xx + yy); [~, iTR] = max(xx - yy); [~, iBR] = max(xx + yy); [~, iBL] = min(xx - yy);
cornersPx = [xx([iTL iTR iBR iBL]) yy([iTL iTR iBR iBL])]; % image: TL TR BR BL
V.screenCornersPx = cornersPx;

% Which screen corner is which: try the 8 assignments, keep the one that
% puts the logged bug on dark pixels
half = m.geometry.dimsCm / 2;
cm = [-half(1) half(2); half(1) half(2); half(1) -half(2); -half(1) -half(2)]; % cyclic
cands = cell(1, 8);
for s = 0:3
  cands{s+1} = circshift(cm, s, 1);
  cands{s+5} = circshift(flipud(cm), s, 1);
end
B = m.bug;
vis = find(B(:,6) == 1 & B(:,5) == 0 & B(:,1) + V.blockToCam > camT(1) & B(:,1) + V.blockToCam < camT(end));
pick = vis(round(linspace(1, numel(vis), min(120, numel(vis)))));
fr = arrayfun(@(t) frameIndex(V, t), B(pick,1));
readers = cellfun(@VideoReader, files, 'Uni', 0);
frames = zeros(v.Height, v.Width, numel(fr));
for k = 1:numel(fr); frames(:,:,k) = readAt(readers, nFrames, fr(k)); end
bg = median(frames, 3);
ratio = nan(8, 1);
for c = 1:8
  H = fitgeotform2d(cands{c}, cornersPx, 'projective');
  px = round(transformPointsForward(H, B(pick,2:3)));
  rad = 6; % px: darkest pixel near the bug (allows for some lens distortion)
  ok = px(:,1) > rad & px(:,1) <= v.Width - rad & px(:,2) > rad & px(:,2) <= v.Height - rad;
  r = nan(numel(pick), 1);
  for k = find(ok)'
    rows = px(k,2)-rad:px(k,2)+rad; cols = px(k,1)-rad:px(k,1)+rad;
    q = frames(rows, cols, k) ./ max(bg(rows, cols), 1);
    r(k) = min(q(:));
  end
  ratio(c) = median(r, 'omitnan');
end
[best, c] = min(ratio);
V.H = fitgeotform2d(cands{c}, cornersPx, 'projective');
V.orientationScore = ratio; % median darkest frame/background ratio at the bug, per assignment
others = sort(ratio(setdiff(1:8, c)));
fprintf('  screen orientation %d: bug at %.0f%% of background brightness (next best %.0f%%)\n', ...
  c, 100 * best, 100 * others(1));
if others(1) - best < 0.1
  warning('mouseChaseVideo:orientation', ['%s: the screen orientation is ambiguous (bug at ' ...
    '%.0f%% vs %.0f%% of background); check the overlay'], ref, 100 * best, 100 * others(1));
end

% Refine with the bug itself: the walls hide the screen's edges, so the
% visible corners are not the image's corners
V.Hcorners = V.H;
V.refined = false;
V.refineResidualCm = NaN;
c0 = transformPointsForward(V.H, [0 0; 1 0; 0 1]);
pxPerCm = mean([norm(c0(2,:) - c0(1,:)), norm(c0(3,:) - c0(1,:))]);
% bug fully on the screen (not in a crevice), visible, and alive
inside = all(abs(B(:,2:3)) <= half - m.params.bugLength / 2, 2);
cand = find(B(:,6) == 1 & B(:,5) == 0 & inside & B(:,1) + V.blockToCam > camT(1) & ...
  B(:,1) + V.blockToCam < camT(end));
pick = cand(round(linspace(1, numel(cand), min(400, numel(cand)))));
pick = unique(pick);
frames = zeros(v.Height, v.Width, numel(pick), 'uint8');
for k = 1:numel(pick); frames(:,:,k) = readAt(readers, nFrames, frameIndex(V, B(pick(k),1))); end
% The bug: what differs from the background (median over these frames, so
% the moving bug and mouse drop out, and fixed bright spots or reflections
% cancel), as a blob of about the bug's size (the mouse is much bigger)
bgB = median(frames, 3);
L = m.params.bugLength;
if isfield(m.params, 'bugWidth') && ~isnan(m.params.bugWidth); W = m.params.bugWidth; else; W = L / 2; end
bugArea = pi / 4 * L * W * pxPerCm^2; % px
blobs = cell(numel(pick), 1); % per frame: [x y] centroids of bug-sized blobs
for k = 1:numel(pick)
  D = abs(double(frames(:,:,k)) - double(bgB)) > 40;
  D = imfill(imclose(D, strel('disk', 2)), 'holes'); % stripes -> one ellipse
  st = regionprops(D, 'Area', 'Centroid');
  st = st([st.Area] >= 0.4 * bugArea & [st.Area] <= 1.8 * bugArea);
  blobs{k} = reshape([st.Centroid], 2, [])';
end
% Iterate: take the blob nearest where the current transform puts the bug,
% refit; the search window shrinks as the transform improves (the corners
% can be several cm off when the camera or walls moved)
H = V.H;
P = B(pick,2:3); % logged positions
winCm = [L / 2 + 5, L / 2 + 2, L / 2 + 1];
for iter = 1:numel(winCm)
  f = fitToBlobs(H, P, blobs, winCm(iter) * pxPerCm, pxPerCm);
  if isempty(f); break; end
  H = f.H;
  fprintf('  refit %d on %d bug positions: median error %.2f cm\n', iter, sum(f.ok), median(f.res));
  best = f; % last good fit
end
% Display lag: a moving bug is drawn where it was logged tau earlier (the
% clock offset's error of ~1 frame is included in tau)
V.displayLag = 0;
if exist('best', 'var')
  tFrame = camT(arrayfun(@(t) frameIndex(V, t), B(pick,1))) - V.blockToCam;
  lags = -0.1:0.01:0.4;
  err = nan(size(lags)); fits = cell(size(lags));
  for i = 1:numel(lags)
    Pl = interp1(B(:,1), B(:,2:3), tFrame - lags(i), 'linear', 'extrap');
    fits{i} = fitToBlobs(best.H, Pl, blobs, winCm(end) * pxPerCm, pxPerCm);
    if ~isempty(fits{i}); err(i) = median(fits{i}.res); end
  end
  [~, i] = min(err);
  best = fits{i};
  V.displayLag = lags(i);
  fprintf('  display lag %.0f ms: median error %.2f cm (no lag: %.2f cm)\n', 1000 * lags(i), err(i), ...
    err(lags == 0));
  V.lagCurve = [lags; err];
end
V.refineVersion = 4;
if exist('best', 'var')
  % sanity check: the screen's corners can't move far from the visible ones
  shift = vecnorm(transformPointsForward(best.H, cands{c}) - cornersPx, 2, 2) / pxPerCm;
  if max(shift) > 6
    warning('mouseChaseVideo:badRefine', ['%s: the bug-fitted transform moves the screen corners ' ...
      'by up to %.1f cm; using the corners only'], ref, max(shift));
    clear best
  end
end
if exist('best', 'var')
  before = vecnorm(transformPointsForward(V.H, best.P(best.ok,:)) - best.found(best.ok,:), 2, 2) / pxPerCm;
  V.H = best.H;
  V.refined = true;
  V.refineResidualCm = median(best.res);
  fprintf('  refined on %d bug positions: median error %.2f cm (corners only: %.2f cm)\n', ...
    sum(best.ok), median(best.res), median(before));
else
  warning('mouseChaseVideo:notRefined', '%s: bug found in only %d frames; transform from the corners only', ...
    ref, sum(ok));
end
end

function f = fitToBlobs(H, P, blobs, winPx, pxPerCm)
%FITTOBLOBS Match logged bug positions P (cm) to the nearest bug-sized blob
%   (within winPx of where H puts them) and fit a projective transform,
%   dropping outliers (a blob that is something else, the bug half under
%   the mouse). Empty if fewer than 20 matches.
f = [];
pr = transformPointsForward(H, P);
found = nan(size(P));
for k = 1:size(P, 1)
  if isempty(blobs{k}); continue; end
  [d, j] = min(vecnorm(blobs{k} - pr(k,:), 2, 2));
  if d <= winPx; found(k,:) = blobs{k}(j,:); end
end
ok = ~isnan(found(:,1));
if sum(ok) < 20; return; end
Hb = fitgeotform2d(P(ok,:), found(ok,:), 'projective');
for pass = 1:2
  res = vecnorm(transformPointsForward(Hb, P(ok,:)) - found(ok,:), 2, 2);
  keep = find(ok); keep = keep(res <= max(3 * median(res), 2));
  ok = false(size(ok)); ok(keep) = true;
  if sum(ok) < 20; return; end
  Hb = fitgeotform2d(P(ok,:), found(ok,:), 'projective');
end
res = vecnorm(transformPointsForward(Hb, P(ok,:)) - found(ok,:), 2, 2) / pxPerCm;
f = struct('H', Hb, 'P', P, 'ok', ok, 'found', found, 'res', res);
end

function i = frameIndex(V, t)
%FRAMEINDEX Nearest frame to block time(s) t.
i = interp1(V.camTimes, 1:numel(V.camTimes), t + V.blockToCam, 'nearest', 'extrap');
i = min(max(i, 1), numel(V.camTimes));
end

function I = readAt(readers, nFrames, i)
%READAT Frame i of the session, across the main file and lastFrames.
f = find(i <= cumsum(nFrames), 1);
i = i - sum(nFrames(1:f-1));
I = read(readers{f}, i);
I = I(:,:,1);
end
