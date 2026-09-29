function report = touchDiagnostics(duration)
%TOUCHDIAGNOSTICS Check what the touch overlay reports on the stimulus PC.
%   REPORT = TOUCHDIAGNOSTICS(DURATION) opens a full-screen window on the
%   stimulus screen and records, for DURATION seconds (default 30):
%     - multi-touch events via the Psychtoolbox TouchQueue, if available
%     - the emulated mouse pointer via GetMouse, for comparison
%   Active touch points are drawn as blue circles labelled with their ID;
%   the mouse pointer is drawn as a red cross while a button is down.
%   Press any key to stop early.
%
%   Run this on POPPY-STIM with srv.expServer closed, while somebody touches
%   the screen with one, then two, then several fingers (or a hand held
%   flat). The report is printed and saved to C:\LocalExpData.
%
%   NB: if MATLAB is driven through Remote Desktop, the window opens in the
%   RDP session rather than on the touchscreen.

if nargin < 1; duration = 30; end

%% System information
report = struct;
report.date = datestr(now, 31);
report.host = getenv('COMPUTERNAME');
report.matlab = version;
report.ptbVersion = PsychtoolboxVersion;
report.ptbRoot = PsychtoolboxRoot;
report.screens = Screen('Screens');
report.screenSizes = zeros(0, 3);
for s = report.screens
  [w, h] = Screen('WindowSize', s);
  report.screenSizes(end+1,:) = [s w h];
end

% HID devices: a multi-touch overlay normally appears as a digitizer
% (usage page 13), possibly alongside a mouse-emulation interface.
try
  report.hid = PsychHID('Devices');
catch ex
  report.hid = [];
  report.hidError = ex.message;
end

report.hasTouchQueue = exist('TouchQueueCreate', 'file') > 0 && ...
  exist('GetTouchDeviceIndices', 'file') > 0;

%% Recording
touchLog = {};
mouseLog = zeros(0, 4); % [time x y anyButtonDown]
maxActive = 0;
dev = [];
win = [];
try
  Screen('Preference', 'SkipSyncTests', 1);
  Screen('Preference', 'VisualDebugLevel', 1);
  win = Screen('OpenWindow', max(report.screens), 128);
  [winW, winH] = Screen('WindowSize', win);
  report.windowSize = [winW winH];
  Screen('TextSize', win, 24);

  if report.hasTouchQueue
    try
      [touchIdx, touchNames, touchInfo] = GetTouchDeviceIndices();
      report.touchDevices = touchIdx;
      report.touchNames = touchNames;
      report.touchInfo = touchInfo;
      if ~isempty(touchIdx)
        dev = touchIdx(1);
        TouchQueueCreate(win, dev);
        TouchQueueStart(dev);
      end
    catch ex
      report.touchError = ex.message;
      dev = [];
    end
  end

  active = containers.Map('KeyType', 'double', 'ValueType', 'any');
  KbReleaseWait;
  tStart = GetSecs;
  while GetSecs - tStart < duration && ~KbCheck
    if ~isempty(dev)
      while TouchEventAvail(dev)
        evt = TouchEventGet(dev, win);
        evt.tRel = GetSecs - tStart;
        touchLog{end+1} = evt; %#ok<AGROW>
        id = double(evt.Keycode);
        switch evt.Type
          case {2, 3} % touch begin / move
            active(id) = [evt.X evt.Y];
          case 4 % touch end
            if isKey(active, id); remove(active, id); end
          case 5 % touch sequence compromised: all touches invalid
            active = containers.Map('KeyType', 'double', 'ValueType', 'any');
        end
        maxActive = max(maxActive, active.Count);
      end
    end

    [mx, my, buttons] = GetMouse(win);
    mouseLog(end+1,:) = [GetSecs - tStart, mx, my, any(buttons)]; %#ok<AGROW>

    ids = keys(active);
    for k = 1:numel(ids)
      xy = active(ids{k});
      Screen('FrameOval', win, [0 0 255], [xy - 40, xy + 40], 4);
      Screen('DrawText', win, sprintf('%d', ids{k}), xy(1) + 45, xy(2) - 12, [0 0 255]);
    end
    if any(buttons)
      Screen('DrawLines', win, [mx-30 mx+30 mx mx; my my my-30 my+30], 4, [255 0 0]);
    end
    if isempty(dev)
      touchStatus = 'no TouchQueue device: mouse pointer only';
    else
      touchStatus = sprintf('touches now: %d   max so far: %d', active.Count, maxActive);
    end
    Screen('DrawText', win, sprintf('%s   |   %.0f s left', touchStatus, ...
      duration - (GetSecs - tStart)), 20, 20, 0);
    Screen('Flip', win);
  end
catch ex
  report.runError = getReport(ex, 'extended', 'hyperlinks', 'off');
end

if ~isempty(dev)
  try TouchQueueStop(dev); TouchQueueRelease(dev); catch; end
end
if ~isempty(win); sca; end

%% Summary
report.touchLog = touchLog;
report.mouseLog = mouseLog;
report.maxSimultaneousTouches = maxActive;

fprintf('\n===== Touch diagnostics: %s (%s) =====\n', report.host, report.date);
fprintf('Psychtoolbox %s\n', report.ptbVersion);
fprintf('Screens: %s\n', mat2str(report.screenSizes));
if isstruct(report.hid)
  fprintf('HID devices:\n');
  for k = 1:numel(report.hid)
    d = report.hid(k);
    fprintf('  [%2d] usagePage %3d usage %3d  %s / %s\n', k, ...
      getFieldOr(d, 'usagePageValue', -1), getFieldOr(d, 'usageValue', -1), ...
      getFieldOr(d, 'manufacturer', ''), getFieldOr(d, 'product', ''));
  end
end
fprintf('TouchQueue functions available: %d\n', report.hasTouchQueue);
if isfield(report, 'touchNames'); fprintf('Touch devices: %s\n', strjoin(cellstr(report.touchNames), ', ')); end
if isfield(report, 'touchError'); fprintf('Touch error: %s\n', report.touchError); end
fprintf('Touch events recorded: %d, max simultaneous touches: %d\n', numel(touchLog), maxActive);
if ~isempty(touchLog); fprintf('Touch event fields: %s\n', strjoin(fieldnames(touchLog{1})', ', ')); end
fprintf('Mouse samples: %d, samples with button down: %d\n', size(mouseLog, 1), sum(mouseLog(:,4)));
if isfield(report, 'runError'); fprintf('Run error:\n%s\n', report.runError); end

outDir = 'C:\LocalExpData';
if ~exist(outDir, 'dir'); mkdir(outDir); end
outFile = fullfile(outDir, sprintf('touchDiag_%s_%s.mat', report.host, datestr(now, 'yyyy-mm-dd_HHMMSS')));
save(outFile, 'report');
fprintf('Saved to %s\n', outFile);
end

function v = getFieldOr(s, name, default)
if isfield(s, name) && ~isempty(s.(name)); v = s.(name); else; v = default; end
end
