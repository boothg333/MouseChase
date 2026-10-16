function figs = plotMouseChaseCatches(source, varargin)
%PLOTMOUSECHASECATCHES Video frames of a few catches, with the logged bug
%   and touches drawn on top.
%   PLOTMOUSECHASECATCHES(EXPREF or FILE) shows, for a few catches spread
%   over the session, the top camera frames in the seconds before each
%   catch: the bug's logged position (orange ring) and the contacts on the
%   screen (blue dots). Needs the session's _topCam.mj2 (see
%   mouseChaseVideo; the first call per session aligns the video, which
%   takes a minute or two). PLOTMOUSECHASECATCHES(M, FOLDER) takes a loaded
%   session (mouseChaseLoad).
%   Options (name, value):
%     'catches'   which catches (default: 5 spread over the session)
%     'offsets'   s relative to the catch (default [-2 -1 -0.5 -0.2 0])
%     'clips'     true: also write an MP4 per catch (-3 to +1 s, slowed
%                 down 2x) into saveDir (default false)
%     'saveDir'   save the figure (and clips) here
%     'root'      subjects folder for finding EXPREF without Rigbox
%     'rewardPos' spout position, cm ([-20 3], measured from the video)
%   Frames are shown in screen centimetres, oriented like the other plots.

o = struct('catches', [], 'offsets', [-2 -1 -0.5 -0.2 0], 'clips', false, 'saveDir', '', ...
  'root', '', 'rewardPos', [-20 3]);
args = varargin;
if isstruct(source) % (m, folder, ...)
  m = source; folder = args{1}; args = args(2:end);
else
  [m, folder] = mouseChaseLoad(source, '');
end
for k = 1:2:numel(args); o.(args{k}) = args{k+1}; end
if isempty(o.saveDir) && o.clips; o.saveDir = pwd; end

S = mouseChaseMetrics(m, 'nShuffle', 2); % for the touches in block time
V = mouseChaseVideo(m, folder);
c = mouseChaseStyle();
K = m.catchLog;
if isempty(o.catches)
  o.catches = unique(round(linspace(1, size(K, 1), min(5, size(K, 1)))));
end
B = m.bug;
E = S.touches;

% Frames are warped to screen centimetres, oriented as in the arena plot
% (x right, y up), with a margin to show the walls and the spout
half = m.geometry.dimsCm / 2;
lim = [-half(1) - 3, half(1) + 3; -half(2) - 3, half(2) + 3];
lim(1,1) = min(lim(1,1), o.rewardPos(1) - 2); lim(1,2) = max(lim(1,2), o.rewardPos(1) + 2);
lim(2,1) = min(lim(2,1), o.rewardPos(2) - 2); lim(2,2) = max(lim(2,2), o.rewardPos(2) + 2);
res = 0.1; % cm per pixel
W.ref = imref2d(round(fliplr(diff(lim, 1, 2)') / res), lim(1,:), lim(2,:));
W.tform = invert(V.H); % video px -> cm
W.half = half;
W.rewardPos = o.rewardPos;
nC = numel(o.catches); nO = numel(o.offsets);
aspect = diff(lim(1,:)) / diff(lim(2,:));
fig = figure('Name', [m.expRef ': catches'], 'Color', 'w', ...
  'Position', [60 40 220 * aspect * nO 230 * nC]);
tl = tiledlayout(fig, nC, nO, 'TileSpacing', 'tight', 'Padding', 'compact');
title(tl, {sprintf('%s: frames before catches (orange: logged bug, blue: touches, + spout)', m.expRef), ...
  'At 0 s the bug may still be on screen: the display takes a frame or two to update'}, ...
  'Interpreter', 'none');
for i = 1:nC
  k = o.catches(i);
  for j = 1:nO
    t = K(k,1) + o.offsets(j);
    ax = nexttile(tl);
    drawFrame(ax, V, W, t, B, E, m, c);
    if j == 1; ylabel(ax, sprintf('catch %d (%.1f min)', k, (K(k,1) - S.tStart) / 60)); end
    if i == 1; title(ax, sprintf('%+.1f s', o.offsets(j))); end
  end
end
figs = fig;
if ~isempty(o.saveDir)
  if ~isfolder(o.saveDir); mkdir(o.saveDir); end
  exportgraphics(fig, fullfile(o.saveDir, [m.expRef '_catches.png']), 'Resolution', 150);
end

%% Clips
if o.clips
  cf = figure('Color', 'k', 'Position', [100 100 round(560 * aspect) 600], 'Visible', 'off');
  ax = axes(cf, 'Position', [0 0 1 0.93]);
  for k = o.catches
    file = fullfile(o.saveDir, sprintf('%s_catch%02d.mp4', m.expRef, k));
    w = VideoWriter(file, 'MPEG-4');
    w.FrameRate = 30; % camera 60 Hz, every frame: 2x slower than real time
    open(w);
    fr = V.frameIndex(K(k,1) - 3):V.frameIndex(K(k,1) + 1);
    for f = fr
      t = V.camTimes(f) - V.blockToCam;
      drawFrame(ax, V, W, t, B, E, m, c);
      title(ax, sprintf('catch %d   %+.2f s', k, t - K(k,1)), 'Color', 'w');
      writeVideo(w, getframe(cf));
    end
    close(w);
    fprintf('wrote %s\n', file);
  end
  close(cf);
end
end

function drawFrame(ax, V, W, t, B, E, m, c)
%DRAWFRAME The video frame at block time t in screen cm (x right, y up),
%   with the logged bug and the touches on top.
cla(ax);
J = imwarp(V.readFrame(t), W.tform, 'OutputView', W.ref, 'FillValues', 0);
imagesc(ax, W.ref.XWorldLimits, W.ref.YWorldLimits, J); % row 1 = lowest y
colormap(ax, gray(256)); clim(ax, [0 255]);
hold(ax, 'on');
set(ax, 'YDir', 'normal', 'XTick', [], 'YTick', [], 'XLim', W.ref.XWorldLimits, ...
  'YLim', W.ref.YWorldLimits, 'DataAspectRatio', [1 1 1]);
rectangle(ax, 'Position', [-W.half, 2 * W.half], 'EdgeColor', [1 1 1 0.3]);
plot(ax, W.rewardPos(1), W.rewardPos(2), '+', 'Color', c.catch, 'MarkerSize', 8, 'LineWidth', 1.5);
% bug: last logged position at or before t, if alive
r = find(B(:,1) <= t, 1, 'last');
if ~isempty(r) && B(r,6)
  a = linspace(0, 2 * pi, 40)';
  ring = B(r,2:3) + (m.params.bugLength / 2 + 1) * [cos(a) sin(a)]; % cm, around the bug
  plot(ax, ring(:,1), ring(:,2), 'Color', c.bug, 'LineWidth', 1.5);
end
% contacts down at t: the last event of each contact (within 0.25 s) is not a lift
recent = E(E(:,7) <= t & E(:,7) > t - 0.25,:);
if ~isempty(recent)
  [~, last] = unique(recent(:,2), 'last');
  down = recent(last, :);
  down = down(down(:,1) ~= 4, :);
  if ~isempty(down)
    plot(ax, down(:,3), down(:,4), '.', 'MarkerSize', 16, 'Color', c.mouse);
  end
end
end
