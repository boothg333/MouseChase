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
%   positions fall on the dark bug in the video.

o = struct('cacheDir', fullfile(tempdir, 'MouseChase'), 'redo', false);
for k = 1:2:numel(varargin); o.(varargin{k}) = varargin{k+1}; end
ref = m.expRef;
files = {fullfile(folder, [ref '_topCam.mj2']), fullfile(folder, [ref '_topCam_lastFrames.mj2'])};
files = files(cellfun(@(f) exist(f, 'file') == 2, files));
assert(~isempty(files), 'mouseChaseVideo:noVideo', 'No top camera video for %s in %s', ref, folder);
cacheFile = fullfile(o.cacheDir, [ref '_video.mat']);

if exist(cacheFile, 'file') && ~o.redo
  V = load(cacheFile); V = V.V;
else
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
