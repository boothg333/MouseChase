<#
.SYNOPSIS
  Turn off Windows touch gestures and touch pop-ups on the rig PC, so paws
  on the touchscreen can't open Windows functions during an experiment.

.DESCRIPTION
  Run in an elevated PowerShell (Run as administrator), logged in as the
  account that runs the experiments (the HKCU settings are per user):

    powershell -ExecutionPolicy Bypass -File windowsTouchLockdown.ps1          # apply
    powershell -ExecutionPolicy Bypass -File windowsTouchLockdown.ps1 -Undo    # restore

  Previous values are saved to windowsTouchLockdown_backup_<PC>.json next to
  this script, and -Undo restores them exactly (including removing values
  that did not exist before). Sign out and back in (or restart) afterwards.

  Touches still reach the experiment window: this only stops Windows from
  interpreting them as gestures.
#>
param([switch]$Undo)

$ErrorActionPreference = 'Stop'
$backupFile = Join-Path $PSScriptRoot "windowsTouchLockdown_backup_$env:COMPUTERNAME.json"

$settings = @(
  @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EdgeUI'; Name = 'AllowEdgeSwipe'; Value = 0;
     Desc = 'Edge swipes (notification centre, task view, widgets)' },
  @{ Path = 'HKCU:\Software\Microsoft\Wisp\Touch'; Name = 'TouchMode_hold'; Value = 0;
     Desc = 'Press and hold for right-click' },
  @{ Path = 'HKCU:\Control Panel\Cursors'; Name = 'ContactVisualization'; Value = 0;
     Desc = 'Touch feedback circles' },
  @{ Path = 'HKCU:\Control Panel\Cursors'; Name = 'GestureVisualization'; Value = 0;
     Desc = 'Gesture feedback' },
  @{ Path = 'HKCU:\Software\Microsoft\TabletTip\1.7'; Name = 'EnableDesktopModeAutoInvoke'; Value = 0;
     Desc = 'Touch keyboard popping up' },
  @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace'; Name = 'AllowWindowsInkWorkspace'; Value = 0;
     Desc = 'Windows Ink Workspace' }
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Please run this from an elevated PowerShell (Run as administrator).' }

function Get-Current($s) {
  if (-not (Test-Path $s.Path)) { return $null }
  $item = Get-ItemProperty -Path $s.Path -Name $s.Name -ErrorAction SilentlyContinue
  if ($null -eq $item) { return $null }
  return $item.($s.Name)
}

if ($Undo) {
  if (-not (Test-Path $backupFile)) { throw "No backup found at $backupFile" }
  $backup = Get-Content -Raw $backupFile | ConvertFrom-Json
  foreach ($b in $backup) {
    if ($null -eq $b.Previous) {
      Remove-ItemProperty -Path $b.Path -Name $b.Name -ErrorAction SilentlyContinue
      Write-Output ("Removed   {0}  ({1})" -f $b.Name, $b.Desc)
    } else {
      New-ItemProperty -Path $b.Path -Name $b.Name -Value $b.Previous -PropertyType DWord -Force | Out-Null
      Write-Output ("Restored  {0} = {1}  ({2})" -f $b.Name, $b.Previous, $b.Desc)
    }
  }
  Write-Output 'Done. Sign out and back in for all changes to take effect.'
  return
}

if (Test-Path $backupFile) {
  Write-Output "Backup $backupFile already exists (lockdown applied before); not overwriting it."
} else {
  $backup = foreach ($s in $settings) {
    [pscustomobject]@{ Path = $s.Path; Name = $s.Name; Desc = $s.Desc; Previous = (Get-Current $s) }
  }
  $backup | ConvertTo-Json | Set-Content -Encoding UTF8 $backupFile
  Write-Output "Saved previous values to $backupFile"
}

foreach ($s in $settings) {
  if (-not (Test-Path $s.Path)) { New-Item -Path $s.Path -Force | Out-Null }
  New-ItemProperty -Path $s.Path -Name $s.Name -Value $s.Value -PropertyType DWord -Force | Out-Null
  Write-Output ("Set       {0} = {1}  ({2})" -f $s.Name, $s.Value, $s.Desc)
}

Write-Output ''
Write-Output 'Done. Sign out and back in (or restart) for all changes to take effect.'
Write-Output 'Please also check by hand, as these have no reliable registry setting:'
Write-Output '  - Settings > Bluetooth & devices > Touch (Windows 11): turn off three- and four-finger gestures'
Write-Output '  - Windows 10: Settings > System > Tablet: never switch to tablet mode'
Write-Output '  - Control Panel > Pen and Touch: "Press and hold" right-click is unticked'
