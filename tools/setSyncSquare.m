function setSyncSquare(squareCm, boxCm, apply, hwFile)
%SETSYNCSQUARE Resize the photodiode sync square and the area it blocks.
%   SETSYNCSQUARE(SQUARECM, BOXCM) shows what would change in this rig's
%   hardware.mat; nothing is written. SETSYNCSQUARE(SQUARECM, BOXCM, true)
%   backs up hardware.mat and writes:
%     stimWindow.SyncBounds  a SQUARECM x SQUARECM square in the bottom-right
%                            corner (where the photodiode sits)
%     touchScreen.blockedPx  the BOXCM ([w h], or one value for a square)
%                            footprint of the box over it, also bottom-right;
%                            MouseChase keeps the bug out of this area
%   Make the square a bit smaller than the box's opening, and BOXCM the
%   box's outer size on the screen. Sizes use touchScreen.dimsCm/pxSize
%   (run configureTouchScreenRig first). Restart srv.expServer afterwards.
%   HWFILE (4th argument) overrides which hardware.mat is edited.

if nargin < 3; apply = false; end
if nargin < 4 || isempty(hwFile)
  hwFile = fullfile(getOr(dat.paths, 'rigConfig'), 'hardware.mat');
end
if isscalar(boxCm); boxCm = [boxCm boxCm]; end
fprintf('Rig config: %s\n', hwFile);
rig = load(hwFile);
assert(isfield(rig, 'touchScreen'), 'setSyncSquare:noGeometry', ...
  'No touchScreen field in hardware.mat: run configureTouchScreenRig first.');
ts = rig.touchScreen;
pxPerCm = ts.pxSize ./ ts.dimsCm;
W = ts.pxSize(1); H = ts.pxSize(2);

sq = round(squareCm * pxPerCm);
syncBounds = [W - sq(1), H - sq(2), W, H];
box = round(boxCm .* pxPerCm);
blockedPx = [W - box(1), H - box(2), W, H];

fprintf('Sync square: %s -> %s  (%.2f x %.2f cm)\n', mat2str(rig.stimWindow.SyncBounds), ...
  mat2str(syncBounds), sq ./ pxPerCm);
fprintf('Blocked area (box): %s -> %s  (%.2f x %.2f cm)\n', mat2str(ts.blockedPx), ...
  mat2str(blockedPx), box ./ pxPerCm);
if any(sq > box)
  warning('The sync square is larger than the box footprint.');
end
if ~apply
  fprintf('\nDry run: nothing written. Call setSyncSquare(%g, %s, true) to apply.\n', ...
    squareCm, mat2str(boxCm));
  return
end
backup = fullfile(fileparts(hwFile), ...
  sprintf('hardware_%s_beforeSyncSquare.mat', datestr(now, 'yyyy-mm-dd_HHMMSS')));
copyfile(hwFile, backup);
fprintf('Backed up to %s\n', backup);
rig.stimWindow.SyncBounds = syncBounds;
rig.touchScreen.blockedPx = blockedPx;
save(hwFile, '-struct', 'rig');
fprintf('Written. Restart srv.expServer to pick up the change.\n');
end
