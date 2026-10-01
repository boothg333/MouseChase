function bandTestRigbox(phaseSecs, windowRect, phasesToRun)
%BANDTESTRIGBOX Like bandTest, but drawing with Rigbox's own renderer.
%   Draws a MouseChase-like scene with vis.init/vis.draw (Rigbox's OpenGL
%   sphere renderer), 8 s per phase, phase number written in the middle:
%     1  floor + rock, drawn once (static, like the idle screen)
%     2  moving bug only, redrawn every frame
%     3  moving bug + rock + floor, where the floor texture is re-uploaded
%        every frame (as MouseChaseDemo's floor currently is)
%     4  as 3 + photodiode square flickering every frame
%     5  as 4 with asynchronous flips (exactly how Rigbox updates)
%     6  as 5 but the floor texture uploaded once (not every frame)
%     7  as 5 + drawnow every frame (Rigbox's loop lets MATLAB repaint)
%     8  as 7 + printing to the command window every frame
%     9  as 8 with the MATLAB window minimised
%   Watch the top of the touchscreen and note in which phases the band
%   appears. Run on POPPY-STIM with srv.expServer closed; any key aborts.
%   BANDTESTRIGBOX(PHASESECS, WINDOWRECT, PHASESTORUN) changes the phase
%   duration, opens a window of that size instead of full screen (for
%   testing), and runs only the listed phases, e.g. bandTestRigbox([], [], 5:9).

if nargin < 1 || isempty(phaseSecs); phaseSecs = 8; end
if nargin < 2; windowRect = []; end
if nargin < 3 || isempty(phasesToRun); phasesToRun = 1:9; end
phases = {'1 static floor + rock', '2 moving bug', '3 bug + rock + re-uploaded floor', ...
  '4 + flickering sync square', '5 + async flips (like Rigbox)', '6 as 5, floor uploaded once', ...
  '7 as 5 + MATLAB repaints', '8 as 7 + command window output', '9 as 8, MATLAB minimised'};
desktop = [];
try desktop = com.mathworks.mde.desk.MLDesktop.getInstance.getMainFrame; catch; end
syncRect = [1180 924 1280 1024]; % rig.stimWindow.SyncBounds on POPPY-STIM
degPerCm = 180 / pi / 100;       % at the 100 cm viewing distance

try
  InitializeMatlabOpenGL;
  win = Screen('OpenWindow', max(Screen('Screens')), 127, windowRect, 32);
  occ = vis.init(win);
  occ.screens = vis.screen([0 0 100], 0, [37.6 30.1], [0 0 1280 1024]);
  if ~isempty(windowRect) % scale the projection into the small test window
    occ.screens.bounds = Screen('Rect', win);
    [occ.screens.w, occ.screens.h] = RectSize(occ.screens.bounds);
  end
  textures = containers.Map('KeyType', 'char', 'ValueType', 'uint32');
  Screen('TextSize', win, 30);

  floorLayer = vis.emptyLayer();
  floorLayer.size = [23.4 18.5];
  floorLayer.isPeriodic = false;
  [floorLayer.rgba, floorLayer.rgbaSize] = vis.rgba(uint8(cat(3, 128, 128, 128)), 1);
  floorLayer.show = true;

  [rock, img] = vis.rectLayer([0; 0], [7; 4.5] * degPerCm, 0);
  rock.textureId = 'square';
  [rock.rgba, rock.rgbaSize] = vis.rgba(1, img);
  rock.maxColour = [0.7 0.7 0.7 1]';
  rock.show = true;

  asyncPending = false;
  frame = 0;
  for k = phasesToRun
    fprintf('%s  phase %s\n', datestr(now, 'HH:MM:SS'), phases{k});
    if k == 9 && ~isempty(desktop); desktop.setState(java.awt.Frame.ICONIFIED); end
    floorLayer.textureId = iff(k == 6, 'floorStatic', '~floor'); % '~' = reload every draw
    tEnd = GetSecs + phaseSecs;
    drawnOnce = false;
    while GetSecs < tEnd && ~KbCheck
      frame = frame + 1;
      if k == 1 && drawnOnce; WaitSecs(0.01); continue; end
      a = frame / 60 * 2 * pi / 4; % bug circling the centre
      [bug, img] = vis.circLayer([10 * cos(a); 6 * sin(a)], [2.4; 0.9] * degPerCm, 0);
      bug.textureId = 'circle';
      [bug.rgba, bug.rgbaSize] = vis.rgba(1, img);
      bug.maxColour = [0 0 0 1]';
      bug.show = true;
      switch k
        case 1, layers = [floorLayer, rock];
        case 2, layers = bug;
        otherwise, layers = [floorLayer, bug, rock];
      end
      if asyncPending; Screen('AsyncFlipEnd', win); asyncPending = false; end
      Screen('BeginOpenGL', win);
      vis.draw(win, occ, layers, textures);
      Screen('EndOpenGL', win);
      if k >= 4; Screen('FillRect', win, 255 * mod(frame, 2), syncRect); end
      DrawFormattedText(win, ['Phase ' phases{k}], 'center', 'center', 0);
      if k >= 5
        Screen('AsyncFlipBegin', win);
        asyncPending = true;
      else
        Screen('Flip', win);
      end
      if k >= 7; drawnow; end
      if k >= 8; fprintf('frame %d\n', frame); end
      drawnOnce = true;
    end
  end
  if ~isempty(desktop); desktop.setState(java.awt.Frame.NORMAL); end
  if asyncPending; Screen('AsyncFlipEnd', win); end
catch ex
  disp(getReport(ex, 'extended', 'hyperlinks', 'off'));
end
if ~isempty(desktop); try desktop.setState(java.awt.Frame.NORMAL); catch; end; end
sca;
end
