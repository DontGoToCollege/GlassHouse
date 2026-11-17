# Smoke check for a GlassHouse build: opens a picture in a throwaway copy of the app on a hidden Windows desktop,
# so nothing appears on screen or takes focus, and checks it shows its window, stays up and saves settings portably.
# Usage: tools\smoke.ps1 -App <folder with GlassHouse.exe>     (build.ps1 runs it on every build)
param([Parameter(Mandatory)][string]$App)

$ErrorActionPreference = "Stop"
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class HiddenDesktop {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SI { public int cb; public string r, desk, title; public int x,y,w,h,cx,cy,fill,flags; public short show, r2; public IntPtr r3, i, o, e; }
    [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr hp, ht; public int pid, tid; }
    [DllImport("user32", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateDesktop(string n, IntPtr a, IntPtr b, int f, uint acc, IntPtr sa);
    [DllImport("user32")] static extern bool CloseDesktop(IntPtr d);
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcess(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inh, int flags, IntPtr env, string dir, ref SI si, out PI pi);
    [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);
    delegate bool EnumProc(IntPtr w, IntPtr l);
    [DllImport("user32")] static extern bool EnumDesktopWindows(IntPtr d, EnumProc f, IntPtr l);
    [DllImport("user32", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr w, StringBuilder s, int n);
    [DllImport("user32")] static extern int GetWindowThreadProcessId(IntPtr w, out int pid);
    [DllImport("user32")] static extern bool IsWindowVisible(IntPtr w);
    public static IntPtr Desk;
    public static int Start(string name, string cmd, string dir) {
        Desk = CreateDesktop(name, IntPtr.Zero, IntPtr.Zero, 0, 0x10000000, IntPtr.Zero);
        if (Desk == IntPtr.Zero) throw new Exception("CreateDesktop failed: " + Marshal.GetLastWin32Error());
        var si = new SI(); si.cb = Marshal.SizeOf(si); si.desk = name; PI pi;
        if (!CreateProcess(null, new StringBuilder(cmd), IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, dir, ref si, out pi))
            throw new Exception("CreateProcess failed: " + Marshal.GetLastWin32Error());
        CloseHandle(pi.hp); CloseHandle(pi.ht); return pi.pid;
    }
    public static string Titles(int pid) {
        var sb = new StringBuilder();
        EnumDesktopWindows(Desk, (w, l) => { int p; GetWindowThreadProcessId(w, out p);
            if (p == pid && IsWindowVisible(w)) { var t = new StringBuilder(256); GetWindowText(w, t, 256); if (t.Length > 0) sb.Append(t).Append('|'); }
            return true; }, IntPtr.Zero);
        return sb.ToString();
    }
    public static void Close() { if (Desk != IntPtr.Zero) CloseDesktop(Desk); Desk = IntPtr.Zero; }
}
"@

$work = Join-Path $env:TEMP "GlassHouse-smoke-$PID"
Copy-Item $App $work -Recurse
$pic = Join-Path $work "smoke-test.png"
Copy-Item "$PSScriptRoot\..\source\__assets\glasshouse\logo_512.png" $pic
$fail = $null
$procId = 0
try {
    $procId = [HiddenDesktop]::Start("GlassHouseSmoke$PID", "`"$work\GlassHouse.exe`" --ig-no-quick-setup `"$pic`"", $work)
    $titles = ""
    for ($i = 0; $i -lt 40 -and -not $titles; $i++) { Start-Sleep -Milliseconds 500; $titles = [HiddenDesktop]::Titles($procId) }
    # the title gains the picture's name once it has loaded
    for ($i = 0; $i -lt 20 -and $titles -notmatch "smoke-test"; $i++) { Start-Sleep -Milliseconds 500; $t = [HiddenDesktop]::Titles($procId); if ($t) { $titles = $t } }
    Start-Sleep -Seconds 2
    if (-not $titles) { $fail = "no window appeared within 20 seconds" }
    elseif ($titles -notmatch "GlassHouse") { $fail = "window title doesn't say GlassHouse: $titles" }
    elseif ($titles -notmatch "smoke-test") { $fail = "the test picture isn't open: $titles" }
    elseif (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { $fail = "it closed by itself after opening" }
    elseif (-not (Get-ChildItem $work -Directory | Where-Object Name -like "_*cache*" -ErrorAction SilentlyContinue) -and -not (Test-Path "$work\igconfig.json") -and -not (Test-Path "$work\_logs")) {
        $fail = "nothing was written next to the exe, so portable mode isn't on"
    }
}
finally {
    if ($procId) { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 800 }
    [HiddenDesktop]::Close()
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fail) { throw "Smoke check failed: $fail" }
Write-Host "Smoke check passed: window '$($titles.TrimEnd('|'))' opened the test picture and stayed up." -ForegroundColor Green
