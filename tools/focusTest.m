function focusTest(useKeyboardQueue)
%FOCUSTEST Find out what happens to the stimulus window when touch starts.
%   FOCUSTEST opens a full-screen window like srv.expServer, then 4 s apart:
%     1  plain window
%     2  keyboard queue started (as Rigbox does at every experiment start)
%     3  touch queue created and started on the window (MouseChaseDemo)
%     4  asks Windows about the window, then tries to bring it back
%        (restore, topmost, focus) with raiseStimWindow.ps1
%   The step is written on screen and printed with the window's state.
%   FOCUSTEST(false) skips step 2, to see if the keyboard queue matters.
%   Run on POPPY-STIM after switchPsychtoolbox, with srv.expServer closed.

if nargin < 1; useKeyboardQueue = true; end
steps = {'1: plain window', '2: keyboard queue', '3: touch queue', '4: bring back'};
raiseScript = fullfile(fileparts(mfilename('fullpath')), 'raiseStimWindow.ps1');
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
        if ~useKeyboardQueue; continue; end
        KbQueueCreate();
        KbQueueStart();
      case 3
        dev = GetTouchDeviceIndices();
        dev = dev(1);
        TouchQueueCreate(win, dev);
        TouchQueueStart(dev);
        pause(0.5);
        fprintf('%s  window state after touch queue:\n', datestr(now, 'HH:MM:SS'));
        runRaise('-ReportOnly');
      case 4
        runRaise('');
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

  function runRaise(opt)
    % builtin: a mock system.m may shadow the real one on the rig
    [~, out] = builtin('system', sprintf( ...
      'powershell -NoProfile -ExecutionPolicy Bypass -File "%s" -ProcessId %d %s', ...
      raiseScript, feature('getpid'), opt));
    fprintf('%s', out);
  end
end
