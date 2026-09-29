function report = touchRawHidTest(duration, vendorId)
%TOUCHRAWHIDTEST Try to read raw HID reports from the touch overlay.
%   REPORT = TOUCHRAWHIDTEST(DURATION, VENDORID) opens a full-screen window
%   and, for DURATION seconds (default 40), polls every HID collection of the
%   device with the given USB vendor ID (default 8183 = 0x1FF7, the overlay
%   on POPPY-STIM) for raw input reports using PsychHID('GetReport'). The
%   number of reports received per collection is shown live.
%
%   Suggested touch protocol while it runs (watch the on-screen timer):
%      0-10 s  one finger: tap, then drag slowly across the screen
%     10-20 s  two fingers held apart, dragged together
%     20-30 s  three or four fingers / a flat hand, held still, then moved
%     30-40 s  nothing
%
%   Also reports Windows' own view of the touchscreen (GetSystemMetrics) and
%   the Psychtoolbox version in C:\toolbox\Psychtoolbox, if present. The
%   report is printed and saved to C:\LocalExpData. Run with srv.expServer
%   closed.

if nargin < 1; duration = 40; end
if nargin < 2; vendorId = 8183; end

report = struct;
report.date = datestr(now, 31);
report.host = getenv('COMPUTERNAME');
report.ptbVersion = PsychtoolboxVersion;
report.ptbRoot = PsychtoolboxRoot;
report.altPtbVersion = readPtbVersion('C:\toolbox\Psychtoolbox');
report.windowsTouch = windowsTouchMetrics();

devices = PsychHID('Devices');
idx = find([devices.vendorID] == vendorId);
report.devices = devices(idx);
report.deviceIdx = idx;
nDev = numel(idx);
counts = zeros(1, nDev);
firstError = repmat({''}, 1, nDev);
reports = {}; % rows of {time, devIdx, uint8 bytes}

win = [];
try
  Screen('Preference', 'SkipSyncTests', 1);
  Screen('Preference', 'VisualDebugLevel', 1);
  win = Screen('OpenWindow', max(Screen('Screens')), 128);
  Screen('TextSize', win, 24);
  KbReleaseWait;
  tStart = GetSecs;
  while GetSecs - tStart < duration && ~KbCheck
    for k = 1:nDev
      for n = 1:50 % drain up to 50 queued reports per collection per frame
        try
          [r, err] = PsychHID('GetReport', idx(k), 1, 0, 64);
        catch ex
          r = [];
          err = struct('n', -1, 'name', ex.identifier, 'description', ex.message);
        end
        if isstruct(err) && isfield(err, 'n') && err.n ~= 0 && isempty(firstError{k})
          firstError{k} = sprintf('%d %s: %s', err.n, err.name, err.description);
        end
        if isempty(r); break; end
        counts(k) = counts(k) + 1;
        reports(end+1,:) = {GetSecs - tStart, idx(k), uint8(r)}; %#ok<AGROW>
      end
    end
    elapsed = GetSecs - tStart;
    Screen('DrawText', win, sprintf('%.0f s   %s', elapsed, protocolStep(elapsed)), 20, 20, 0);
    for k = 1:nDev
      d = devices(idx(k));
      Screen('DrawText', win, sprintf('HID %d (page %d, usage %d): %d reports', ...
        idx(k), d.usagePageValue, d.usageValue, counts(k)), 20, 60 + 30*k, 0);
    end
    Screen('Flip', win);
  end
catch ex
  report.runError = getReport(ex, 'extended', 'hyperlinks', 'off');
end
for k = 1:nDev
  try PsychHID('ReceiveReportsStop', idx(k)); catch; end
end
if ~isempty(win); sca; end

report.counts = counts;
report.firstError = firstError;
report.reports = reports;

%% Summary
fprintf('\n===== Raw HID touch test: %s (%s) =====\n', report.host, report.date);
fprintf('Psychtoolbox in use: %s (%s)\n', report.ptbVersion, report.ptbRoot);
fprintf('Psychtoolbox in C:\\toolbox\\Psychtoolbox: %s\n', report.altPtbVersion);
fprintf('Windows touch: %s\n', report.windowsTouch);
for k = 1:nDev
  d = devices(idx(k));
  fprintf('HID %d page %d usage %d: %d reports', idx(k), d.usagePageValue, d.usageValue, counts(k));
  if ~isempty(firstError{k}); fprintf('  | first error: %s', firstError{k}); end
  fprintf('\n');
  if isempty(reports); continue; end
  mine = reports(cell2mat(reports(:,2)) == idx(k), 3);
  if ~isempty(mine)
    lens = cellfun(@numel, mine);
    fprintf('   report lengths: %s\n', mat2str(unique(lens)'));
    for m = round(linspace(1, numel(mine), min(5, numel(mine))))
      fprintf('   e.g. %s\n', sprintf('%02X ', mine{m}));
    end
  end
end
if isfield(report, 'runError'); fprintf('Run error:\n%s\n', report.runError); end

outDir = 'C:\LocalExpData';
if ~exist(outDir, 'dir'); mkdir(outDir); end
outFile = fullfile(outDir, sprintf('touchRawHid_%s_%s.mat', report.host, datestr(now, 'yyyy-mm-dd_HHMMSS')));
save(outFile, 'report');
fprintf('Saved to %s\n', outFile);
end

function s = protocolStep(t)
if t < 10;     s = 'ONE finger: tap, then drag slowly';
elseif t < 20; s = 'TWO fingers apart, drag together';
elseif t < 30; s = 'THREE+ fingers / flat hand: hold still, then move';
else;          s = 'do NOT touch';
end
end

function v = readPtbVersion(root)
v = 'not found';
f = fullfile(root, 'Contents.m');
if exist(f, 'file')
  txt = fileread(f);
  tok = regexp(txt, 'Version\s+([\d\.]+)', 'tokens', 'once');
  if ~isempty(tok); v = tok{1}; else; v = 'present, version unknown'; end
end
end

function s = windowsTouchMetrics()
% SM_DIGITIZER (94) flags and SM_MAXIMUMTOUCHES (95) from user32.
ps1 = [tempname '.ps1'];
fid = fopen(ps1, 'w');
fprintf(fid, '%s\n', ...
  'Add-Type -Namespace W -Name U -MemberDefinition ''[DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);''', ...
  'Write-Output ("digitizerFlags=0x{0:X2} maxTouches={1}" -f [W.U]::GetSystemMetrics(94), [W.U]::GetSystemMetrics(95))');
fclose(fid);
% builtin: a mock system.m (Rigbox test fixtures) may shadow the real one
[status, out] = builtin('system', sprintf('powershell -NoProfile -ExecutionPolicy Bypass -File "%s"', ps1));
delete(ps1);
if status == 0; s = strtrim(out); else; s = ['query failed: ' strtrim(out)]; end
end
