<#
.SYNOPSIS
  Background touch reader for MouseChaseTouch: reads the multi-touch overlay
  through Windows raw input and sends every report to MATLAB over UDP.

.DESCRIPTION
  touchReader.ps1 -Port <MATLAB's UDP port> -ParentPid <MATLAB pid> [-LogFile f]

  Started (hidden) by MouseChaseTouch at experiment start. Uses a hidden
  message-only window registered for raw input from touchscreens (HID usage
  page 0x0D, usage 0x04) with RIDEV_INPUTSINK, so it receives touches
  whichever window has focus, without creating any visible window.

  Each HID report becomes one UDP datagram to 127.0.0.1:<Port>:
      R <seconds since reader start> <contact count>
      <id> <tip> <x> <y> <width> <height>     one line per used finger slot
  x, y, width and height are the overlay's logical units (0..LogicalMax,
  sent once in the HELLO message: 'HELLO <xMax> <yMax>').
  Empty slots (contact id 255 with the tip up) are left out.

  Exits when it receives 'QUIT', or when the MATLAB process ends.
#>
param([Parameter(Mandatory = $true)][int]$Port, [Parameter(Mandatory = $true)][int]$ParentPid,
  [string]$LogFile = '')

function Log($msg) {
  if ($LogFile) {
    try { Add-Content -Path $LogFile -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $msg) } catch { }
  }
}

try {
  Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public class TouchReader : NativeWindow {
  const int WM_INPUT = 0x00FF;
  const uint RID_INPUT = 0x10000003, RIDI_PREPARSEDDATA = 0x20000005;
  const int HIDP_OK = 0x00110000, HidP_Input = 0;

  [StructLayout(LayoutKind.Sequential)] struct RAWINPUTDEVICE { public ushort UsagePage; public ushort Usage; public uint Flags; public IntPtr Target; }
  [StructLayout(LayoutKind.Sequential)] struct RAWINPUTHEADER { public uint Type; public uint Size; public IntPtr Device; public IntPtr wParam; }
  [StructLayout(LayoutKind.Sequential)] struct HIDP_CAPS {
    public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
    public ushort NumberLinkCollectionNodes, NumberInputButtonCaps, NumberInputValueCaps, NumberInputDataIndices,
      NumberOutputButtonCaps, NumberOutputValueCaps, NumberOutputDataIndices,
      NumberFeatureButtonCaps, NumberFeatureValueCaps, NumberFeatureDataIndices;
  }
  [StructLayout(LayoutKind.Sequential)] struct HIDP_VALUE_CAPS {
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

  UdpClient udp;
  IPEndPoint matlab;
  int parentPid;
  Dictionary<IntPtr, IntPtr> pre = new Dictionary<IntPtr, IntPtr>();
  Dictionary<IntPtr, ushort> links = new Dictionary<IntPtr, ushort>();
  Stopwatch clock = Stopwatch.StartNew();
  bool helloSent = false;
  public int Reports = 0;
  public string Status = "";

  public static string Run(int port, int parentPid) {
    TouchReader r = new TouchReader();
    return r.RunLoop(port, parentPid);
  }

  string RunLoop(int port, int pid) {
    parentPid = pid;
    matlab = new IPEndPoint(IPAddress.Loopback, port);
    udp = new UdpClient(new IPEndPoint(IPAddress.Loopback, 0));
    CreateParams cp = new CreateParams();
    cp.Parent = new IntPtr(-3); // HWND_MESSAGE: no visible window
    CreateHandle(cp);
    RAWINPUTDEVICE[] d = new RAWINPUTDEVICE[1];
    d[0].UsagePage = 0x0D; d[0].Usage = 0x04; d[0].Flags = 0x100; d[0].Target = Handle; // RIDEV_INPUTSINK
    if (!RegisterRawInputDevices(d, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))))
      return "RegisterRawInputDevices failed, error " + Marshal.GetLastWin32Error();
    Send("HELLO 0 0"); // logical ranges follow in a second HELLO once a device reports
    Timer timer = new Timer();
    timer.Interval = 200;
    timer.Tick += delegate { Housekeeping(); };
    timer.Start();
    Application.Run();
    timer.Stop();
    Send("BYE");
    udp.Close();
    return Status == "" ? "stopped after " + Reports + " reports" : Status;
  }

  void Housekeeping() {
    bool parentAlive;
    try { parentAlive = !Process.GetProcessById(parentPid).HasExited; } catch { parentAlive = false; }
    if (!parentAlive) { Status = "MATLAB process ended"; Application.ExitThread(); return; }
    while (udp.Available > 0) {
      IPEndPoint from = new IPEndPoint(IPAddress.Any, 0);
      string msg = Encoding.ASCII.GetString(udp.Receive(ref from)).Trim();
      if (msg == "QUIT") { Status = "QUIT received after " + Reports + " reports"; Application.ExitThread(); return; }
    }
  }

  void Send(string s) {
    byte[] b = Encoding.ASCII.GetBytes(s);
    try { udp.Send(b, b.Length, matlab); } catch { }
  }

  protected override void WndProc(ref Message m) {
    if (m.Msg == WM_INPUT) {
      try { OnInput(m.LParam); } catch (Exception e) { Status = e.Message; }
    }
    base.WndProc(ref m);
  }

  void OnInput(IntPtr lParam) {
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
        Reports++;
        Decode(h.Device, pp, rep);
      }
    } finally { Marshal.FreeHGlobal(buf); }
  }

  IntPtr Preparsed(IntPtr dev) {
    if (pre.ContainsKey(dev)) return pre[dev];
    uint n = 0;
    GetRawInputDeviceInfo(dev, RIDI_PREPARSEDDATA, IntPtr.Zero, ref n);
    IntPtr pp = Marshal.AllocHGlobal((int)n);
    GetRawInputDeviceInfo(dev, RIDI_PREPARSEDDATA, pp, ref n);
    HIDP_CAPS c = new HIDP_CAPS(); c.Reserved = new ushort[17];
    HidP_GetCaps(pp, ref c);
    pre[dev] = pp; links[dev] = c.NumberLinkCollectionNodes;
    if (!helloSent) {
      Send(string.Format("HELLO {0} {1}", LogicalMax(pp, 0x30), LogicalMax(pp, 0x31)));
      helloSent = true;
    }
    return pp;
  }

  int LogicalMax(IntPtr pp, ushort usage) {
    HIDP_VALUE_CAPS[] vc = new HIDP_VALUE_CAPS[64]; ushort n = 64;
    if (HidP_GetSpecificValueCaps(HidP_Input, 0x01, 0, usage, vc, ref n, pp) != HIDP_OK || n == 0) return 0;
    return vc[0].LogicalMax;
  }

  bool Get(IntPtr pp, byte[] rep, ushort page, ushort link, ushort usage, out uint v) {
    return HidP_GetUsageValue(HidP_Input, page, link, usage, out v, pp, rep, (uint)rep.Length) == HIDP_OK;
  }

  void Decode(IntPtr dev, IntPtr pp, byte[] rep) {
    uint cc;
    if (!Get(pp, rep, 0x0D, 0, 0x54, out cc)) cc = 0;
    StringBuilder sb = new StringBuilder();
    sb.AppendFormat("R {0:F5} {1}\n", clock.Elapsed.TotalSeconds, cc);
    for (ushort link = 1; link < links[dev]; link++) {
      uint id, x, y, w, ht;
      if (!Get(pp, rep, 0x0D, link, 0x51, out id)) continue; // not a finger collection
      ushort[] us = new ushort[32]; uint nu = 32; bool tip = false;
      if (HidP_GetUsages(HidP_Input, 0x0D, link, us, ref nu, pp, rep, (uint)rep.Length) == HIDP_OK)
        for (int i = 0; i < nu; i++) if (us[i] == 0x42) tip = true;
      if (id == 255 && !tip) continue; // empty slot
      if (!Get(pp, rep, 0x01, link, 0x30, out x)) x = 0;
      if (!Get(pp, rep, 0x01, link, 0x31, out y)) y = 0;
      if (!Get(pp, rep, 0x0D, link, 0x48, out w)) w = 0;
      if (!Get(pp, rep, 0x0D, link, 0x49, out ht)) ht = 0;
      sb.AppendFormat("{0} {1} {2} {3} {4} {5}\n", id, tip ? 1 : 0, x, y, w, ht);
    }
    Send(sb.ToString());
  }
}
'@
  Log "started, sending to 127.0.0.1:$Port, parent MATLAB pid $ParentPid"
  $result = [TouchReader]::Run($Port, $ParentPid)
  Log "exited: $result"
} catch {
  Log "error: $($_.Exception.Message)"
}
