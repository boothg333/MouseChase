function configureTouchScreenRig(apply, dimsCm, distanceCm, hwFile)
%CONFIGURETOUCHSCREENRIG Set up this rig's hardware.mat for MouseChaseTouch.
%   CONFIGURETOUCHSCREENRIG() shows what would change; nothing is written.
%   CONFIGURETOUCHSCREENRIG(true) backs up hardware.mat and writes:
%     rig.screens      one flat screen straight ahead of the viewer, filling
%                      the stimulus window (replaces the three virtual
%                      screens), so Signals draws on the touchscreen
%     rig.touchScreen  the same geometry for MouseChaseTouch, which converts
%                      touch pixels <-> cm <-> visual degrees with it:
%                        pxSize      [w h] of the stimulus window
%                        dimsCm      [w h] of the visible image, in cm
%                        distanceCm  virtual viewing distance (see below)
%                        blockedPx   areas the mouse can't reach, one row
%                                    [left top right bottom] per area; set
%                                    to the sync square (covered by a box)
%
%   CONFIGURETOUCHSCREENRIG(APPLY, DIMSCM, DISTANCECM) sets the screen size
%   (default [37.6 30.1], the iiyama ProLite T1932MSC's viewable area: please
%   measure) and viewing distance (default 100 cm). The mouse stands on the
%   screen, so the distance is only a scale for Signals' degrees; 100 cm
%   keeps shapes undistorted to within ~3% at the edges.
%
%   Run on the stimulus PC (it edits that rig's config), with Rigbox on the
%   path. NB this changes where any Signals stimulus appears on this rig.
%   HWFILE (4th argument) overrides which hardware.mat is edited.

if nargin < 1; apply = false; end
if nargin < 2 || isempty(dimsCm); dimsCm = [37.6 30.1]; end
if nargin < 3 || isempty(distanceCm); distanceCm = 100; end
if nargin < 4 || isempty(hwFile)
  hwFile = fullfile(getOr(dat.paths, 'rigConfig'), 'hardware.mat');
end
fprintf('Rig config: %s\n', hwFile);
rig = load(hwFile);

[pxW, pxH] = RectSize(rig.stimWindow.Bounds);
if isfield(rig, 'screens')
  fprintf('Current screens (%d):\n', numel(rig.screens));
  for k = 1:numel(rig.screens)
    fprintf('  bounds %s\n', mat2str(rig.screens(k).bounds));
  end
end
aspectPx = pxW / pxH;
aspectCm = dimsCm(1) / dimsCm(2);
if abs(aspectPx / aspectCm - 1) > 0.02
  warning('Screen size %s cm has aspect %.3f but the window %dx%d px has %.3f: pixels would not be square.', ...
    mat2str(dimsCm), aspectCm, pxW, pxH, aspectPx);
end

screens = vis.screen([0 0 distanceCm], 0, dimsCm, [0 0 pxW pxH]);
touchScreen = struct('pxSize', [pxW pxH], 'dimsCm', dimsCm, ...
  'distanceCm', distanceCm, 'blockedPx', zeros(0, 4));
if ~isempty(rig.stimWindow.SyncBounds)
  touchScreen.blockedPx = rig.stimWindow.SyncBounds;
end

fprintf('New screens (1): bounds %s, %s cm at %g cm straight ahead\n', ...
  mat2str(screens.bounds), mat2str(dimsCm), distanceCm);
fprintf('New touchScreen: pxSize %s, dimsCm %s, distanceCm %g, blockedPx %s\n', ...
  mat2str(touchScreen.pxSize), mat2str(dimsCm), distanceCm, mat2str(touchScreen.blockedPx));

if ~apply
  fprintf('\nDry run: nothing written. Call configureTouchScreenRig(true) to apply.\n');
  return
end

backup = fullfile(fileparts(hwFile), ...
  sprintf('hardware_%s_beforeMouseChase.mat', datestr(now, 'yyyy-mm-dd_HHMMSS')));
copyfile(hwFile, backup);
fprintf('Backed up to %s\n', backup);
rig.screens = screens;
rig.touchScreen = touchScreen;
save(hwFile, '-struct', 'rig');
fprintf('Written. Restart srv.expServer to pick up the change.\n');
end
