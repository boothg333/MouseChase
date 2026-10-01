<#
.SYNOPSIS
  Report on, and bring back to the front, the Psychtoolbox window(s) of a
  given MATLAB process.

.DESCRIPTION
  raiseStimWindow.ps1 -ProcessId <MATLAB pid> [-ReportOnly | -Release]
  Lists the process's top-level windows (title, visible, minimised). The
  Psychtoolbox stimulus window ("PTB Onscreen window ...") is restored, made
  topmost and given focus, unless -ReportOnly is given. -Release makes it
  an ordinary (not topmost) window again.
  Needed because creating a TouchQueue on Windows opens a visible
  'PTB-PsychHID' window that covers the stimulus window.
  -Retries N repeats the raise N times, 0.5 s apart (windows that cover it
  may appear a moment later). -LogFile appends everything printed to a file.
  From MATLAB: builtin('system', sprintf('powershell -NoProfile -ExecutionPolicy Bypass -File "%s" -ProcessId %d', f, feature('getpid')))
#>
param([Parameter(Mandatory = $true)][int]$ProcessId, [switch]$ReportOnly, [switch]$Release,
  [int]$Retries = 1, [string]$LogFile = '', [switch]$HidePsychHid, [switch]$AlsoRaisePsychHid)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class StimWin {
  delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
  [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  public static List<KeyValuePair<IntPtr, string>> Windows(int processId) {
    var found = new List<KeyValuePair<IntPtr, string>>();
    EnumWindows((h, p) => {
      int pid; GetWindowThreadProcessId(h, out pid);
      if (pid == processId) {
        var sb = new StringBuilder(256); GetWindowText(h, sb, 256);
        found.Add(new KeyValuePair<IntPtr, string>(h, sb.ToString()));
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@

function Invoke-Pass {
  $ptb = 0
  foreach ($w in [StimWin]::Windows($ProcessId)) {
    $h = $w.Key; $title = $w.Value
    if ([string]::IsNullOrEmpty($title)) { continue }
    $isStim = $title -like 'PTB Onscreen window*'
    if ($ReportOnly -or $title -like 'PTB*' -or $title -like 'MATLAB*') {
      "window '{0}': visible={1} minimised={2}" -f $title, [StimWin]::IsWindowVisible($h), [StimWin]::IsIconic($h)
    }
    if ($title -like 'PTB-PsychHID*' -and -not $ReportOnly) {
      if ($HidePsychHid) {
        [void][StimWin]::ShowWindow($h, 0)                                  # SW_HIDE
        "  -> PsychHID window hidden; now visible={0}" -f [StimWin]::IsWindowVisible($h)
      } elseif ($AlsoRaisePsychHid) {
        [void][StimWin]::ShowWindow($h, 9)
        [void][StimWin]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0013)
        "  -> PsychHID window raised, foreground={0}" -f [StimWin]::SetForegroundWindow($h)
      }
    }
    if (-not $isStim -or $ReportOnly) { continue }
    $ptb++
    if ($Release) {
      [void][StimWin]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 0x0013) # HWND_NOTOPMOST, no move/size/activate
      '  -> no longer topmost'
    } else {
      [void][StimWin]::ShowWindow($h, 9)                                  # SW_RESTORE
      [void][StimWin]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0013) # HWND_TOPMOST, no move/size/activate
      $fg = [StimWin]::SetForegroundWindow($h)
      "  -> restored, topmost, foreground={0}; now visible={1} minimised={2}" -f $fg, [StimWin]::IsWindowVisible($h), [StimWin]::IsIconic($h)
    }
  }
  if (-not $ReportOnly -and $ptb -eq 0) { 'No PTB stimulus window found for this process.' }
}

$mode = if ($ReportOnly) { 'report' } elseif ($Release) { 'release' } else { 'raise' }
$lines = @("{0}  {1}, MATLAB pid {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $mode, $ProcessId)
for ($i = 1; $i -le [Math]::Max(1, $Retries); $i++) {
  if ($i -gt 1) { Start-Sleep -Milliseconds 500 }
  if ($Retries -gt 1) { $lines += " attempt $i" }
  $lines += Invoke-Pass
}
$lines
if ($LogFile) {
  try { Add-Content -Path $LogFile -Value $lines } catch { }
}
