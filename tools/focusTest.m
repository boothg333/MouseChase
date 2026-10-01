function focusTest()
%FOCUSTEST Find a way to keep the stimulus window visible once touch starts.
%   Opens a full-screen window like srv.expServer, then (about 6 s each):
%     1  plain window
%     2  keyboard queue started (as Rigbox does)
%     3  touch queue started (the stimulus window gets covered)
%     4  raise the stimulus window only (what MouseChaseDemo does now)
%     5  hide the 'PTB-PsychHID' window, raise the stimulus window
%     6  raise the PsychHID window first, then the stimulus window
%        (what the first focusTest did, when the window came back)
%     7  as 6, but drawing with asynchronous flips, like Rigbox
%   From step 3 on, a blue circle is drawn under every touch. Touch the
%   screen throughout and note, per step: is the grey window visible, and
%   do circles follow the fingers? Window states are printed per step.
%   Run on POPPY-STIM after switchPsychtoolbox, with srv.expServer closed.

steps = {'1: plain window', '2: keyboard queue', '3: touch queue', ...
  '4: raise stimulus window', '5: hide PsychHID window', ...
  '6: raise PsychHID, then stimulus', '7: as 6, async flips'};
raiseScript = fullfile(fileparts(mfilename('fullpath')), 'raiseStimWindow.ps1');
dev = [];
active = containers.Map('KeyType', 'double', 'ValueType', 'any');
try
  % Timing self-tests can fail on this PC (desktop compositor) and would
  % abort before step 1; they're irrelevant here
  Screen('Preference', 'SkipSyncTests', 1);
  win = Screen('OpenWindow', max(Screen('Screens')), 128);
  Screen('TextSize', win, 40);
  for k = 1:numel(steps)
    fprintf('\n%s  === step %s\n', datestr(now, 'HH:MM:SS'), steps{k});
    switch k
      case 2
        KbQueueCreate();
        KbQueueStart();
      case 3
        dev = GetTouchDeviceIndices();
        dev = dev(1);
        TouchQueueCreate(win, dev);
        TouchQueueStart(dev);
        pause(0.5);
        runRaise('-ReportOnly');
      case 4
        runRaise('');
      case 5
        runRaise('-HidePsychHid');
      case {6, 7}
        runRaise('-AlsoRaisePsychHid');
    end
    tEnd = GetSecs + 6;
    while GetSecs < tEnd
      if ~isempty(dev)
        while TouchEventAvail(dev)
          evt = TouchEventGet(dev, win);
          switch evt.Type
            case {2, 3}; active(double(evt.Keycode)) = [evt.X evt.Y];
            case 4; if isKey(active, double(evt.Keycode)); remove(active, double(evt.Keycode)); end
            case 5; remove(active, keys(active));
          end
        end
      end
      ids = keys(active);
      for i = 1:numel(ids)
        xy = active(ids{i});
        Screen('FrameOval', win, [0 0 255], [xy - 50, xy + 50], 6);
      end
      Screen('DrawText', win, ['Step ' steps{k}], 100, 100, 0);
      if k == 7
        Screen('AsyncFlipBegin', win);
        Screen('AsyncFlipEnd', win);
      else
        Screen('Flip', win);
      end
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
