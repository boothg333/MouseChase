function focusTest()
%FOCUSTEST Find which start-up step pushes the stimulus window behind MATLAB.
%   Opens a full-screen window like srv.expServer, then performs, 4 s apart,
%   the steps an experiment start involves. The current step is written on
%   screen; note after which step MATLAB comes to the front.
%     1  plain window
%     2  keyboard queue started (as Rigbox does at every experiment start)
%     3  dat.paths read (as MouseChaseDemo does to find hardware.mat)
%     4  touch queue created and started on the window (MouseChaseDemo)
%   Run on POPPY-STIM after switchPsychtoolbox, with srv.expServer closed.

steps = {'1: plain window', '2: keyboard queue', '3: dat.paths', '4: touch queue'};
dev = [];
try
  % Timing self-tests can fail on this PC (desktop compositor) and would
  % abort before step 1; they're irrelevant for a focus test
  Screen('Preference', 'SkipSyncTests', 1);
  win = Screen('OpenWindow', max(Screen('Screens')), 128);
  Screen('TextSize', win, 40);
  for k = 1:numel(steps)
    switch k
      case 2
        KbQueueCreate();
        KbQueueStart();
      case 3
        dat.paths;
      case 4
        dev = GetTouchDeviceIndices();
        dev = dev(1);
        TouchQueueCreate(win, dev);
        TouchQueueStart(dev);
    end
    fprintf('%s  step %s done\n', datestr(now, 'HH:MM:SS'), steps{k});
    tEnd = GetSecs + 4;
    while GetSecs < tEnd
      Screen('DrawText', win, ['Step ' steps{k}], 100, 100, 0);
      Screen('Flip', win);
    end
  end
catch ex
  disp(getReport(ex, 'extended', 'hyperlinks', 'off'));
end
if ~isempty(dev)
  try TouchQueueStop(dev); TouchQueueRelease(dev); catch; end
end
try KbQueueRelease(); catch; end
sca;
end
