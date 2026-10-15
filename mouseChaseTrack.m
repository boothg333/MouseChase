function T = mouseChaseTrack(m, folder, varargin)
%MOUSECHASETRACK Track the mouse in a MouseChase session's top camera video,
%   and check every touch contact against it.
%   T = MOUSECHASETRACK(M, FOLDER) (see mouseChaseLoad) goes through the
%   video (every 2nd frame: 30 Hz) and returns
%     T.t          block time of each tracked frame
%     T.xy         body centre (cm, screen coordinates; NaN: not found)
%     T.area       body area (cm2)
%     T.contacts   table, one row per contact down at a tracked frame:
%                  t, id, x, y, w, h (cm, as logged), dBody, dTail (cm from
%                  the body and from the thin dark parts, i.e. the tail),
%                  and type: 'paw' (within 1.5 cm of the body), 'tail' (on
%                  the tail), or 'none' (no mouse there: e.g. the mouse is
%                  on the dark wall, out of view)
%   This reads the whole video (~10 min per 20 min session over the
%   network); the result is cached like mouseChaseVideo's.
%   Options (name, value):
%     'step'      track every step-th frame (2)
%     'frames'    frame range (for testing; not cached)
%     'cacheDir', 'redo'  as in mouseChaseVideo
%     'parallax'  [k cx cy]: the camera sees the mouse's back, a few cm above
%                 the screen, so it appears k (fraction) further out from
%                 (cx, cy) cm than the paws under it ([0.05 -2.6 -2.6], fitted
%                 from the touch-to-mouse offsets of EB056's sessions)
%
%   The mouse: pixels much darker than the background (frame/background <
%   0.55 for the body, < 0.75 for the thin tail; the background is the 80th percentile of frames over the session,
%   so the moving mouse and bug drop out of it). The logged bug is masked
%   out (it is dark too). An opening with a 1 cm disk separates the body
%   (kept: the largest blob) from thin parts: tail, and legs sticking out.

o = struct('step', 2, 'frames', [], 'cacheDir', fullfile(tempdir, 'MouseChase'), 'redo', false, ...
  'parallax', [0.05 -2.6 -2.6]);
for k = 1:2:numel(varargin); o.(varargin{k}) = varargin{k+1}; end
cacheFile = fullfile(o.cacheDir, [m.expRef '_track.mat']);
if isempty(o.frames) && exist(cacheFile, 'file') && ~o.redo
  T = load(cacheFile); T = T.T;
  T.contacts.type = contactType(T.contacts); % (the rule may have changed)
  return
end

V = mouseChaseVideo(m, folder, 'cacheDir', o.cacheDir);
S = mouseChaseMetrics(m, 'nShuffle', 2); % touches in block time
E = S.touches;
B = m.bug;
nAll = numel(V.camTimes);
if isempty(o.frames)
  frames = V.floorFrame:o.step:nAll;
else
  frames = o.frames;
end
tFr = V.camTimes(frames) - V.blockToCam; % block time

% Scale: px per cm at the screen centre
c0 = transformPointsForward(V.H, [0 0; 1 0; 0 1]);
pxPerCm = mean([norm(c0(2,:) - c0(1,:)), norm(c0(3,:) - c0(1,:))]);

% Background: 80th percentile of frames spread over the experiment
v1 = VideoReader(V.files{1});
bgFr = round(linspace(V.floorFrame + 60, nAll - 60, 150));
stack = zeros(v1.Height, v1.Width, numel(bgFr), 'uint8');
for k = 1:numel(bgFr); stack(:,:,k) = V.readFrame(V.camTimes(bgFr(k)) - V.blockToCam); end
bg = double(prctile(stack, 80, 3)); clear stack
screen = bg > 40; % where the (lit) screen is; the bezel is dark anyway
[gx, gy] = meshgrid(1:v1.Width, 1:v1.Height);

seBody = strel('disk', max(2, round(0.5 * pxPerCm))); % 1 cm wide
seGrow = strel('disk', 2);
bugR = (m.params.bugLength / 2 + 0.8) * pxPerCm;
nF = numel(frames);
xy = nan(nF, 2); area = nan(nF, 1);
rows = cell(nF, 1);

% Contacts down at each tracked frame (last event of each id <= t within
% 0.25 s, and not a lift)
[ids, ~, idIdx] = unique(E(:,2));
byId = arrayfun(@(k) find(idIdx == k), 1:numel(ids), 'Uni', 0);

fprintf('%s: tracking %d frames:', m.expRef, nF);
if ~isempty(o.frames) % test: random access
  for i = 1:nF; track(i, V.readFrame(tFr(i))); end
else % the whole session: read each file straight through (fast for mj2)
  cumN = [0 cumsum(V.nFrames)];
  i = 1;
  for f = 1:numel(V.files)
    r = VideoReader(V.files{f});
    first = max(1, frames(1) - cumN(f));
    if first > V.nFrames(f); continue; end
    r.CurrentTime = (first - 1) / r.FrameRate;
    g = cumN(f) + first; % frame number in the session
    while hasFrame(r) && i <= nF
      I = readFrame(r);
      if g == frames(i)
        track(i, I);
        i = i + 1;
      end
      g = g + 1;
    end
  end
end
fprintf('\n');
C = vertcat(rows{:});
if isempty(C); C = zeros(0, 11); end
T = struct('expRef', m.expRef, 't', tFr(:), 'xy', xy, 'area', area, 'pxPerCm', pxPerCm, ...
  'contacts', array2table(C, 'VariableNames', {'t', 'id', 'x', 'y', 'w', 'h', 'dBody', 'dTail', ...
  'dMouse', 'offX', 'offY'}));
T.contacts.type = contactType(T.contacts);
if isempty(o.frames)
  if ~isfolder(o.cacheDir); mkdir(o.cacheDir); end
  save(cacheFile, 'T');
end

  function track(i, I)
  %TRACK Find the mouse in frame I (tracked frame i) and check the contacts.
  if mod(i, max(1, round(nF / 20))) == 0; fprintf(' %.0f%%', 100 * i / nF); end
  F = double(I(:,:,1));
  ratio = F ./ max(bg, 1);
  dark = ratio < 0.55 & screen;
  greyish = ratio < 0.75 & screen; % the tail is thin, so lighter than the body
  rb = find(B(:,1) <= tFr(i), 1, 'last'); % mask the bug
  if ~isempty(rb) && B(rb,6)
    pb = transformPointsForward(V.H, B(rb,2:3));
    nearBug = (gx - pb(1)).^2 + (gy - pb(2)).^2 <= bugR^2;
    dark(nearBug) = false;
    greyish(nearBug) = false;
  end
  dark = bwareaopen(dark, 15); % specks
  if ~any(dark(:)); return; end
  body = imopen(dark, seBody);
  cc = bwconncomp(body);
  nPix = 0;
  if cc.NumObjects > 0; [nPix, big] = max(cellfun(@numel, cc.PixelIdxList)); end
  if nPix >= 2 * pxPerCm^2 % >= 2 cm2: the body (it may be off the screen, on the wall)
    body = false(size(body)); body(cc.PixelIdxList{big}) = true;
    [yy, xx] = find(body);
    xy(i,:) = fromImage(transformPointsInverse(V.H, [mean(xx) mean(yy)]));
    area(i) = nPix / pxPerCm^2;
  else
    body = false(size(body));
  end
  % thin dark parts: tail (and legs sticking out)
  thin = bwareaopen(greyish & ~imdilate(body, seGrow), 15);
  dark = dark | thin;
  % contacts
  down = zeros(0, 5);
  for kk = 1:numel(byId)
    ev = byId{kk};
    j = ev(find(E(ev,7) <= tFr(i), 1, 'last'));
    if ~isempty(j) && E(j,1) ~= 4 && tFr(i) - E(j,7) < 0.25
      down(end+1,:) = [E(j,2) E(j,3:6)]; %#ok<AGROW>
    end
  end
  if isempty(down); return; end
  % the body is seen from above (parallax), the tail lies on the screen
  p = round(transformPointsForward(V.H, toImage(down(:,2:3))));
  pT = round(transformPointsForward(V.H, down(:,2:3)));
  inside = p(:,1) >= 1 & p(:,1) <= v1.Width & p(:,2) >= 1 & p(:,2) <= v1.Height & ...
    pT(:,1) >= 1 & pT(:,1) <= v1.Width & pT(:,2) >= 1 & pT(:,2) <= v1.Height;
  dB = nan(size(p, 1), 1); dT = dB; dD = dB; off = nan(size(p, 1), 2);
  if any(inside)
    li = sub2ind(size(body), p(inside,2), p(inside,1));
    liT = sub2ind(size(body), pT(inside,2), pT(inside,1));
    if any(body(:)); DB = bwdist(body); dB(inside) = DB(li) / pxPerCm; else; dB(inside) = Inf; end
    if any(thin(:)); DT = bwdist(thin); dT(inside) = DT(liT) / pxPerCm; else; dT(inside) = Inf; end
    % nearest dark pixel (any part of the mouse): for checking the touch
    % calibration, as an offset in screen cm
    [DD, nearestIdx] = bwdist(dark);
    dD(inside) = DD(li) / pxPerCm;
    [ny, nx] = ind2sub(size(dark), nearestIdx(li));
    off(inside,:) = fromImage(transformPointsInverse(V.H, [nx ny])) - down(inside,2:3);
  end
  rows{i} = [repmat(tFr(i), size(down, 1), 1), down, dB, dT, dD, off];
  end

  function q = toImage(p)
  %TOIMAGE Screen-level point -> where the mouse's body above it appears.
  q = o.parallax(2:3) + (1 + o.parallax(1)) * (p - o.parallax(2:3));
  end

  function p = fromImage(q)
  p = o.parallax(2:3) + (q - o.parallax(2:3)) / (1 + o.parallax(1));
  end
end

function type = contactType(C)
%CONTACTTYPE Classify contacts from their distances (cm) to the body and tail:
%   paw   within 1.5 cm of the body (legs reach out)
%   tail  on the tail (within 1 cm) and nearer to it than to the body, or,
%         far from the body (>= 4 cm), within 2.2 cm of the visible tail:
%         the very tip is too thin for the camera (checked by eye on the
%         catches of EB056's sessions)
%   none  neither (e.g. the mouse is on the dark wall, out of view)
type = repmat("none", height(C), 1);
type(C.dBody <= 1.5) = "paw";
type((C.dTail <= 1 & C.dTail < C.dBody - 0.3) | (C.dTail <= 2.2 & C.dBody >= 4)) = "tail";
type = categorical(type, ["paw" "tail" "none"]);
end
