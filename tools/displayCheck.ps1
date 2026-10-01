<#
.SYNOPSIS
  Report Windows settings that commonly cause tearing / unsynchronised
  flips with Psychtoolbox. Read-only: changes nothing.

.DESCRIPTION
  powershell -ExecutionPolicy Bypass -File displayCheck.ps1
  Run in the account that runs the experiments. Prints each setting with
  what Psychtoolbox prefers, and saves the report to C:\LocalExpData.
#>

function Reg($path, $name) {
  try { (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name } catch { $null }
}

$out = @("Display check on $env:COMPUTERNAME, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", '')

$os = Get-CimInstance Win32_OperatingSystem
$out += "Windows: $($os.Caption) build $($os.BuildNumber)"

foreach ($v in Get-CimInstance Win32_VideoController) {
  $out += "Graphics: $($v.Name), driver $($v.DriverVersion) ($($v.DriverDate)); " +
    "mode $($v.CurrentHorizontalResolution)x$($v.CurrentVerticalResolution) @ $($v.CurrentRefreshRate) Hz"
}
foreach ($m in Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue) {
  $name = -join ($m.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })
  $out += "Monitor: $name"
}

# Display scaling (DPI): 96 = 100%
Add-Type -Namespace DC -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
[DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int index);
'@
$dpi = [DC.Dpi]::GetDeviceCaps([DC.Dpi]::GetDC([IntPtr]::Zero), 88) # LOGPIXELSX
$out += ''
$out += "Display scaling: {0}% (want 100%)" -f [math]::Round($dpi / 96 * 100)

$hags = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
$hagsText = switch ($hags) { 2 { 'ON' } 1 { 'off' } default { 'not set (driver default)' } }
$out += "Hardware-accelerated GPU scheduling: $hagsText (want off)"

$dx = Reg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings'
$swapUpgrade = if ($dx -match 'SwapEffectUpgradeEnable=1') { 'ON' } elseif ($dx -match 'SwapEffectUpgradeEnable=0') { 'off' } else { 'not set (Windows default)' }
$out += "Optimisations for windowed games: $swapUpgrade (want off)"

$gameMode = Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
$out += "Game Mode: $(if ($gameMode -eq 0) { 'off' } else { 'on or default' })"

$contact = Reg 'HKCU:\Control Panel\Cursors' 'ContactVisualization'
$gesture = Reg 'HKCU:\Control Panel\Cursors' 'GestureVisualization'
$out += "Touch feedback circles: ContactVisualization=$contact GestureVisualization=$gesture (want 0 and 0; draws an overlay)"

$edge = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EdgeUI' 'AllowEdgeSwipe'
$out += "Edge swipes: $(if ($edge -eq 0) { 'disabled' } else { 'enabled' }) (touch lockdown applied: $(if ($edge -eq 0) { 'yes' } else { 'no' }))"

$vnc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'vnc' -or $_.DisplayName -match 'vnc' }
foreach ($s in $vnc) { $out += "VNC service: $($s.DisplayName) is $($s.Status)" }
$vncProc = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'vnc' }
foreach ($p in $vncProc) { $out += "VNC process running: $($p.ProcessName)" }

$plan = (powercfg /getactivescheme) -join ' '
$out += "Power plan: $plan"

$out | ForEach-Object { Write-Output $_ }
$dir = 'C:\LocalExpData'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
$file = Join-Path $dir ("displayCheck_{0}_{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
$out | Set-Content $file
Write-Output ''
Write-Output "Saved $file"
