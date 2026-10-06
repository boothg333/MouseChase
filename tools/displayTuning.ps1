<#
.SYNOPSIS
  Apply Windows display settings that help Psychtoolbox synchronise its
  screen updates with the monitor (prevents tearing).

.DESCRIPTION
  Run in an elevated PowerShell (Run as administrator), logged in as the
  account that runs the experiments (some settings are per user):

    powershell -ExecutionPolicy Bypass -File displayTuning.ps1          # apply
    powershell -ExecutionPolicy Bypass -File displayTuning.ps1 -Undo    # restore

  Changes:
    - "Optimisations for windowed games" off (DirectX swap-effect upgrade)
    - Game Mode off
    - Hardware-accelerated GPU scheduling off (if the GPU supports it)
    - Multiplane overlays (MPO) off - a known cause of flicker on Intel
    - Power plan: High performance
  Previous values are saved to displayTuning_backup_<PC>.json next to this
  script; -Undo restores them. Restart the PC afterwards.

  The touch feedback overlay is switched off by windowsTouchLockdown.ps1.
#>
param([switch]$Undo)

$ErrorActionPreference = 'Stop'
$backupFile = Join-Path $PSScriptRoot "displayTuning_backup_$env:COMPUTERNAME.json"

$settings = @(
  @{ Path = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'; Name = 'DirectXUserGlobalSettings';
     Type = 'String'; Desc = 'Optimisations for windowed games'; Value = $null }, # value built below
  @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled';
     Type = 'DWord'; Desc = 'Game Mode'; Value = 0 },
  @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode';
     Type = 'DWord'; Desc = 'Hardware-accelerated GPU scheduling (1 = off)'; Value = 1 },
  @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'OverlayTestMode';
     Type = 'DWord'; Desc = 'Multiplane overlays (5 = off)'; Value = 5 }
)
$highPerformance = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Please run this from an elevated PowerShell (Run as administrator).' }

function Get-Current($s) {
  if (-not (Test-Path $s.Path)) { return $null }
  $item = Get-ItemProperty -Path $s.Path -Name $s.Name -ErrorAction SilentlyContinue
  if ($null -eq $item) { return $null }
  return $item.($s.Name)
}

function Get-PowerScheme {
  $line = (powercfg /getactivescheme) -join ' '
  if ($line -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { return $Matches[1] }
  return $null
}

if ($Undo) {
  if (-not (Test-Path $backupFile)) { throw "No backup found at $backupFile" }
  $backup = Get-Content -Raw $backupFile | ConvertFrom-Json
  foreach ($b in $backup.Registry) {
    if ($null -eq $b.Previous) {
      Remove-ItemProperty -Path $b.Path -Name $b.Name -ErrorAction SilentlyContinue
      Write-Output ("Removed   {0}  ({1})" -f $b.Name, $b.Desc)
    } else {
      New-ItemProperty -Path $b.Path -Name $b.Name -Value $b.Previous -PropertyType $b.Type -Force | Out-Null
      Write-Output ("Restored  {0} = {1}  ({2})" -f $b.Name, $b.Previous, $b.Desc)
    }
  }
  if ($backup.PowerScheme) {
    powercfg /setactive $backup.PowerScheme
    Write-Output "Restored  power plan $($backup.PowerScheme)"
  }
  Write-Output 'Done. Restart the PC for all changes to take effect.'
  return
}

# Windowed-games setting lives in a ';'-separated string with other options:
# keep those, set SwapEffectUpgradeEnable=0
$dx = $settings[0]
$current = Get-Current $dx
$parts = @()
if ($current) { $parts = $current.Split(';') | Where-Object { $_ -and $_ -notmatch '^SwapEffectUpgradeEnable=' } }
$dx.Value = (($parts + 'SwapEffectUpgradeEnable=0') -join ';') + ';'

if (Test-Path $backupFile) {
  Write-Output "Backup $backupFile already exists (tuning applied before); not overwriting it."
} else {
  $backup = [pscustomobject]@{
    Registry = @(foreach ($s in $settings) {
      [pscustomobject]@{ Path = $s.Path; Name = $s.Name; Type = $s.Type; Desc = $s.Desc; Previous = (Get-Current $s) }
    })
    PowerScheme = (Get-PowerScheme)
  }
  $backup | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $backupFile
  Write-Output "Saved previous values to $backupFile"
}

foreach ($s in $settings) {
  if (-not (Test-Path $s.Path)) { New-Item -Path $s.Path -Force | Out-Null }
  New-ItemProperty -Path $s.Path -Name $s.Name -Value $s.Value -PropertyType $s.Type -Force | Out-Null
  Write-Output ("Set       {0} = {1}  ({2})" -f $s.Name, $s.Value, $s.Desc)
}
powercfg /setactive $highPerformance 2>$null
if ($LASTEXITCODE -eq 0) { Write-Output 'Set       power plan: High performance' }
else { Write-Output 'Could not select the High performance power plan (not available?); left unchanged.' }

Write-Output ''
Write-Output 'Done. Restart the PC for all changes to take effect.'
