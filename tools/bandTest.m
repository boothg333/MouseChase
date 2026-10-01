function bandTest()
%BANDTEST Find what makes the band at the top of the touchscreen flicker.
%   Shows, 8 s each, the ingredients of a MouseChase session one at a time
%   on a grey screen, with the phase number written in the middle:
%     1  static black square bottom-right (like the idle server screen)
%     2  square flickering black/white every frame (photodiode sync square
%        during an experiment)
%     3  no square; a small dark dot moving around, screen redrawn every
%        frame (like the bug)
%     4  flickering square + moving dot (like a session)
%     5  as 4, with asynchronous flips (the way Rigbox updates the screen)
%     6  square flickering every other frame pair (slower, 15 Hz)
%   Watch the top of the touchscreen and note in which phases the band
%   appears. Run on POPPY-STIM with srv.expServer closed. Any key aborts.

phases = {'1 static square', '2 flickering square', '3 moving dot', ...
  '4 flicker + dot', '5 flicker + dot, async flips', '6 slow flicker'};
syncRect = [1180 924 1280 1024]; % rig.stimWindow.SyncBounds on POPPY-STIM
try
  win = Screen('OpenWindow', max(Screen('Screens')), 127);
  [w, h] = Screen('WindowSize', win);
  Screen('TextSize', win, 30);
  frame = 0;
  for k = 1:numel(phases)
    fprintf('%s  phase %s\n', datestr(now, 'HH:MM:SS'), phases{k});
    tEnd = GetSecs + 8;
    while GetSecs < tEnd && ~KbCheck
      frame = frame + 1;
      Screen('FillRect', win, 127);
      if any(k == [3 4 5]) % dot circling the centre, like a moving bug
        a = frame / 60 * 2 * pi / 4;
        xy = [w/2 + 300*cos(a), h/2 + 250*sin(a)];
        Screen('FillOval', win, 0, [xy - 15, xy + 15]);
      end
      switch k
        case 1, sq = 0;
        case {2, 4, 5}, sq = 255 * mod(frame, 2);
        case 6, sq = 255 * mod(floor(frame / 2), 2);
        otherwise, sq = [];
      end
      if ~isempty(sq); Screen('FillRect', win, sq, syncRect); end
      DrawFormattedText(win, ['Phase ' phases{k}], 'center', 'center', 0);
      if k == 5
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
sca;
end
