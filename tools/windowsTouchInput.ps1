<#
.SYNOPSIS
  Switch Windows' own handling of touch input off or on (per user).

.DESCRIPTION
  powershell -ExecutionPolicy Bypass -File windowsTouchInput.ps1          # show current state
  powershell -ExecutionPolicy Bypass -File windowsTouchInput.ps1 -Off     # Windows ignores touches
  powershell -ExecutionPolicy Bypass -File windowsTouchInput.ps1 -On      # back to normal

  Sets HKCU\Software\Microsoft\Wisp\Touch\TouchGate (0 = off, 1 = on), the
  setting behind the old "Use your finger as an input device" checkbox,
  which Windows 11's Control Panel no longer shows. With touch off, touches
  no longer move the pointer, click or trigger gestures; MouseChase's touch
  reader (tools/touchReader.ps1) reads the raw overlay data separately -
  verify with rawTouchTest.ps1 that it still receives touches.
  Run as the account that runs the experiments, then sign out and back in.
#>
param([switch]$Off, [switch]$On)

$path = 'HKCU:\Software\Microsoft\Wisp\Touch'
function Show-State {
  $v = $null
  try { $v = (Get-ItemProperty -Path $path -Name TouchGate -ErrorAction Stop).TouchGate } catch { }
  $state = switch ($v) { 0 { 'OFF (Windows ignores touches)' } 1 { 'on' } default { 'not set (on, Windows default)' } }
  Write-Output "Windows touch input (TouchGate = $v): $state"
}

Show-State
if ($Off -or $On) {
  if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
  New-ItemProperty -Path $path -Name TouchGate -Value ([int][bool]$On) -PropertyType DWord -Force | Out-Null
  Show-State
  Write-Output 'Sign out and back in (or restart) for this to take effect.'
}
