<#
.SYNOPSIS
  Check whether Windows delivers the touch overlay's raw HID data to a
  background program (no Psychtoolbox involved).

.DESCRIPTION
  powershell -ExecutionPolicy Bypass -File rawTouchTest.ps1 [-Seconds 15] [-NoBackgroundPhase]

  Registers a hidden window for raw input from touchscreens (HID usage page
  0x0D, usage 0x04) with RIDEV_INPUTSINK, so it also receives input while
  another program has focus. Every report is decoded with the Windows HID
  parser (HidP_*): contact count, and per contact its ID, tip switch
  (finger down), X, Y, width and height.

  Phase 1: this window is in front - touch it.
  Phase 2: a second PowerShell window opens maximised (another program in
           front, like the stimulus window during an experiment) - touch it
           until it closes. This is the important one.

  Writes rawTouchTest_<PC>_<time>.txt (summary) and .csv (all decoded
  contacts) to C:\LocalExpData.
#>
param([int]$Seconds = 15, [switch]$NoBackgroundPhase, [string]$OutDir = 'C:\LocalExpData')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public class RawTouch : NativeWindow {
  const int WM_INPUT = 0x00FF;
  const uint RID_INPUT = 0x10000003, RIDI_PREPARSEDDATA = 0x20000005, RIDI_DEVICENAME = 0x20000007;
  const int HIDP_OK = 0x00110000, HidP_Input = 0;

  [StructLayout(LayoutKind.Sequential)] struct RAWINPUTDEVICE { public ushort UsagePage; public ushort Usage; public uint Flags; public IntPtr Target; }
  [StructLayout(LayoutKind.Sequential)] struct RAWINPUTHEADER { public uint Type; public uint Size; public IntPtr Device; public IntPtr wParam; }
  [StructLayout(LayoutKind.Sequential)] public struct HIDP_CAPS {
    public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
    public ushort NumberLinkCollectionNodes, NumberInputButtonCaps, NumberInputValueCaps, NumberInputDataIndices,
      NumberOutputButtonCaps, NumberOutputValueCaps, NumberOutputDataIndices,
      NumberFeatureButtonCaps, NumberFeatureValueCaps, NumberFeatureDataIndices;
  }
  [StructLayout(LayoutKind.Sequential)] public struct HIDP_VALUE_CAPS {
    public ushort UsagePage; public byte ReportID, IsAlias; public ushort BitField, LinkCollection, LinkUsage, LinkUsagePage;
    public byte IsRange, IsStringRange, IsDesignatorRange, IsAbsolute, HasNull, Reserved;
    public ushort BitSize, ReportCount, R0, R1, R2, R3, R4;
    public uint UnitsExp, Units; public int LogicalMin, LogicalMax, PhysicalMin, PhysicalMax;
    public ushort UsageMin, UsageMax, StringMin, StringMax, DesignatorMin, DesignatorMax, DataIndexMin, DataIndexMax;
  }

  [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] d, uint n, uint size);
  [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr h, uint cmd, IntPtr data, ref uint size, uint headerSize);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint GetRawInputDeviceInfo(IntPtr dev, uint cmd, IntPtr data, ref uint size);
  [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr pp, ref HIDP_CAPS caps);
  [DllImport("hid.dll")] static extern int HidP_GetUsageValue(int type, ushort page, ushort link, ushort usage, out uint value, IntPtr pp, byte[] report, uint len);
  [DllImport("hid.dll")] static extern int HidP_GetUsages(int type, ushort page, ushort link, [Out] ushort[] usages, ref uint n, IntPtr pp, byte[] report, uint len);
  [DllImport("hid.dll")] static extern int HidP_GetSpecificValueCaps(int type, ushort page, ushort link, ushort usage, [Out] HIDP_VALUE_CAPS[] caps, ref ushort n, IntPtr pp);

  public int Phase = 1;
  public int[] Reports = new int[3], SinkReports = new int[3];
  public int MaxContactCount = 0, MaxTipsInReport = 0, LastError = 0;
  public string Error = "";
  public HashSet<uint> TipIds = new HashSet<uint>();
  public List<string> Rows = new List<string>();
  public Dictionary<IntPtr, string> Info = new Dictionary<IntPtr, string>();
  Dictionary<IntPtr, IntPtr> pre = new Dictionary<IntPtr, IntPtr>();
  Dictionary<IntPtr, HIDP_CAPS> caps = new Dictionary<IntPtr, HIDP_CAPS>();
  Stopwatch clock = Stopwatch.StartNew();

  public bool Start() {
    CreateParams cp = new CreateParams();
    cp.Parent = new IntPtr(-3); // HWND_MESSAGE: invisible, message-only window
    CreateHandle(cp);
    RAWINPUTDEVICE[] d = new RAWINPUTDEVICE[1];
    d[0].UsagePage = 0x0D; d[0].Usage = 0x04; d[0].Flags = 0x100; d[0].Target = Handle; // RIDEV_INPUTSINK
    bool ok = RegisterRawInputDevices(d, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)));
    if (!ok) LastError = Marshal.GetLastWin32Error();
    return ok;
  }

  protected override void WndProc(ref Message m) {
    if (m.Msg == WM_INPUT) {
      try { OnInput(m.LParam, (m.WParam.ToInt64() & 0xFF) == 1); }
      catch (Exception e) { Error = e.ToString(); }
    }
    base.WndProc(ref m);
  }

  void OnInput(IntPtr lParam, bool sink) {
    uint hdr = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER)), size = 0;
    GetRawInputData(lParam, RID_INPUT, IntPtr.Zero, ref size, hdr);
    IntPtr buf = Marshal.AllocHGlobal((int)size);
    try {
      if (GetRawInputData(lParam, RID_INPUT, buf, ref size, hdr) != size) return;
      RAWINPUTHEADER h = (RAWINPUTHEADER)Marshal.PtrToStructure(buf, typeof(RAWINPUTHEADER));
      if (h.Type != 2) return; // RIM_TYPEHID
      int sizeHid = Marshal.ReadInt32(buf, (int)hdr), count = Marshal.ReadInt32(buf, (int)hdr + 4);
      IntPtr pp = Preparsed(h.Device);
      for (int r = 0; r < count; r++) {
        byte[] rep = new byte[sizeHid];
        Marshal.Copy(IntPtr.Add(buf, (int)hdr + 8 + r * sizeHid), rep, 0, sizeHid);
        Reports[Phase]++; if (sink) SinkReports[Phase]++;
        Decode(h.Device, pp, rep);
      }
    } finally { Marshal.FreeHGlobal(buf); }
  }

  IntPtr Preparsed(IntPtr dev) {
    if (pre.ContainsKey(dev)) return pre[dev];
    uint n = 0;
    GetRawInputDeviceInfo(dev, RIDI_DEVICENAME, IntPtr.Zero, ref n);
    IntPtr nb = Marshal.AllocHGlobal((int)n * 2 + 2);
    GetRawInputDeviceInfo(dev, RIDI_DEVICENAME, nb, ref n);
    string name = Marshal.PtrToStringUni(nb);
    Marshal.FreeHGlobal(nb);
    n = 0;
    GetRawInputDeviceInfo(dev, RIDI_PREPARSEDDATA, IntPtr.Zero, ref n);
    IntPtr pp = Marshal.AllocHGlobal((int)n);
    GetRawInputDeviceInfo(dev, RIDI_PREPARSEDDATA, pp, ref n);
    HIDP_CAPS c = new HIDP_CAPS(); c.Reserved = new ushort[17];
    HidP_GetCaps(pp, ref c);
    pre[dev] = pp; caps[dev] = c;
    Info[dev] = string.Format("{0}\n    usage page 0x{1:X2} usage 0x{2:X2}, input report {3} bytes, {4} link collections, X: {5}, Y: {6}",
      name, c.UsagePage, c.Usage, c.InputReportByteLength, c.NumberLinkCollectionNodes,
      Range(pp, 0x30), Range(pp, 0x31));
    return pp;
  }

  string Range(IntPtr pp, ushort usage) {
    HIDP_VALUE_CAPS[] vc = new HIDP_VALUE_CAPS[64]; ushort n = 64;
    if (HidP_GetSpecificValueCaps(HidP_Input, 0x01, 0, usage, vc, ref n, pp) != HIDP_OK || n == 0) return "not found";
    return string.Format("logical {0}..{1}, physical {2}..{3} (units 0x{4:X}, exp {5})",
      vc[0].LogicalMin, vc[0].LogicalMax, vc[0].PhysicalMin, vc[0].PhysicalMax, vc[0].Units, vc[0].UnitsExp);
  }

  bool Get(IntPtr pp, byte[] rep, ushort page, ushort link, ushort usage, out uint v) {
    return HidP_GetUsageValue(HidP_Input, page, link, usage, out v, pp, rep, (uint)rep.Length) == HIDP_OK;
  }

  void Decode(IntPtr dev, IntPtr pp, byte[] rep) {
    HIDP_CAPS c = caps[dev];
    uint cc;
    int contactCount = Get(pp, rep, 0x0D, 0, 0x54, out cc) ? (int)cc : -1;
    if (contactCount > MaxContactCount) MaxContactCount = contactCount;
    int tips = 0;
    double t = clock.Elapsed.TotalSeconds;
    for (ushort link = 1; link < c.NumberLinkCollectionNodes; link++) {
      uint id, x, y, w, ht;
      if (!Get(pp, rep, 0x0D, link, 0x51, out id)) continue; // not a finger collection
      bool hasX = Get(pp, rep, 0x01, link, 0x30, out x), hasY = Get(pp, rep, 0x01, link, 0x31, out y);
      if (!Get(pp, rep, 0x0D, link, 0x48, out w)) w = 0;
      if (!Get(pp, rep, 0x0D, link, 0x49, out ht)) ht = 0;
      ushort[] us = new ushort[32]; uint nu = 32; bool tip = false;
      if (HidP_GetUsages(HidP_Input, 0x0D, link, us, ref nu, pp, rep, (uint)rep.Length) == HIDP_OK)
        for (int i = 0; i < nu; i++) if (us[i] == 0x42) tip = true;
      if (tip) { tips++; TipIds.Add(id); }
      Rows.Add(string.Format("{0},{1:F4},{2},{3},{4},{5},{6},{7},{8},{9}",
        Phase, t, contactCount, link, id, tip ? 1 : 0, hasX ? (long)x : -1, hasY ? (long)y : -1, w, ht));
    }
    if (tips > MaxTipsInReport) MaxTipsInReport = tips;
  }
}
'@

function Pump($rt, $secs, $label) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $secs) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 2
    Write-Host -NoNewline ("`r  {0}: {1,3:F0} s left, reports {2}   " -f $label, ($secs - $sw.Elapsed.TotalSeconds), $rt.Reports[$rt.Phase])
  }
  Write-Host ''
}

$rt = New-Object RawTouch
if (-not $rt.Start()) { throw "RegisterRawInputDevices failed, Windows error $($rt.LastError)" }

Write-Host "`nPHASE 1 ($Seconds s): touch THIS window - one finger, then several." -ForegroundColor Yellow
Pump $rt $Seconds 'phase 1 (this window in front)'

if (-not $NoBackgroundPhase) {
  $rt.Phase = 2
  Write-Host "`nPHASE 2 ($Seconds s): a second window opens - touch IT with several fingers until it closes." -ForegroundColor Yellow
  Start-Sleep -Seconds 2
  $msg = "Write-Host 'PHASE 2: touch THIS window with several fingers until it closes (background test)' -ForegroundColor Yellow"
  $other = Start-Process powershell -PassThru -WindowStyle Maximized -ArgumentList '-NoExit', '-Command', $msg
  Pump $rt $Seconds 'phase 2 (other window in front)'
  try { Stop-Process -Id $other.Id -ErrorAction Stop } catch { }
}

$summary = @(
  "Raw touch test on $env:COMPUTERNAME, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
  "Phase 1 (own window in front):   $($rt.Reports[1]) reports ($($rt.SinkReports[1]) received in background mode)",
  "Phase 2 (other window in front): $($rt.Reports[2]) reports ($($rt.SinkReports[2]) received in background mode)",
  "Max contact count reported: $($rt.MaxContactCount); max fingers down in one report: $($rt.MaxTipsInReport)",
  "Contact IDs seen with finger down: $(($rt.TipIds | Sort-Object) -join ', ')",
  'Devices:'
) + ($rt.Info.Values | ForEach-Object { "  $_" })
if ($rt.Error) { $summary += "Decode error: $($rt.Error)" }

$summary | ForEach-Object { Write-Host $_ }
$dir = $OutDir
if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
$base = Join-Path $dir ("rawTouchTest_{0}_{1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
$summary | Set-Content "$base.txt"
@('phase,time,contactCount,link,id,tip,x,y,width,height') + $rt.Rows | Set-Content "$base.csv"
Write-Host "`nSaved $base.txt and .csv" -ForegroundColor Green
