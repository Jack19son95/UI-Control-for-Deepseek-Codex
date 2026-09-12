# ============================================================================
# uikit.ps1 -- Windows UI automation core (standalone, no external dependencies).
# Capabilities: window enumeration / control tree, real mouse & keyboard, message-level control, UIA,
# screenshots, wait helpers, clipboard, monitors, batch steps, action log, safety denylist.
# Usage: . "$PSScriptRoot\uikit.ps1" then call the functions (ui.ps1 is the CLI wrapper).
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Import-UiKitType {
    <#
      Compile a P/Invoke helper once and reuse it afterwards.
      Every UI action is its own PowerShell process and Add-Type -TypeDefinition costs ~0.5 s per process
      (Roslyn/CSC compile). Caching the assembly as a DLL next to the logs cuts that to ~20 ms.
      The cache is keyed by a hash of the source, so edits invalidate it, and it is split per runtime
      (.NET Framework and .NET Core cannot share assemblies). Any failure falls back to compiling in
      memory, so a read-only or blocked temp folder only costs speed, never function.
    #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Source)
    if ($Name -as [type]) { return }
    $dll = ''
    try {
        $tag = if ($PSVersionTable.PSEdition -eq 'Core') { 'core' } else { 'netfx' }
        $sha = [Security.Cryptography.SHA256]::Create()
        $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Source))) -replace '-', '').Substring(0, 16)
        $dir = Join-Path (Join-Path (Join-Path $env:TEMP 'codex-uia') 'asm') $tag
        $dll = Join-Path $dir ("$Name.$hash.dll")
        if (Test-Path -LiteralPath $dll) {
            try { Add-Type -Path $dll -ErrorAction Stop; if ($Name -as [type]) { return } } catch { }
        }
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $tmp = Join-Path $dir ("$Name.$hash.$PID.tmp")
        Add-Type -TypeDefinition $Source -OutputAssembly $tmp -OutputType Library -ErrorAction Stop
        Move-Item -LiteralPath $tmp -Destination $dll -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $dll) {
            Add-Type -Path $dll -ErrorAction Stop
            if ($Name -as [type]) { return }
        }
    } catch { }
    <# Last resort: original behaviour (in-memory compile). #>
    Add-Type -TypeDefinition $Source
}

Import-UiKitType -Name 'UiKit' -Source @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class UiKit {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom;
        public int Width { get { return Right - Left; } } public int Height { get { return Bottom - Top; } } }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
        public int cbSize; public uint flags; public IntPtr hwndActive, hwndFocus, hwndCapture,
        hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rcCaret; }
    [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO {
        public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    [StructLayout(LayoutKind.Sequential)] public struct CURSORINFO {
        public int cbSize; public uint flags; public IntPtr hCursor; public POINT ptScreenPos; }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT {
        public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT {
        public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct HARDWAREINPUT {
        public uint uMsg; public ushort wParamL, wParamH; }
    [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION {
        [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", EntryPoint="GetWindowTextW", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", EntryPoint="GetWindowTextLengthW")] public static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll", EntryPoint="SendMessageW")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll", EntryPoint="SendMessageW", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageText(IntPtr h, uint m, IntPtr w, string l);
    [DllImport("user32.dll", EntryPoint="SendMessageW", CharSet=CharSet.Unicode)] public static extern int SendMessageGetText(IntPtr h, uint m, IntPtr w, StringBuilder l);
    [DllImport("user32.dll", EntryPoint="PostMessageW")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h, int id);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool altTab);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO gti);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int idx);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr mon, ref MONITORINFO mi);
    [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] public static extern bool GetCursorInfo(ref CURSORINFO ci);
    [DllImport("user32.dll")] public static extern IntPtr CopyIcon(IntPtr h);
    [DllImport("user32.dll")] public static extern bool DrawIconEx(IntPtr dc, int x, int y, IntPtr icon, int cx, int cy, uint step, IntPtr brush, uint flags);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll", EntryPoint="FindWindowExW", CharSet=CharSet.Unicode)]
    public static extern IntPtr FindWindowExW(IntPtr parent, IntPtr after, string cls, string win);
    [DllImport("user32.dll", EntryPoint="GetWindow")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);

    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004,
        MOUSEEVENTF_RIGHTDOWN = 0x0008, MOUSEEVENTF_RIGHTUP = 0x0010,
        MOUSEEVENTF_MIDDLEDOWN = 0x0020, MOUSEEVENTF_MIDDLEUP = 0x0040,
        MOUSEEVENTF_WHEEL = 0x0800, MOUSEEVENTF_HWHEEL = 0x1000;
    public const uint KEYEVENTF_KEYUP = 0x0002, KEYEVENTF_UNICODE = 0x0004;
    public const uint GW_OWNER = 4;
    public static readonly IntPtr HWND_TOP = IntPtr.Zero, HWND_TOPMOST = (IntPtr)(-1), HWND_NOTOPMOST = (IntPtr)(-2);

    public static string ClassOf(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    public static string TextOf(IntPtr h) { int n = GetWindowTextLength(h); var sb = new StringBuilder(n + 2); GetWindowText(h, sb, n + 2); return sb.ToString(); }
    public static int PidOf(IntPtr h) { uint pid; GetWindowThreadProcessId(h, out pid); return (int)pid; }
    public static uint ThreadOf(IntPtr h) { uint pid; return GetWindowThreadProcessId(h, out pid); }
    public static RECT RectOf(IntPtr h) { RECT r; GetWindowRect(h, out r); return r; }

    public static List<IntPtr> TopLevel() {
        var list = new List<IntPtr>();
        EnumWindows(delegate(IntPtr h, IntPtr p) { list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }
    public static List<IntPtr> DirectChildren(IntPtr parent) {
        var list = new List<IntPtr>();
        IntPtr child = IntPtr.Zero;
        while (true) {
            child = FindWindowExW(parent, child, null, null);
            if (child == IntPtr.Zero) break;
            list.Add(child);
        }
        return list;
    }
    public static List<IntPtr> Monitors() {
        var list = new List<IntPtr>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr h, IntPtr p) { list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }
    public static MONITORINFO MonitorInfoOf(IntPtr mon) {
        var mi = new MONITORINFO(); mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO)); GetMonitorInfo(mon, ref mi); return mi;
    }
    public static INPUT KeyInput(ushort vk, bool up) {
        INPUT i = new INPUT(); i.type = 1; i.u.ki.wVk = vk;
        i.u.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0; return i; }
    public static INPUT UniInput(char c, bool up) {
        INPUT i = new INPUT(); i.type = 1; i.u.ki.wScan = (ushort)c;
        i.u.ki.dwFlags = KEYEVENTF_UNICODE | (up ? KEYEVENTF_KEYUP : 0); return i; }
    public static INPUT MouseInput(uint flags, int dx, int dy, int data) {
        INPUT i = new INPUT(); i.type = 0; i.u.mi.dx = dx; i.u.mi.dy = dy;
        i.u.mi.mouseData = (uint)data; i.u.mi.dwFlags = flags; return i; }
    public static int Send(INPUT[] inputs) {
        return (int)SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT))); }
    public static int InputSize() { return Marshal.SizeOf(typeof(INPUT)); }
}
'@
<#
  MSAA (Microsoft Active Accessibility) accessor.
  Legacy Win32 controls are often reported as generic 'Pane' elements without patterns by the .NET UIA client;
  going through oleacc's IAccessible is what yields the real role (button/edit/list...),
  name, state and default action, and lets us invoke that action (equivalent to UIA Invoke).
  The interface is carried as 'object' so no .NET Accessibility assembly reference is needed.
#>
Import-UiKitType -Name 'Msaa' -Source @'
using System;
using System.Runtime.InteropServices;

public class Msaa {
    [DllImport("oleacc.dll")]
    public static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint dwObjectID,
        ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppvObject);

    public static object Client(IntPtr hwnd) {
        Guid iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");   // IID_IAccessible
        object o;
        int hr = AccessibleObjectFromWindow(hwnd, 0xFFFFFFFC, ref iid, out o);  // OBJID_CLIENT
        return (hr == 0) ? o : null;
    }
    public static object Self(IntPtr hwnd) {
        Guid iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");
        object o;
        int hr = AccessibleObjectFromWindow(hwnd, 0x00000000, ref iid, out o);  // OBJID_WINDOW
        return (hr == 0) ? o : null;
    }
}
'@

# Locale-independent rules first: process names and window classes.
$script:UiBlockedProcesses = @(
    # terminals / shells / dev hosts
    'cmd','conhost','windowsterminal','wt','powershell','pwsh','wsl','bash','sh','fish','nu',
    'codex','chatgpt',
    # credential / logon / UAC machinery (these are the same on every UI language)
    'consent','logonui','credentialuibroker','winlogon','lsass'
)
$script:UiBlockedProcessPatterns = @('keepass*','1password*','bitwarden*','lastpass*','dashlane*',
                                     'enpass*','roboform*','nordpass*')
$script:UiBlockedClasses = @(
    'ConsoleWindowClass','CASCADIA_HOSTING_WINDOW_CLASS',   # consoles / Windows Terminal
    'Credential Dialog Xaml Host','CredentialDialogXamlHost' # modern Windows credential prompt
)
# Sensitive Control Panel pages are addressed by CLSID, and CLSIDs never change with the UI language,
# so this catches e.g. Credential Manager or User Accounts in German/Japanese Windows.
$script:UiBlockedShellPaths = @(
    '{1206F5F1-0569-412C-8FEC-3204630DFB70}',  # Credential Manager (Windows / Web credentials)
    '{60632754-C523-4B62-B45C-4172DA012619}'   # User Accounts
)
# Loaders hide their real target in the command line, e.g. "rundll32.exe keymgr.dll,KRShowKeyMgr"
# opens the stored-usernames-and-passwords dialog from a generic rundll32 window.
$script:UiLoaderProcesses = @('rundll32','control','regsvr32','mshta')
$script:UiSensitiveTokens = @('keymgr','credui','vaultcli','dpapimig','credential','password')
# Supplementary heuristic only: these titles are localised, so zh-CN and en-US are covered here while
# every other language relies on the process/class/shell rules above (and UAC on the secure desktop is
# not reachable from a normal desktop session in the first place). The zh-CN entries are locale data
# written as code points so that this file stays pure ASCII.
$script:UiBlockedTitles = @(
    (-join [char[]](0x7528,0x6237,0x8D26,0x6237,0x63A7,0x5236)),   # User Account Control
    'User Account Control',
    (-join [char[]](0x51ED,0x636E)),                               # Credential
    'Credential',
    ('Windows ' + (-join [char[]](0x5B89,0x5168))),                # Windows Security
    'Windows Security'
)
<# User document windows: never type into them or modify them unless -Force is passed. #>
$script:UiDocumentTitlePattern = '\.(txt|md|markdown|docx?|xlsx?|pptx?|pdf|csv|json|ya?ml|xml|ini|cfg|conf|log|sql|db|bak|key|pem|env|c|cpp|h|py|js|ts|html|css|ps1|bat|sh)\b'
$script:UiLogPath = Join-Path $env:TEMP ("codex-uia\" + (Get-Date -Format 'yyyyMMdd') + ".jsonl")
$script:UiTempDir = Split-Path -Parent $script:UiLogPath
$script:UiaRoot = $null
$script:UiShellApp = $null
$script:UiPreexisting = $null

function Initialize-UiKit {
    <# Make the process DPI aware and prepare the log directory (call once per process). #>
    [void][UiKit]::SetProcessDpiAwarenessContext([IntPtr](-4))
    $dir = $script:UiTempDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    <# Persist a baseline snapshot so later CLI invocations can tell which windows already existed. #>
    $base = Join-Path $dir "baseline.json"
    $script:UiPreexisting = New-Object System.Collections.Generic.HashSet[int64]
    if (Test-Path $base) {
        try {
            $data = Get-Content -LiteralPath $base -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($h in $data.handles) { [void]$script:UiPreexisting.Add([int64]$h) }
        } catch { }
    }
    if ($script:UiPreexisting.Count -eq 0) {
        foreach ($h in [UiKit]::TopLevel()) { [void]$script:UiPreexisting.Add([int64]$h) }
        $script:UiPreexisting | ConvertTo-Json -Compress |
            Set-Content -LiteralPath $base -Encoding UTF8
    }
}

function Reset-UiBaseline {
    <# Rebuild the 'pre-existing windows' baseline (call at the start of a new automation run). #>
    $dir = $script:UiTempDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $base = Join-Path $dir "baseline.json"
    $hs = New-Object System.Collections.Generic.HashSet[int64]
    foreach ($h in [UiKit]::TopLevel()) { [void]$hs.Add([int64]$h) }
    $script:UiPreexisting = $hs
    $hs | ConvertTo-Json -Compress | Set-Content -LiteralPath $base -Encoding UTF8
    return $hs.Count
}

function Write-UiLog {
    param([string]$Action, [hashtable]$Data = @{}, [switch]$Quiet)
    $rec = [ordered]@{ t = (Get-Date -Format 'HH:mm:ss.fff'); action = $Action }
    foreach ($k in $Data.Keys) { $rec[$k] = $Data[$k] }
    $json = ($rec | ConvertTo-Json -Compress -Depth 6)
    try { Add-Content -LiteralPath $script:UiLogPath -Value $json -Encoding UTF8 } catch { }
    if (-not $Quiet) { Write-Output $json }
}
function Get-UiLogPath { $script:UiLogPath }
function Get-UiTempDir { $script:UiTempDir }

function Get-UiProcessCommandLine {
    <# Command line of a process. Only called for loader processes, where the target module is not
       reflected in the process name (rundll32 / control / regsvr32 / mshta). #>
    param([Parameter(Mandatory)][int]$ProcessId)
    try {
        $p = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
        return [string]$p.CommandLine
    } catch { }
    return ''
}

function Get-UiShellLocation {
    <# Parsing name of an Explorer window, e.g. '::{26EE0668-...}\9\::{1206F5F1-...}' for a control
       panel page. CLSIDs are identical in every UI language. Returns '' for plain folders / failures. #>
    param([Parameter(Mandatory)][int64]$Handle)
    try {
        if (-not $script:UiShellApp) { $script:UiShellApp = New-Object -ComObject Shell.Application }
        foreach ($w in @($script:UiShellApp.Windows())) {
            try { if ([int64]$w.HWND -eq $Handle) { return [string]$w.Document.Folder.Self.Path } } catch { }
        }
    } catch { }
    return ''
}

function Test-UiSafeName {
    <#
      Pure, locale-independent safety predicate (no handles involved, so it is unit-testable).
      Order matters: process name, window class, loader command line and shell CLSID are language
      independent; window titles are only a supplementary heuristic because they are localised (the
      zh/en strings below cover those two UI languages, every other locale is caught earlier).
    #>
    param([string]$Process = "", [string]$Class = "", [string]$Title = "",
          [string]$CommandLine = "", [string]$ShellPath = "", [switch]$AllowDocument)
    $pname = $Process.ToLower()
    if ($pname -and ($script:UiBlockedProcesses -contains $pname)) {
        return @{ Safe = $false; Rule = 'process'; Reason = "safety policy: refusing to drive terminal/security process $Process" }
    }
    foreach ($pat in $script:UiBlockedProcessPatterns) {
        if ($pname -and ($pname -like $pat)) {
            return @{ Safe = $false; Rule = 'process-pattern'; Reason = "safety policy: refusing to drive password manager $Process" }
        }
    }
    if ($CommandLine) {
        foreach ($tok in $script:UiSensitiveTokens) {
            if ($CommandLine -like "*$tok*") {
                return @{ Safe = $false; Rule = 'command-line'; Reason = "safety policy: refusing to drive a credential/security tool launched via $Process" }
            }
        }
    }
    if ($Class) {
        foreach ($c in $script:UiBlockedClasses) {
            if ($Class -like "*$c*") {
                return @{ Safe = $false; Rule = 'class'; Reason = "safety policy: refusing to drive protected window class $Class" }
            }
        }
    }
    if ($ShellPath) {
        foreach ($clsid in $script:UiBlockedShellPaths) {
            if ($ShellPath -like "*$clsid*") {
                return @{ Safe = $false; Rule = 'shell'; Reason = "safety policy: refusing to drive a sensitive control panel page ($clsid)" }
            }
        }
    }
    if ($Title) {
        foreach ($t in $script:UiBlockedTitles) {
            if ($Title -like "*$t*") {
                return @{ Safe = $false; Rule = 'title'; Reason = 'safety policy: refusing to drive a security/credential dialog' }
            }
        }
        if ($Title -match $script:UiDocumentTitlePattern) {
            if ($AllowDocument) { return @{ Safe = $true; Rule = ''; Reason = '' } }
            return @{ Safe = $false; Rule = 'document'; Reason = "safety policy: looks like a user document window ($Title); pass -Force to override" }
        }
    }
    return @{ Safe = $true; Rule = ''; Reason = '' }
}

function Test-UiSafeTarget {
    <# Resolve the window's process/class/title (plus command line / shell CLSID when needed) and apply
       the locale-independent safety predicate. #>
    param([Parameter(Mandatory)][IntPtr]$Handle, [switch]$AllowDocument)
    if ($Handle -eq [IntPtr]::Zero) { return @{ Safe = $false; Rule = 'handle'; Reason = 'window handle is null' } }
    $pname = ''
    $procId = [UiKit]::PidOf($Handle)
    try { $pname = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { }
    $cls = [UiKit]::ClassOf($Handle)
    $cmd = ''
    if ($pname -and ($script:UiLoaderProcesses -contains $pname.ToLower())) {
        $cmd = Get-UiProcessCommandLine -ProcessId $procId
    }
    $shellPath = ''
    if ($cls -like '*CabinetWClass*' -or $cls -like '*ShellTabWindowClass*') {
        $shellPath = Get-UiShellLocation -Handle ([int64]$Handle)
    }
    return Test-UiSafeName -Process $pname -Class $cls -Title ([UiKit]::TextOf($Handle)) `
                           -CommandLine $cmd -ShellPath $shellPath -AllowDocument:$AllowDocument
}


function Assert-UiSafeToType {
    <# Gate before typing: refuse terminals / security UI / user document windows. -Force relaxes only the
       user document rule; terminals, credential UI and password managers stay blocked. #>
    param([Parameter(Mandatory)][int64]$Window, [switch]$Force)
    $r = Test-UiSafeTarget -Handle ([IntPtr]$Window) -AllowDocument:$Force
    if (-not $r.Safe) { throw $r.Reason }
    return $true
}

function Assert-UiSafeInteract {
    <# Single gate for every real interaction (click / drag / type):
       terminals, consoles, security/credential dialogs, password managers and the Codex/ChatGPT windows are
       always refused. -Force relaxes only the user-document rule. #>
    param([Parameter(Mandatory)][int64]$Window, [switch]$Force)
    $root = [UiKit]::GetAncestor([IntPtr]$Window, 2)
    if ($root -eq [IntPtr]::Zero) { $root = [IntPtr]$Window }
    $r = Test-UiSafeTarget -Handle $root -AllowDocument:$Force
    if (-not $r.Safe) { throw $r.Reason }
    return $true
}

function Assert-UiSafeKeyboard {
    <# Keystrokes land in whatever window has focus, so gate on the foreground window: this refuses to
       type into a terminal, a credential dialog or the Codex window by accident. #>
    param([switch]$Force)
    $fg = [UiKit]::GetForegroundWindow()
    if ($fg -eq [IntPtr]::Zero) { return $true }
    $root = [UiKit]::GetAncestor($fg, 2)
    if ($root -eq [IntPtr]::Zero) { $root = $fg }
    $r = Test-UiSafeTarget -Handle $root -AllowDocument:$Force
    if (-not $r.Safe) {
        throw ("Aborted keyboard input: the focused window is not a safe target (" + $r.Reason +
               "). Bring the target window to the front first (ui.ps1 activate -Window <handle>), or pass -Force for your own document.")
    }
    return $true
}

function Assert-UiSafePoint {
    <# Gate for raw coordinate input (clickxy / drag / wheel). The window that owns the point must not be a
       protected target, otherwise the input would land on it. When an occluder covers the point, the
       intended target (-Window) is raised once and the point is re-checked before giving up. #>
    param([Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y, [int64]$Window = 0,
          [switch]$AllowDocument, [switch]$Force)
    if ($Force) { return $true }
    $r = Get-UiPointOwner -X $X -Y $Y -AllowDocument:$AllowDocument
    if ($r.Safe) { return $true }
    if ($Window -ne 0 -and $r.Handle -ne $Window) {
        [void](Set-UiFocus -Window $Window)
        for ($i = 0; $i -lt 4; $i++) {
            Start-Sleep -Milliseconds 200
            $again = Get-UiPointOwner -X $X -Y $Y -AllowDocument:$AllowDocument
            if ($again.Safe -or $again.Handle -eq $Window) { return $true }
            $r = $again
        }
    }
    throw ("Aborted raw input at ($X,$Y): " + $r.Reason)
}

function Get-UiPointOwner {
    <# Safety verdict for the window under a screen point (used by the raw input gate). #>
    param([Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y, [switch]$AllowDocument)
    $pt = New-Object UiKit+POINT; $pt.X = $X; $pt.Y = $Y
    $under = [UiKit]::WindowFromPoint($pt)
    if ($under -eq [IntPtr]::Zero) { return @{ Safe = $true; Rule = ''; Reason = ''; Handle = 0 } }
    $root = [UiKit]::GetAncestor($under, 2)
    if ($root -eq [IntPtr]::Zero) { $root = $under }
    $r = Test-UiSafeTarget -Handle $root -AllowDocument:$AllowDocument
    return @{ Safe = $r.Safe; Rule = $r.Rule; Reason = $r.Reason; Handle = [int64]$root }
}

function Test-UiPreexisting {
    <# True when the window existed before this session started (i.e. it belongs to the user). #>
    param([Parameter(Mandatory)][int64]$Window)
    if ($null -eq $script:UiPreexisting) { return $false }
    return $script:UiPreexisting.Contains($Window)
}

function Get-UiWindow {
    <# Enumerate top-level windows (filterable): handle/process/class/title/rect/DPI/monitor/foreground/safe. #>
    param([string]$Process, [string]$Title, [string]$Class, [switch]$VisibleOnly,
          [switch]$IncludeChildren, [switch]$NewOnly, [int]$Index = -1)
    $out = New-Object System.Collections.Generic.List[object]
    $i = 0
    foreach ($h in [UiKit]::TopLevel()) {
        $pw = [UiKit]::PidOf($h); $pname = ''
        try { $pname = (Get-Process -Id $pw -ErrorAction Stop).ProcessName } catch { }
        $cls = [UiKit]::ClassOf($h); $txt = [UiKit]::TextOf($h)
        if ($VisibleOnly -and -not [UiKit]::IsWindowVisible($h)) { continue }
        if ($Process -and -not ($pname -like $Process)) { continue }
        if ($Title -and -not ($txt -like $Title)) { continue }
        if ($Class -and -not ($cls -like $Class)) { continue }
        if ($NewOnly -and (Test-UiPreexisting -Window ([int64]$h))) { continue }
        $r = [UiKit]::RectOf($h)
        $mon = [UiKit]::MonitorInfoOf([UiKit]::MonitorFromWindow($h, 2))
        $obj = [pscustomobject]@{
            Handle=[int64]$h; Pid=$pw; Process=$pname; Class=$cls; Title=$txt
            Visible=[UiKit]::IsWindowVisible($h); Enabled=[UiKit]::IsWindowEnabled($h)
            Min=[UiKit]::IsIconic($h); Max=[UiKit]::IsZoomed($h)
            X=$r.Left; Y=$r.Top; W=$r.Width; H=$r.Height
            Dpi=[UiKit]::GetDpiForWindow($h)
            Monitor=@{X=$mon.rcMonitor.Left;Y=$mon.rcMonitor.Top;W=$mon.rcMonitor.Width;H=$mon.rcMonitor.Height}
            Foreground=([UiKit]::GetForegroundWindow() -eq $h)
            PreExisting=(Test-UiPreexisting -Window ([int64]$h))
            Safe=(Test-UiSafeTarget -Handle $h).Safe; Z=$i
        }
        if ($IncludeChildren) { $obj | Add-Member NoteProperty Children (Get-UiTree -Window ([int64]$h)) }
        $out.Add($obj); $i++
    }
    if ($Index -ge 0) { if ($Index -lt $out.Count) { return $out[$Index] } else { return $null } }
    return $out
}

function Get-UiWindowByTitle {
    param([Parameter(Mandatory)][string]$Title, [string]$Process)
    $w = @(Get-UiWindow -Title "*$Title*" -Process $Process -VisibleOnly)
    if ($w.Count -eq 0) { throw "no window whose title contains $Title" }
    return $w[0]
}

function Get-UiFocusedControl {
    <# Focused control via GetGUIThreadInfo (works across processes). #>
    param([Parameter(Mandatory)][int64]$Window)
    $h = [IntPtr]$Window
    $gti = New-Object UiKit+GUITHREADINFO
    $gti.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($gti)
    [void][UiKit]::GetGUIThreadInfo([UiKit]::ThreadOf($h), [ref]$gti)
    if ($gti.hwndFocus -eq [IntPtr]::Zero) { return $null }
    return [pscustomobject]@{ Handle=[int64]$gti.hwndFocus; Id=[UiKit]::GetDlgCtrlID($gti.hwndFocus)
        Class=[UiKit]::ClassOf($gti.hwndFocus); Text=[UiKit]::TextOf($gti.hwndFocus); Window=$Window }
}

function Get-UiTree {
    <# Control tree (default depth 5). #>
    param([Parameter(Mandatory)][int64]$Window, [int]$Depth = 5)
    $items = New-Object System.Collections.Generic.List[object]
    function Walk([IntPtr]$h, [int]$level) {
        foreach ($c in [UiKit]::DirectChildren($h)) {
            $r = [UiKit]::RectOf($c)
            $items.Add([pscustomobject]@{
                Handle=[int64]$c; ControlId=[UiKit]::GetDlgCtrlID($c); Class=[UiKit]::ClassOf($c)
                Text=[UiKit]::TextOf($c); Level=$level
                X=$r.Left; Y=$r.Top; W=$r.Width; H=$r.Height
                Visible=[UiKit]::IsWindowVisible($c); Enabled=[UiKit]::IsWindowEnabled($c) })
            if ($level + 1 -lt $Depth) { Walk $c ($level + 1) }
        }
    }
    Walk ([IntPtr]$Window) 0
    return $items
}

function Resolve-UiTarget {
    <# Resolve a control by -Id / -Class / -Text / -At x,y. #>
    param([Parameter(Mandatory)][int64]$Window, [int]$Id = [int]::MinValue,
          [string]$Class, [string]$Text, [int]$Index = 0, [int[]]$At)
    if ($Id -ne [int]::MinValue) {
        $h = [UiKit]::GetDlgItem([IntPtr]$Window, $Id)
        if ($h -ne [IntPtr]::Zero) { return $h }
        $hit = @(Get-UiTree -Window $Window | Where-Object { $_.ControlId -eq $Id })
        if ($hit.Count -gt $Index) { return [IntPtr]$hit[$Index].Handle }
        throw "no control with ID=$Id inside the window"
    }
    if ($At) { $pt = New-Object UiKit+POINT; $pt.X = $At[0]; $pt.Y = $At[1]; return [UiKit]::WindowFromPoint($pt) }
    if ($Class -or $Text) {
        $cand = @(Get-UiTree -Window $Window | Where-Object {
            (-not $Class -or $_.Class -like $Class) -and (-not $Text -or $_.Text -like "*$Text*") })
        if ($cand.Count -le $Index) { throw "no control matching Class='$Class' Text='$Text'" }
        return [IntPtr]$cand[$Index].Handle
    }
    return [IntPtr]$Window
}


function Set-UiWindowState {
    param([Parameter(Mandatory)][int64]$Window,
          [ValidateSet('normal','min','max','hide','restore')][string]$State = 'normal')
    $map = @{ normal = 1; min = 2; max = 3; hide = 0; restore = 9 }
    [void][UiKit]::ShowWindow([IntPtr]$Window, $map[$State]); Start-Sleep -Milliseconds 200
}
function Set-UiWindowRect {
    param([Parameter(Mandatory)][int64]$Window,[int]$X,[int]$Y,[int]$W,[int]$H,[switch]$Activate)
    $flags = 0x0004; if (-not $Activate) { $flags = $flags -bor 0x0010 }
    [void][UiKit]::SetWindowPos([IntPtr]$Window, [UiKit]::HWND_TOP, $X, $Y, $W, $H, [uint32]$flags)
    Start-Sleep -Milliseconds 200
}
function Set-UiWindowTopMost {
    param([Parameter(Mandatory)][int64]$Window, [switch]$Off)
    $after = if ($Off) { [UiKit]::HWND_NOTOPMOST } else { [UiKit]::HWND_TOPMOST }
    [void][UiKit]::SetWindowPos([IntPtr]$Window, $after, 0, 0, 0, 0, 0x0013)
}
function Set-UiFocus {
    <# Activate a window (optionally focus a control); returns whether it became the foreground window.
       Windows enforces a foreground lock, so a plain SetForegroundWindow is often rejected;
       this falls back step by step: ALT-key trick -> temporary topmost -> AttachThreadInput. #>
    param([Parameter(Mandatory)][int64]$Window, [int64]$Control = 0)
    $h = [IntPtr]$Window
    [void][UiKit]::ShowWindow($h, 9)
    [void][UiKit]::SetForegroundWindow($h)
    [void][UiKit]::BringWindowToTop($h)
    Start-Sleep -Milliseconds 150
    if ([UiKit]::GetForegroundWindow() -ne $h) {
        # 1) Send a dummy ALT keystroke to release the foreground lock, then retry
        [void][UiKit]::Send(@([UiKit]::KeyInput(0x12, $false), [UiKit]::KeyInput(0x12, $true)))
        Start-Sleep -Milliseconds 80
        [void][UiKit]::SetForegroundWindow($h)
        Start-Sleep -Milliseconds 200
    }
    if ([UiKit]::GetForegroundWindow() -ne $h) {
        # 2) Temporarily go topmost to force the window forward, then restore the Z order
        [void][UiKit]::SetWindowPos($h, [UiKit]::HWND_TOPMOST, 0, 0, 0, 0, 0x0013)
        [void][UiKit]::SetForegroundWindow($h)
        Start-Sleep -Milliseconds 200
        [void][UiKit]::SetWindowPos($h, [UiKit]::HWND_NOTOPMOST, 0, 0, 0, 0, 0x0013)
        Start-Sleep -Milliseconds 120
    }
    if ([UiKit]::GetForegroundWindow() -ne $h) {
        # 3) Attach to the foreground thread's input queue and steal focus
        $fg = [UiKit]::GetForegroundWindow()
        $tf = [UiKit]::ThreadOf($fg); $me = [UiKit]::GetCurrentThreadId()
        if ($tf -ne $me -and $tf -ne 0) {
            [void][UiKit]::AttachThreadInput($me, $tf, $true)
            [void][UiKit]::SetForegroundWindow($h)
            [void][UiKit]::AttachThreadInput($me, $tf, $false)
            Start-Sleep -Milliseconds 180
        }
    }
    if ($Control -ne 0) {
        $c = [IntPtr]$Control
        $t1 = [UiKit]::ThreadOf($h); $t2 = [UiKit]::ThreadOf($c); $me = [UiKit]::GetCurrentThreadId()
        if ($t2 -ne $me) { [void][UiKit]::AttachThreadInput($me, $t2, $true) }
        if ($t1 -ne $me) { [void][UiKit]::AttachThreadInput($me, $t1, $true) }
        [void][UiKit]::SetFocus($c)
        if ($t1 -ne $me) { [void][UiKit]::AttachThreadInput($me, $t1, $false) }
        if ($t2 -ne $me) { [void][UiKit]::AttachThreadInput($me, $t2, $false) }
    }
    Start-Sleep -Milliseconds 220
    return ([UiKit]::GetForegroundWindow() -eq $h)
}

function Assert-UiForeground {
    <# Ensure the window is foreground and focused (with retries); throw instead of typing into nowhere. #>
    param([Parameter(Mandatory)][int64]$Window, [int64]$Control = 0, [int]$Retries = 3)
    for ($i = 0; $i -lt $Retries; $i++) {
        if (Set-UiFocus -Window $Window -Control $Control) { return $true }
        Start-Sleep -Milliseconds 250
    }
    throw "could not bring window $Window to the foreground; typing would go astray"
}

# ------------------------------------------------------------------ real mouse
function Move-UiMouse {
    param([Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y, [int]$Ms = 0)
    if ($Ms -le 0) { [void][UiKit]::SetCursorPos($X, $Y); Start-Sleep -Milliseconds 40; return }
    $p = New-Object UiKit+POINT; [void][UiKit]::GetCursorPos([ref]$p)
    $steps = [Math]::Max(2, [int]($Ms / 12))
    for ($i = 1; $i -le $steps; $i++) {
        [void][UiKit]::SetCursorPos([int]($p.X + ($X - $p.X) * $i / $steps), [int]($p.Y + ($Y - $p.Y) * $i / $steps))
        Start-Sleep -Milliseconds 12
    }
}

function Invoke-UiMouseButton {
    param([ValidateSet('left','right','middle')][string]$Button = 'left',
          [ValidateSet('down','up','click','double')][string]$Kind = 'click',
          [int]$X = [int]::MinValue, [int]$Y = [int]::MinValue, [int64]$Window = 0, [switch]$Force)
    if ($X -ne [int]::MinValue) { [void](Assert-UiSafePoint -X $X -Y $Y -Window $Window -AllowDocument -Force:$Force) }
    if ($X -ne [int]::MinValue) { [void][UiKit]::SetCursorPos($X, $Y); Start-Sleep -Milliseconds 70 }
    $d = @{ left = 0x0002; right = 0x0008; middle = 0x0020 }[$Button]
    $u = @{ left = 0x0004; right = 0x0010; middle = 0x0040 }[$Button]
    switch ($Kind) {
        'down'   { [void][UiKit]::Send(@([UiKit]::MouseInput([uint32]$d,0,0,0))) }
        'up'     { [void][UiKit]::Send(@([UiKit]::MouseInput([uint32]$u,0,0,0))) }
        'click'  { [void][UiKit]::Send(@([UiKit]::MouseInput([uint32]$d,0,0,0),[UiKit]::MouseInput([uint32]$u,0,0,0))) }
        'double' {
            [void][UiKit]::Send(@([UiKit]::MouseInput([uint32]$d,0,0,0),[UiKit]::MouseInput([uint32]$u,0,0,0)))
            Start-Sleep -Milliseconds 90
            [void][UiKit]::Send(@([UiKit]::MouseInput([uint32]$d,0,0,0),[UiKit]::MouseInput([uint32]$u,0,0,0))) }
    }
    Start-Sleep -Milliseconds 130
}

function Invoke-UiDrag {
    <# Real drag (right-button drag, interpolated path, initial hold). #>
    param([Parameter(Mandatory)][int]$X1,[Parameter(Mandatory)][int]$Y1,
          [Parameter(Mandatory)][int]$X2,[Parameter(Mandatory)][int]$Y2,
          [int]$Steps = 24,[ValidateSet('left','right')][string]$Button = 'left',[int]$HoldMs = 200,
          [int64]$Handle = 0, [switch]$Force)
    [void](Assert-UiSafePoint -X $X1 -Y $Y1 -Window $Handle -AllowDocument -Force:$Force)
    if ($Handle -ne 0) { Assert-UiPointOwned -X $X1 -Y $Y1 -Handle $Handle -Retries 1 }
    [void][UiKit]::SetCursorPos($X1, $Y1); Start-Sleep -Milliseconds $HoldMs
    $d = @{ left = 0x0002; right = 0x0008 }[$Button]
    $u = @{ left = 0x0004; right = 0x0010 }[$Button]
    [void][UiKit]::Send(@([UiKit]::MouseInput([uint32]$d,0,0,0)))
    Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le $Steps; $i++) {
        [void][UiKit]::SetCursorPos([int]($X1 + ($X2-$X1)*$i/$Steps), [int]($Y1 + ($Y2-$Y1)*$i/$Steps))
        Start-Sleep -Milliseconds 16
    }
    Start-Sleep -Milliseconds 160
    [void][UiKit]::Send(@([UiKit]::MouseInput([uint32]$u,0,0,0)))
    Start-Sleep -Milliseconds 150
}

function Invoke-UiWheel {
    param([int]$X = [int]::MinValue,[int]$Y = [int]::MinValue,[int]$Delta = -360,[switch]$Horizontal,
          [int64]$Window = 0,[switch]$Force)
    if ($X -ne [int]::MinValue) { [void](Assert-UiSafePoint -X $X -Y $Y -Window $Window -AllowDocument -Force:$Force) }
    if ($X -ne [int]::MinValue) { [void][UiKit]::SetCursorPos($X, $Y); Start-Sleep -Milliseconds 90 }
    $flag = if ($Horizontal) { 0x1000 } else { 0x0800 }
    [void][UiKit]::Send(@([UiKit]::MouseInput([uint32]$flag, 0, 0, $Delta)))
    Start-Sleep -Milliseconds 220
}

function Get-UiCursor { $p = New-Object UiKit+POINT; [void][UiKit]::GetCursorPos([ref]$p); return @{ X = $p.X; Y = $p.Y } }

# ------------------------------------------------------------------ real keyboard
$script:UiKeyMap = @{
    'ENTER'=0x0D;'RETURN'=0x0D;'TAB'=0x09;'ESC'=0x1B;'ESCAPE'=0x1B;'SPACE'=0x20;'BACKSPACE'=0x08;'BACK'=0x08
    'DELETE'=0x2E;'DEL'=0x2E;'INSERT'=0x2D;'INS'=0x2D;'HOME'=0x24;'END'=0x23;'PAGEUP'=0x21;'PGUP'=0x21
    'PAGEDOWN'=0x22;'PGDN'=0x22;'UP'=0x26;'DOWN'=0x28;'LEFT'=0x25;'RIGHT'=0x27;'APPS'=0x5D
    'F1'=0x70;'F2'=0x71;'F3'=0x72;'F4'=0x73;'F5'=0x74;'F6'=0x75;'F7'=0x76;'F8'=0x77;'F9'=0x78;'F10'=0x79
    'F11'=0x7A;'F12'=0x7B;'NUMLOCK'=0x90;'CAPSLOCK'=0x14;'PRINTSCREEN'=0x2C
    # Punctuation needs explicit OEM codes: a bare "-" would map to its ASCII value (0x2D = INSERT) and hit the wrong key.
    'OEM_MINUS'=0xBD;'MINUS'=0xBD;'OEM_PLUS'=0xBB;'PLUS'=0xBB;'OEM_COMMA'=0xBC;'OEM_PERIOD'=0xBE
    'OEM_1'=0xBA;'OEM_2'=0xBF;'OEM_3'=0xC0;'OEM_4'=0xDB;'OEM_5'=0xDC;'OEM_6'=0xDD;'OEM_7'=0xDE
    'SHIFT'=0x10;'CTRL'=0x11;'CONTROL'=0x11;'ALT'=0x12
    # Windows keys double as modifiers (WIN+D show desktop, WIN+E explorer, WIN+R run) so that shell-level
    # shortcuts are reachable without leaving this engine.
    'WIN'=0x5B;'LWIN'=0x5B;'RWIN'=0x5C;'MENU'=0x5D
}

function Send-UiKeys {
    <# Key chords / sequences, e.g. "CTRL+SHIFT+S", "ENTER", "CTRL+A, DELETE". #>
    param([Parameter(Mandatory)][string]$Keys, [int]$GapMs = 30, [switch]$Force)
    [void](Assert-UiSafeKeyboard -Force:$Force)
    foreach ($combo in ($Keys -split ',')) {
        $c = $combo.Trim(); if ($c -eq '') { continue }
        $parts = $c.ToUpper() -split '\+'
        $mods = @(); $keys = @()
        foreach ($p in $parts) { if ($p -in @('CTRL','CONTROL','SHIFT','ALT','WIN','LWIN','RWIN','MENU')) { $mods += $p } else { $keys += $p } }
        $inputs = New-Object System.Collections.Generic.List[object]
        foreach ($m in $mods) { $inputs.Add([UiKit]::KeyInput([uint16]$script:UiKeyMap[$m], $false)) }
        foreach ($k in $keys) {
            $vk = if ($script:UiKeyMap.ContainsKey($k)) { [uint16]$script:UiKeyMap[$k] }
                  elseif ($k.Length -eq 1) { [uint16][char]$k } else { throw "unrecognised key: $k" }
            $inputs.Add([UiKit]::KeyInput($vk, $false)); $inputs.Add([UiKit]::KeyInput($vk, $true))
            Start-Sleep -Milliseconds $GapMs
        }
        for ($i = $mods.Count - 1; $i -ge 0; $i--) { $inputs.Add([UiKit]::KeyInput([uint16]$script:UiKeyMap[$mods[$i]], $true)) }
        $arr = $inputs.ToArray()
        $sent = [UiKit]::Send($arr)
        if ($sent -ne $arr.Length) { throw "SendInput(keys) sent only $sent/$($arr.Length) events" }
        Start-Sleep -Milliseconds 130
    }
}

function Send-UiText {
    <#
      Type text. Default path is clipboard + Ctrl+V:
        - it bypasses IME composition (measured: raw ASCII input turns into repeated digits under a CJK IME);
        - long text is nearly instant, an order of magnitude faster than per-character input.
      The cost is a temporary clipboard takeover (text content is restored afterwards).
      Use -Raw to send Unicode characters one by one when the clipboard must not be touched; a CJK IME may interfere with mixed text.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [switch]$Raw, [switch]$Force)
    [void](Assert-UiSafeKeyboard -Force:$Force)
    if (-not $Raw) {
        $old = Get-UiClipboard
        Set-UiClipboard -Text $Text
        Send-UiKeys -Keys 'CTRL+V' -Force:$Force
        Start-Sleep -Milliseconds 300
        if ($null -ne $old) { Set-UiClipboard -Text $old } else { Set-UiClipboard -Text '' }
        return
    }
    $batch = New-Object System.Collections.Generic.List[object]
    foreach ($ch in $Text.ToCharArray()) {
        $batch.Add([UiKit]::UniInput($ch, $false)); $batch.Add([UiKit]::UniInput($ch, $true))
        if ($batch.Count -ge 160) { [void][UiKit]::Send($batch.ToArray()); $batch.Clear(); Start-Sleep -Milliseconds 15 }
    }
    if ($batch.Count -gt 0) { [void][UiKit]::Send($batch.ToArray()) }
    Start-Sleep -Milliseconds 130
}

# ------------------------------------------------------------------ message-level control
function Get-UiText {
    param([Parameter(Mandatory)][int64]$Handle)
    $h = [IntPtr]$Handle
    $len = [int][UiKit]::SendMessage($h, 0x000E, [IntPtr]::Zero, [IntPtr]::Zero)
    $sb = New-Object System.Text.StringBuilder ([Math]::Max(64, $len + 2))
    [void][UiKit]::SendMessageGetText($h, 0x000D, [IntPtr]$sb.Capacity, $sb)
    return $sb.ToString()
}
function Set-UiText {
    <# WM_SETTEXT; gated like real typing so the message path cannot bypass the safety policy. #>
    param([Parameter(Mandatory)][int64]$Handle,[Parameter(Mandatory)][AllowEmptyString()][string]$Text,
          [switch]$Force)
    [void](Assert-UiSafeInteract -Window ([int64]$Handle) -Force:$Force)
    [void][UiKit]::SendMessageText([IntPtr]$Handle, 0x000C, [IntPtr]::Zero, $Text)
    Start-Sleep -Milliseconds 80
    return (Get-UiText -Handle $Handle)
}
function Invoke-UiCommand {
    <# Post WM_COMMAND (menu/button command id); notification code 1 mimics a keyboard shortcut. #>
    param([Parameter(Mandatory)][int64]$Window,[Parameter(Mandatory)][int]$CommandId,[int]$Notify = 0,
          [switch]$Force)
    [void](Assert-UiSafeInteract -Window ([int64]$Window) -Force:$Force)
    <# WM_COMMAND carries the id in the low word and the notification code in the high word. #>
    $w = [IntPtr](($Notify * 65536) + $CommandId)
    [void][UiKit]::PostMessage([IntPtr]$Window, 0x0111, $w, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 150
}
function Invoke-UiClick {
    <# Click a control: real mouse click by default, -Message uses BM_CLICK (no mouse involved). #>
    param([Parameter(Mandatory)][int64]$Handle,[switch]$Message,
          [ValidateSet('left','right','middle')][string]$Button='left',[switch]$Double,[switch]$Force)
    $h = [IntPtr]$Handle
    if ($Message) { [void](Assert-UiSafeInteract -Window ([int64]$h) -Force:$Force)
                    [void][UiKit]::PostMessage($h, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero); Start-Sleep -Milliseconds 180; return }
    [void](Assert-UiSafeInteract -Window ([int64]$h) -Force:$Force)
    $r = [UiKit]::RectOf($h)
    if ($r.Width -le 0 -or $r.Height -le 0) { throw "control has no visible area; cannot click it" }
    $x = [int](($r.Left + $r.Right) / 2); $y = [int](($r.Top + $r.Bottom) / 2)
    Assert-UiPointOwned -X $x -Y $y -Handle $h
    $rw = [UiKit]::GetAncestor($h, 2); if ($rw -eq [IntPtr]::Zero) { $rw = $h }
    Invoke-UiMouseButton -Button $Button -Kind $(if ($Double) {'double'} else {'click'}) -X $x -Y $y -Window ([int64]$rw) -Force:$Force
    return @{ X = $x; Y = $y }
}

function Assert-UiPointOwned {
    <# Landing-point check before any real input: the window under the target point must belong to the target,
       otherwise the click would land on whatever window covers it.
       It first tries to raise the target, then aborts with an error instead of clicking blindly. #>
    param([Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y,
          [Parameter(Mandatory)][int64]$Handle, [int]$Retries = 2)
    $target = [UiKit]::GetAncestor([IntPtr]$Handle, 2)     # GA_ROOT
    if ($target -eq [IntPtr]::Zero) { $target = [IntPtr]$Handle }
    for ($i = 0; $i -le $Retries; $i++) {
        $pt = New-Object UiKit+POINT; $pt.X = $X; $pt.Y = $Y
        $under = [UiKit]::WindowFromPoint($pt)
        $root = [UiKit]::GetAncestor($under, 2)
        if ($root -eq $target) { return $true }
        if ($i -lt $Retries) {
            [void](Set-UiFocus -Window ([int64]$target))
            Start-Sleep -Milliseconds 250
        }
    }
    $underName = ''
    try { $underName = (Get-Process -Id ([UiKit]::PidOf($under)) -ErrorAction Stop).ProcessName +
                       " / " + [UiKit]::TextOf($root) } catch { }
    throw ("Aborted the real click: another window occupies the landing point ($X,$Y is $underName). " +
           "Bring the target window to the front first, or use -Message for a message-level click.")
}
function Set-UiCheck {
    param([Parameter(Mandatory)][int64]$Handle,[bool]$Checked = $true)
    [void][UiKit]::SendMessage([IntPtr]$Handle, 0x00F1, [IntPtr]([int]$Checked), [IntPtr]::Zero)
    Start-Sleep -Milliseconds 80
}
function Get-UiCheck { param([Parameter(Mandatory)][int64]$Handle)
    return [int][UiKit]::SendMessage([IntPtr]$Handle, 0x00F0, [IntPtr]::Zero, [IntPtr]::Zero) }
function Set-UiComboSelect {
    param([Parameter(Mandatory)][int64]$Handle,[Parameter(Mandatory)][int]$Index)
    [void][UiKit]::SendMessage([IntPtr]$Handle, 0x014E, [IntPtr]$Index, [IntPtr]::Zero); Start-Sleep -Milliseconds 100
}
function Get-UiComboInfo {
    param([Parameter(Mandatory)][int64]$Handle)
    return @{ Count=[int][UiKit]::SendMessage([IntPtr]$Handle,0x0146,[IntPtr]::Zero,[IntPtr]::Zero)
              Selected=[int][UiKit]::SendMessage([IntPtr]$Handle,0x0147,[IntPtr]::Zero,[IntPtr]::Zero) }
}
function Get-UiTabInfo {
    param([Parameter(Mandatory)][int64]$Handle)
    return @{ Count=[int][UiKit]::SendMessage([IntPtr]$Handle,0x1304,[IntPtr]::Zero,[IntPtr]::Zero)
              Selected=[int][UiKit]::SendMessage([IntPtr]$Handle,0x130B,[IntPtr]::Zero,[IntPtr]::Zero) }
}
function Set-UiTabSelect {
    <# Click a tab header with a real click so TCN_SELCHANGE fires; -TabWidth overrides the tab width. #>
    param([Parameter(Mandatory)][int64]$Handle,[Parameter(Mandatory)][int]$Index,[int]$TabWidth = 110)
    $h = [IntPtr]$Handle; $r = [UiKit]::RectOf($h)
    $scale = [UiKit]::GetDpiForWindow($h) / 96.0
    $x = [int]($r.Left + $TabWidth * $scale * $Index + $TabWidth * $scale / 2)
    $y = [int]($r.Top + 14 * $scale)
    $rw = [UiKit]::GetAncestor($h, 2); if ($rw -eq [IntPtr]::Zero) { $rw = $h }
    Invoke-UiMouseButton -Kind 'click' -X $x -Y $y -Window ([int64]$rw)
    Start-Sleep -Milliseconds 200
}
function Get-UiListInfo {
    <# ListView/ListBox summary: row count + current selection (use UIA for details). #>
    param([Parameter(Mandatory)][int64]$Handle)
    $h = [IntPtr]$Handle; $cls = [UiKit]::ClassOf($h)
    if ($cls -like 'SysListView32*') {
        return @{ Kind='ListView'; Count=[int][UiKit]::SendMessage($h,0x1004,[IntPtr]::Zero,[IntPtr]::Zero)
                  Selected=[int][UiKit]::SendMessage($h,0x100C,[IntPtr](-1),[IntPtr]2) }
    }
    return @{ Kind='Unknown'; Count=$null; Selected=$null }
}

# ------------------------------------------------------------------ clipboard
function Get-UiClipboard { try { return (Get-Clipboard -Raw -ErrorAction Stop) } catch { return $null } }
function Set-UiClipboard {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    try { Set-Clipboard -Value $Text -ErrorAction Stop } catch { throw "clipboard write failed: $($_.Exception.Message)" }
}

# ------------------------------------------------------------------ screenshots
function Remove-UiTempPath {
    <#
      Best-effort delete that retries: a helper killed a moment ago can still hold the handles of its own
      log files, and a picture that is already gone must not turn into an error.
    #>
    param([Parameter(Mandatory)][string]$Path, [switch]$Tree)
    for ($i = 0; $i -lt 5; $i++) {
        try { if ($Tree) { [IO.Directory]::Delete($Path, $true) } else { [IO.File]::Delete($Path) } } catch { }
        if (-not (Test-Path -LiteralPath $Path)) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return (-not (Test-Path -LiteralPath $Path))
}

function Save-UiShot {
    <# Screenshot: -Window / -Monitor n / -Region x,y,w,h; -Print uses PrintWindow; -Cursor overlays the cursor.
       The frame is always captured whole and at full resolution: -MaxWidth is the only thing that can make it
       smaller, and only because a caller asked for that in so many words. #>
    param([string]$Out,[int64]$Window = 0,[int]$Monitor = -1,[int[]]$Region,
          [switch]$Print,[switch]$Cursor,[int]$MaxWidth = 0,[int]$DelayMs = 0)
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
    Add-Type -AssemblyName System.Drawing
    if ($Monitor -ge 0) {
        $mons = [UiKit]::Monitors()
        if ($Monitor -ge $mons.Count) { throw "monitor index out of range (found $($mons.Count))" }
        $mi = [UiKit]::MonitorInfoOf($mons[$Monitor])
        $x=$mi.rcMonitor.Left; $y=$mi.rcMonitor.Top; $w=$mi.rcMonitor.Width; $h=$mi.rcMonitor.Height
    } elseif ($Region) { $x=$Region[0]; $y=$Region[1]; $w=$Region[2]; $h=$Region[3] }
    elseif ($Window -ne 0) { $r=[UiKit]::RectOf([IntPtr]$Window); $x=$r.Left; $y=$r.Top; $w=$r.Width; $h=$r.Height }
    else { $x=0; $y=0; $w=[UiKit]::GetSystemMetrics(0); $h=[UiKit]::GetSystemMetrics(1) }
    if ($w -le 0 -or $h -le 0) { throw "invalid capture area: ${w}x${h}" }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    if ($Print -and $Window -ne 0) {
        $hdc = $g.GetHdc(); [void][UiKit]::PrintWindow([IntPtr]$Window, $hdc, 2); $g.ReleaseHdc($hdc)
    } else {
        $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $w, $h))
    }
    if ($Cursor) {
        $ci = New-Object UiKit+CURSORINFO
        $ci.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($ci)
        if ([UiKit]::GetCursorInfo([ref]$ci)) {
            $ic = [UiKit]::CopyIcon($ci.hCursor); $hdc2 = $g.GetHdc()
            [void][UiKit]::DrawIconEx($hdc2, $ci.ptScreenPos.X - $x, $ci.ptScreenPos.Y - $y, $ic, 0, 0, 0, [IntPtr]::Zero, 3)
            $g.ReleaseHdc($hdc2); [void][UiKit]::DestroyIcon($ic)
        }
    }
    $g.Dispose()
    if ($MaxWidth -gt 0 -and $w -gt $MaxWidth) {
        $nw = $MaxWidth; $nh = [int]($h * $MaxWidth / $w)
        $small = New-Object System.Drawing.Bitmap $nw, $nh
        $g2 = [System.Drawing.Graphics]::FromImage($small)
        $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g2.DrawImage($bmp, 0, 0, $nw, $nh); $g2.Dispose(); $bmp.Dispose(); $bmp = $small
    }
    if (-not $Out) { $Out = Join-Path $script:UiTempDir ("uia-shot-" + (Get-Date -Format 'HHmmss') + ".png") }
    $dir = Split-Path -Parent $Out
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return $Out
}

function Test-UiShotBlank {
    <# Detect a blank capture (PrintWindow returns black/white for some composited windows). #>
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.Drawing
    $bmp = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        $first = $bmp.GetPixel(2, 2).ToArgb()
        $same = 0; $total = 0
        for ($x = 2; $x -lt $bmp.Width; $x += [Math]::Max(1, [int]($bmp.Width / 24))) {
            for ($y = 2; $y -lt $bmp.Height; $y += [Math]::Max(1, [int]($bmp.Height / 24))) {
                $total++
                if ($bmp.GetPixel($x, $y).ToArgb() -eq $first) { $same++ }
            }
        }
        return ($total -gt 0 -and ($same / $total) -gt 0.97)
    } finally { $bmp.Dispose() }
}

function Save-UiShotSmart {
    <# Smart capture: screen grab for the foreground window; when occluded try PrintWindow, then raise and re-grab if blank. #>
    param([Parameter(Mandatory)][string]$Out, [Parameter(Mandatory)][int64]$Window,
          [int64]$Control = 0, [switch]$Cursor, [int]$MaxWidth = 0, [switch]$NoActivate)
    $target = if ($Control -ne 0) { $Control } else { $Window }
    $fg = [UiKit]::GetForegroundWindow()
    $isForeground = ($fg -eq [IntPtr]$Window)
    $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(),
            ("uia-probe-" + [Guid]::NewGuid().ToString('N') + ".png"))
    if (-not $isForeground) {
        [void](Save-UiShot -Out $tmp -Window $target -Print)
        $blank = $true
        try { $blank = Test-UiShotBlank -Path $tmp } catch { $blank = $true }
        [void](Remove-UiTempPath -Path $tmp)
        if (-not $blank) {
            <# PrintWindow returned real content: use it and leave the user's focus untouched. #>
            return (Save-UiShot -Out $Out -Window $target -Print -Cursor:$Cursor -MaxWidth $MaxWidth)
        }
        if (-not $NoActivate) {
            <#
              PrintWindow returns nothing for these windows (common with custom-drawn/composited UI).
              Instead of stealing focus: temporarily go topmost, take a screen grab, then restore the Z order.
              That yields real pixels without displacing the window the user is working in.
            #>
            [void][UiKit]::SetWindowPos([IntPtr]$Window, [UiKit]::HWND_TOPMOST, 0, 0, 0, 0, 0x0013)
            Start-Sleep -Milliseconds 320
            $fgNow = [UiKit]::GetForegroundWindow()
            $shot = Save-UiShot -Out $Out -Window $target -Cursor:$Cursor -MaxWidth $MaxWidth
            [void][UiKit]::SetWindowPos([IntPtr]$Window, [UiKit]::HWND_NOTOPMOST, 0, 0, 0, 0, 0x0013)
            if ($fgNow -ne [IntPtr]$Window) {
                Write-UiLog 'shot-occluded' @{ window=$Window; note='target occluded: captured via temporary topmost (focus untouched)' } -Quiet
            }
            return $shot
        }
    }
    return (Save-UiShot -Out $Out -Window $target -Cursor:$Cursor -MaxWidth $MaxWidth)
}

# ------------------------------------------------- conversation size (the 413 guard)
<#
  Why this exists
  ---------------------------------------------------------------------------------------------
  Every image the model reads is stored in the conversation and re-sent, byte for byte, on every
  later request, so the body only grows. DeepSeek's gateway (openresty) buffers the whole JSON body
  and rejects anything above ~50 MB (measured boundary: 48 MiB accepted, 51 MB rejected) with

      413 Payload Too Large: Failed to buffer the request body: length limit exceeded

  and that ends the run: the history can never shrink back under the limit, so every later request
  fails too. Deleting the file from disk does not help either - those bytes are already in history.

  Nothing client side can prune that history, so no picture ever enters it. Every capture is a
  full-resolution PNG handed to an out-of-band reader (`look`) that returns text and deletes the file
  the moment the answer is in hand - the same split native Computer Use uses, where the harness looks
  at the screen and only observations reach the conversation. On top of that `budget` reports the live
  conversation size (the newest session rollout tail, i.e. what follows the last compaction, which is
  what the client actually sends again) and every shot still waiting on disk.
#>
$script:UiPlanProbeSeconds = 3       # cache for the rollout probe
$script:UiBodyCacheBytes   = [int64]0
$script:UiBodyCacheTime    = [datetime]::MinValue
$script:UiCodexExe         = $null

function Get-UiSessionBodyBytes {
    <#
      Size of the current conversation: the newest session rollout written in the last while is the
      session being driven (the client appends to it as the turn runs). Returns 0 when unknown.
      After a compaction only what follows the last 'compacted' item is still sent, so that tail is what
      gets measured - otherwise a long session would keep looking huge after Codex already trimmed it.
    #>
    param([int]$MaxAgeSeconds = 1800)
    if (((Get-Date) - $script:UiBodyCacheTime).TotalSeconds -lt $script:UiPlanProbeSeconds) { return $script:UiBodyCacheBytes }
    $bytes = [int64]0
    try {
        $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
        $rootIn = Join-Path $codexHome 'sessions'
        foreach ($day in @((Get-Date), (Get-Date).AddDays(-1))) {
            $dir = Join-Path $rootIn (Join-Path $day.ToString('yyyy') (Join-Path $day.ToString('MM') $day.ToString('dd')))
            if (-not (Test-Path -LiteralPath $dir)) { continue }
            $f = @(Get-ChildItem -LiteralPath $dir -Filter 'rollout-*.jsonl' -File -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1)
            if ($f.Count -gt 0 -and ((Get-Date) - $f[0].LastWriteTime).TotalSeconds -le $MaxAgeSeconds) {
                $bytes = Get-UiLiveBodyBytes -Path $f[0].FullName
                break
            }
        }
    } catch { $bytes = [int64]0 }
    $script:UiBodyCacheBytes = $bytes
    $script:UiBodyCacheTime = Get-Date
    return $bytes
}

function Get-UiLiveBodyBytes {
    <# Bytes the client would actually send again: everything after the last compaction marker. #>
    param([Parameter(Mandatory)][string]$Path)
    $len = (Get-Item -LiteralPath $Path).Length
    $window = [Math]::Min(262144, $len)
    if ($window -le 0) { return [int64]0 }
    try {
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            [void]$fs.Seek($len - $window, [IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] $window
            $read = $fs.Read($buf, 0, $window)
            $text = [Text.Encoding]::UTF8.GetString($buf, 0, $read)
            $idx = $text.LastIndexOf('"type":"compacted"')
            if ($idx -ge 0) { return [int64]($window - $idx) }
        } finally { $fs.Dispose() }
    } catch { }
    return [int64]$len
}

function Format-UiReadAdvice {
    <#
      The one line every capture prints: how to read it. There is exactly one read path - `look` hands
      the full-resolution file to a throw-away Codex run, brings back text only and deletes the picture
      right after. A UI capture is never read with view_image: those bytes would then be re-sent in
      every later request for the rest of the run.
    #>
    param([string]$Path = '')
    $p = if ($Path) { $Path } else { '<path>' }
    return ("read: look -Path `"$p`" -Ask `"what you need to know`"   (full-resolution out-of-band read: " +
            "text comes back and the picture is deleted right after, so it never enters this conversation " +
            "and never occupies space - never view_image a UI capture)")
}

function Invoke-UiShotWithPlan {
    <#
      The one capture entry point, so every caller behaves identically:
        * a full-resolution PNG - same pixels, same frame, never cropped, downscaled or re-encoded;
        * its size and dimensions, so the caller can print the out-of-band read line for it.
    #>
    param([string]$Out = '', [int64]$Window = 0, [int]$Monitor = -1, [int[]]$Region,
          [switch]$Print, [switch]$Cursor, [int]$MaxWidth = 0)
    if (-not $Out) {
        $Out = Join-Path $script:UiTempDir ("uia-shot-" + (Get-Date -Format 'HHmmss') + ".png")
    }
    if ($Window -ne 0 -and -not $Region -and $Monitor -lt 0 -and -not $Print) {
        $p = Save-UiShotSmart -Out $Out -Window $Window -Cursor:$Cursor -MaxWidth $MaxWidth
    } else {
        $p = Save-UiShot -Out $Out -Window $Window -Monitor $Monitor -Region $Region -Cursor:$Cursor -Print:$Print -MaxWidth $MaxWidth
    }
    $img = [System.Drawing.Image]::FromFile($p)
    $dims = "$($img.Width)x$($img.Height)"
    $img.Dispose()
    $bytes = (Get-Item -LiteralPath $p).Length
    return [pscustomobject]@{ Image = $p; Out = $Out; Bytes = $bytes; Dimensions = $dims }
}

# ------------------------------------------------- out-of-band image reads (the `look` path)
<#
  The read path that costs this conversation nothing: a throw-away Codex run opens the full-resolution
  file, answers the question about it, and the picture is deleted as soon as the answer is in hand - no
  session files kept, no image bytes added here. This is the only way a shot is read: a capture is
  never handed to view_image, because those bytes would stay in the conversation for good.
#>

function Get-UiCodexExe {
    <# The Codex CLI used for out-of-band image reads (same config, same model, same vision). #>
    if ($script:UiCodexExe) { return $script:UiCodexExe }
    $cands = @()
    if ($env:CODEX_CLI_PATH) { $cands += $env:CODEX_CLI_PATH }
    $bin = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    if (Test-Path -LiteralPath $bin) {
        $cands += @(Get-ChildItem -LiteralPath $bin -Directory -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | ForEach-Object { Join-Path $_.FullName 'codex.exe' })
    }
    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { $cands += $cmd.Source }
    foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { $script:UiCodexExe = $c; return $c } }
    return $null
}

function Invoke-UiLook {
    <#
      Look at a screenshot out of band and bring back TEXT.
      A throw-away `codex exec --ephemeral` run receives the full-resolution file (-i: no crop, no
      downscale, no re-encode), answers the question, and persists no session files. The picture is
      deleted the moment the read is over (answer or failure), so nothing accumulates: neither on disk
      nor in this conversation. Only -Keep spares it. Returns
      @{ Ok; Answer; Deleted; Kept; Seconds; Path; Error }.
    #>
    param([Parameter(Mandatory)][string]$Path, [string]$Ask = 'Describe what is visible and read out the text that matters.',
          [switch]$Keep, [int]$TimeoutSec = 240)
    if (-not (Test-Path -LiteralPath $Path)) { throw "image not found: $Path" }
    $exe = Get-UiCodexExe
    if (-not $exe) {
        return [pscustomobject]@{ Ok = $false; Answer = ''; Deleted = $false; Seconds = 0; Path = $Path; Kept = $false
                                  Error = 'codex CLI not found - set CODEX_CLI_PATH or install Codex' }
    }
    $full = (Resolve-Path -LiteralPath $Path).Path
    $dir = Join-Path $script:UiTempDir ("look-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Force $dir | Out-Null
    $promptFile = Join-Path $dir 'prompt.txt'
    $answerFile = Join-Path $dir 'answer.txt'
    $stdoutFile = Join-Path $dir 'stdout.txt'
    $stderrFile = Join-Path $dir 'stderr.txt'
    @"
You are looking at one screenshot on behalf of another agent.
Use only the attached image. Do not run commands, do not read or change any file, do not ask questions.
Answer in plain text, concise (a few lines at most), and only with what you can actually see - say that
something is unreadable instead of guessing.
$Ask
"@ | Set-Content -LiteralPath $promptFile -Encoding UTF8
    $q = { param($s) '"' + $s + '"' }
    $argList = @('exec', '--ephemeral', '--skip-git-repo-check', '-s', 'read-only', '-C', (& $q $dir),
                 '-i', (& $q $full), '-o', (& $q $answerFile), '-')
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $ok = $false; $err = ''
    try {
        $p = Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -PassThru `
             -RedirectStandardInput $promptFile -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        if ($p.WaitForExit($TimeoutSec * 1000)) {
            <#
              Windows PowerShell 5.1 does not always expose ExitCode for a process started with -PassThru, so
              fall back to "the helper wrote an answer", which is what actually matters here.
            #>
            $code = $null
            try { $p.Refresh(); $code = $p.ExitCode } catch { $code = $null }
            if ($null -eq $code) {
                $ok = (Test-Path -LiteralPath $answerFile) -and ((Get-Item -LiteralPath $answerFile).Length -gt 0)
                if (-not $ok) { $err = 'the helper finished without answering' }
            } else {
                $ok = ($code -eq 0)
                if (-not $ok) { $err = "helper exited with $code" }
            }
        } else {
            try { $p.Kill() } catch { }
            try { [void]$p.WaitForExit(2000) } catch { }
            $err = "timed out after ${TimeoutSec}s"
        }
    } catch { $err = $_.Exception.Message }
    $sw.Stop()
    $answer = if (Test-Path -LiteralPath $answerFile) { (Get-Content -LiteralPath $answerFile -Raw -Encoding UTF8).Trim() } else { '' }
    if ($ok -and -not $answer) { $ok = $false; $err = 'the helper returned no answer' }
    if (-not $ok) {
        <#
          The helper prints its whole transcript to stderr, so take the last line that actually reads like a
          complaint - that is the part worth keeping, and it is read before the scratch folder goes.
        #>
        try {
            $bad = @(Get-Content -LiteralPath $stderrFile -Encoding UTF8 -ErrorAction SilentlyContinue |
                     Where-Object { $_ -match '(?i)\b(error|failed|failure|timed out|timeout|refused|denied|unavailable|not found|panic)\b' })
            if ($bad.Count -gt 0) {
                $line = $bad[-1].Trim()
                if ($line.Length -gt 160) { $line = $line.Substring(0, 160) + '...' }
                $err = "$err : $line"
            }
        } catch { }
    }
    <#
      Read once, gone immediately - and the same on failure: a read that produced no answer leaves
      nothing worth keeping, a fresh capture is one command away, and only -Keep (caller explicitly
      wants this file) spares it. The scratch folder never survives either.
    #>
    $deleted = $false
    if (-not $Keep) { $deleted = Remove-UiTempPath -Path $full }
    [void](Remove-UiTempPath -Path $dir -Tree)
    return [pscustomobject]@{ Ok = $ok; Answer = $answer; Deleted = $deleted; Seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
                              Path = $full; Error = $err; Kept = $Keep.IsPresent }
}

function Get-UiContextReport {
    <# Live conversation size and every shot still waiting on disk. #>
    $dir = $script:UiTempDir
    $shots = @(if (Test-Path -LiteralPath $dir) {
        Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.png', '.jpg') } | Sort-Object LastWriteTime -Descending
    })
    <# Measure-Object emits nothing for an empty list, so only ask it when there is something to measure. #>
    $shotBytes = [int64]0
    if ($shots.Count -gt 0) { $shotBytes = [int64](($shots | Measure-Object Length -Sum).Sum) }
    return [pscustomobject]@{
        BodyBytes = Get-UiSessionBodyBytes
        Dir       = $dir
        Shots     = $shots
        ShotCount = $shots.Count
        ShotBytes = $shotBytes
        Look      = Get-UiCodexExe
    }
}

function Format-UiContextReport {
    <# Three lines: how big this conversation is, what is left to read, and where the reader lives. #>
    param([Parameter(Mandatory)]$Report)
    $body = if ($Report.BodyBytes -gt 0) { "$([Math]::Round($Report.BodyBytes / 1MB, 1)) MB" } else { 'unknown' }
    $lines = @("context: conversation is $body live (no picture ever enters it; the gateway rejects ~50 MB)")
    if ($Report.ShotCount -eq 0) {
        $lines += "shots on disk: none - nothing is waiting to be read"
    } else {
        $names = ($Report.Shots | Select-Object -First 8 | ForEach-Object { $_.Name }) -join ', '
        if ($Report.ShotCount -gt 8) { $names += ", +$($Report.ShotCount - 8) more" }
        $lines += ("shots on disk: $($Report.ShotCount) ($([Math]::Round($Report.ShotBytes / 1KB)) KB) - read each with look " +
                   "(it deletes its own picture), or cleanup -Path <file> once it is not needed any more: $names")
    }
    $lines += ("out-of-band reader: " + $(if ($Report.Look) { [string]$Report.Look } else { 'codex CLI not found - set CODEX_CLI_PATH' }))
    return ($lines -join "`n")
}

# ------------------------------------------------------------------ wait / monitors
function Wait-Ui {
    <# Wait for a condition: -WindowVisible/-WindowGone/-Foreground/-RectStable/-Text/-TextGone (with -Handle). #>
    param([int64]$Window = 0,[int64]$Handle = 0,[string]$Text,[string]$TextGone,
          [switch]$WindowVisible,[switch]$WindowGone,[switch]$Foreground,[switch]$RectStable,
          [int]$TimeoutMs = 8000,[int]$IntervalMs = 120)
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        $ok = $true
        if ($WindowGone -and $Window -ne 0)    { $ok = $ok -and (-not [UiKit]::IsWindowVisible([IntPtr]$Window)) }
        if ($WindowVisible -and $Window -ne 0) { $ok = $ok -and [UiKit]::IsWindowVisible([IntPtr]$Window) }
        if ($Foreground -and $Window -ne 0)    { $ok = $ok -and ([UiKit]::GetForegroundWindow() -eq [IntPtr]$Window) }
        if ($Handle -ne 0 -and $Text)          { $ok = $ok -and ((Get-UiText -Handle $Handle) -like "*$Text*") }
        if ($Handle -ne 0 -and $TextGone)      { $ok = $ok -and (-not ((Get-UiText -Handle $Handle) -like "*$TextGone*")) }
        if ($RectStable -and $Window -ne 0) {
            $r1 = [UiKit]::RectOf([IntPtr]$Window); Start-Sleep -Milliseconds 260
            $r2 = [UiKit]::RectOf([IntPtr]$Window)
            $ok = $ok -and ($r1.Left -eq $r2.Left -and $r1.Top -eq $r2.Top -and $r1.Width -eq $r2.Width -and $r1.Height -eq $r2.Height)
        }
        if ($ok) { return $true }
        Start-Sleep -Milliseconds $IntervalMs
    }
    return $false
}
function Get-UiMonitor {
    $out = New-Object System.Collections.Generic.List[object]; $i = 0
    foreach ($m in [UiKit]::Monitors()) {
        $mi = [UiKit]::MonitorInfoOf($m)
        $out.Add([pscustomobject]@{ Index=$i; Primary=(($mi.dwFlags -band 1) -ne 0)
            X=$mi.rcMonitor.Left; Y=$mi.rcMonitor.Top; W=$mi.rcMonitor.Width; H=$mi.rcMonitor.Height
            WorkX=$mi.rcWork.Left; WorkY=$mi.rcWork.Top; WorkW=$mi.rcWork.Width; WorkH=$mi.rcWork.Height })
        $i++
    }
    return $out
}

# ------------------------------------------------------------------ UIA (modern apps: browsers/Electron/WPF/UWP)
function ConvertTo-UiPixel {
    <#
      UIA hands back doubles, and some providers (Flutter, custom-drawn UIs) answer with Infinity or NaN for
      elements that have no finite bounds - casting that to [int] throws and takes the whole command down.
      Everything that turns a UIA coordinate into pixels goes through here.
    #>
    param($Value)
    try {
        $d = [double]$Value
        if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return 0 }
        if ($d -gt 2147483647) { return 2147483647 }
        if ($d -lt -2147483648) { return -2147483648 }
        return [int][Math]::Round($d)
    } catch { return 0 }
}

function Resolve-UiaAutomationType {
    <#
      Locate System.Windows.Automation.AutomationElement in whatever way this host allows.
      PowerShell 7 / .NET Core resolves the assembly-qualified name; Windows PowerShell 5.1 loads the
      GAC assembly but [Type]::GetType("<type>, UIAutomationClient") still returns nothing there, so
      ask PowerShell's own type resolver and the loaded assembly object instead.
    #>
    $t = "System.Windows.Automation.AutomationElement" -as [type]
    if ($t) { return $t }
    $t = [Type]::GetType("System.Windows.Automation.AutomationElement, UIAutomationClient")
    if ($t) { return $t }
    foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) {
        try {
            if ($a.GetName().Name -eq "UIAutomationClient") {
                $t = $a.GetType("System.Windows.Automation.AutomationElement")
                if ($t) { return $t }
            }
        } catch { }
    }
    return $null
}

function Initialize-Uia {
    <#
      Load UIAutomationClient (not shipped with PowerShell 7). To work on any machine this tries, in order:
        1) use it directly when the type is already resolvable in this process;
        2) every installed .NET Desktop Runtime version (ProgramFiles / ProgramFiles(x86) / DOTNET_ROOT);
        3) the .NET Framework GAC / the WPF folder of the host runtime (Windows PowerShell 5.1);
      If all fail it throws; callers then fall back to the Win32 control tree + MSAA, which do not need UIA.
    #>
    if ($script:UiaRoot) { return }
    if (-not (Resolve-UiaAutomationType)) {
        $roots = @()
        foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:DOTNET_ROOT)) {
            if ($pf) { $roots += (Join-Path $pf "dotnet\shared\Microsoft.WindowsDesktop.App") }
        }
        foreach ($wd in ($roots | Select-Object -Unique)) {
            if (-not (Test-Path $wd)) { continue }
            foreach ($ver in (Get-ChildItem $wd -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
                $dll = Join-Path $ver.FullName "UIAutomationClient.dll"
                if (Test-Path $dll) { try { [void][Reflection.Assembly]::LoadFrom($dll); break } catch { } }
            }
            if (Resolve-UiaAutomationType) { break }
        }
        <# .NET Framework (typical for Windows PowerShell 5.1): GAC by simple name, then the framework WPF folder. #>
        if (-not (Resolve-UiaAutomationType)) {
            foreach ($name in @("UIAutomationClient", "UIAutomationTypes")) {
                try { [void][Reflection.Assembly]::LoadWithPartialName($name) } catch { }
                try { [void](Add-Type -AssemblyName $name -ErrorAction Stop) } catch { }
            }
        }
        if (-not (Resolve-UiaAutomationType)) {
            foreach ($dir in @("$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\WPF",
                               "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\WPF")) {
                $dll = Join-Path $dir "UIAutomationClient.dll"
                if (Test-Path $dll) { try { [void][Reflection.Assembly]::LoadFrom($dll) } catch { } }
                if (Resolve-UiaAutomationType) { break }
            }
        }
    }
    $t = Resolve-UiaAutomationType
    if (-not $t) { throw "UIA unavailable (UIAutomationClient not found); falling back to Win32 control tree + MSAA" }
    $script:UiaRoot = $t::RootElement
}

function Close-UiDialog {
    <# Close a dialog owned by the target window's process (app-agnostic):
         1) find a visible dialog window of that process (#32770 or a custom dialog class);
         2) try WM_COMMAND IDOK(1) -> IDYES(6) -> IDCANCEL(2) -> WM_CLOSE in turn;
       returns the action that actually closed it, or $null when there is no dialog. #>
    param([Parameter(Mandatory)][int64]$Window, [ValidateSet('ok','yes','cancel')][string]$Choice = 'ok')
    $pid_ = [UiKit]::PidOf([IntPtr]$Window)
    $dlg = $null
    foreach ($w in (Get-UiWindow | Sort-Object Z)) {
        if ($w.Pid -ne $pid_) { continue }
        if ($w.Handle -eq $Window) { continue }
        if (-not $w.Visible) { continue }
        if ($w.W -lt 80 -or $w.H -lt 40) { continue }
        $dlg = $w; break
    }
    if (-not $dlg) { return $null }
    $codes = switch ($Choice) {
        'yes'    { @(6, 1, 2) }
        'cancel' { @(2, 7, 6) }
        default  { @(1, 6, 2) }
    }
    foreach ($code in $codes) {
        [void][UiKit]::PostMessage([IntPtr]$dlg.Handle, 0x0111, [IntPtr]$code, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 350
        if (-not [UiKit]::IsWindowVisible([IntPtr]$dlg.Handle)) { return @{ Dialog = $dlg.Title; Action = "WM_COMMAND $code" } }
    }
    [void][UiKit]::PostMessage([IntPtr]$dlg.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 300
    return @{ Dialog = $dlg.Title; Action = 'WM_CLOSE' }
}

function Get-UiaElement {
    param([Parameter(Mandatory)][int64]$Handle)
    Initialize-Uia
    return [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Handle)
}

function Find-UiaElement {
    <# Find elements inside a window by UIA properties. #>
    param([Parameter(Mandatory)][int64]$Window,[string]$Name,[string]$AutomationId,
          [string]$Class,[string]$ControlType,[switch]$Deep,[int]$Index = 0)
    Initialize-Uia
    $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Window)
    $conds = New-Object System.Collections.Generic.List[object]
    if ($Name)         { $conds.Add((New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name))) }
    if ($AutomationId) { $conds.Add((New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId))) }
    if ($Class)        { $conds.Add((New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, $Class))) }
    if ($ControlType)  { $ct = [System.Windows.Automation.ControlType]::$ControlType
                         $conds.Add((New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ct))) }
    $cond = if ($conds.Count -eq 0) { [System.Windows.Automation.Condition]::TrueCondition }
            elseif ($conds.Count -eq 1) { $conds[0] }
            else { New-Object System.Windows.Automation.AndCondition ($conds.ToArray()) }
    $scope = if ($Deep) { [System.Windows.Automation.TreeScope]::Descendants } else { [System.Windows.Automation.TreeScope]::Children }
    $found = $root.FindAll($scope, $cond)
    if ($found.Count -le $Index) { return $null }
    return $found[$Index]
}

function Get-UiaTree {
    <# UIA element tree (for browsers/Electron/WPF that expose no Win32 child controls). #>
    param([Parameter(Mandatory)][int64]$Window,[int]$Depth = 3,[int]$MaxNodes = 400)
    Initialize-Uia
    $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Window)
    $list = New-Object System.Collections.Generic.List[object]
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    function Walk($el, [int]$lvl) {
        if ($null -eq $el -or $lvl -gt $Depth -or $list.Count -ge $MaxNodes) { return }
        $c = $el.Current; $r = $c.BoundingRectangle
        $list.Add([pscustomobject]@{
            Level=$lvl; Name=$c.Name; AutomationId=$c.AutomationId; Class=$c.ClassName
            ControlType=($c.ControlType.ProgrammaticName -replace 'ControlType\.','')
            X=(ConvertTo-UiPixel $r.X); Y=(ConvertTo-UiPixel $r.Y); W=(ConvertTo-UiPixel $r.Width); H=(ConvertTo-UiPixel $r.Height)
            Enabled=$c.IsEnabled; Offscreen=$c.IsOffscreen })
        $child = $walker.GetFirstChild($el)
        while ($null -ne $child -and $list.Count -lt $MaxNodes) { Walk $child ($lvl + 1); $child = $walker.GetNextSibling($child) }
    }
    Walk $root 0
    return $list
}

function Invoke-UiaAction {
    <# Invoke a UIA action on an element. #>
    param([Parameter(Mandatory)]$Element,
          [ValidateSet('Invoke','Select','Expand','Collapse','ScrollIntoView','Focus','SetValue','Toggle')][string]$Action,
          [string]$Value)
    switch ($Action) {
        'Invoke'         { $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
        'Select'         { $Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }
        'Expand'         { $Element.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand() }
        'Collapse'       { $Element.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() }
        'ScrollIntoView' { $Element.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView() }
        'Focus'          { $Element.SetFocus() }
        'Toggle'         { $Element.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle() }
        'SetValue'       { $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Value) }
    }
    Start-Sleep -Milliseconds 180
}

function Get-UiaValue {
    <# Read an element's ValuePattern (edit boxes, result fields, ...). #>
    param([Parameter(Mandatory)]$Element)
    try { return $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
    catch { return $null }
}

function Get-UiaText {
    <# Read element text: TextPattern first (documents/web pages/editors), then Name. #>
    param([Parameter(Mandatory)]$Element, [int]$MaxChars = 4000)
    try {
        $tp = $Element.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        $t = $tp.DocumentRange.GetText($MaxChars)
        if ($t) { return $t }
    } catch { }
    $v = Get-UiaValue -Element $Element
    if ($v) { return $v }
    <# When the window itself has no text, descend into Document / Edit / Text children. #>
    try {
        if ($Element.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window) {
            foreach ($ct in @([System.Windows.Automation.ControlType]::Document,
                              [System.Windows.Automation.ControlType]::Edit,
                              [System.Windows.Automation.ControlType]::Text)) {
                $cond = New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ct)
                $found = $Element.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
                for ($i = 0; $i -lt [Math]::Min($found.Count, 4); $i++) {
                    $el2 = $found[$i]
                    try {
                        $tp2 = $el2.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
                        $t2 = $tp2.DocumentRange.GetText($MaxChars)
                        if ($t2 -and $t2.Trim().Length -gt 0) { return $t2 }
                    } catch { }
                    $v2 = Get-UiaValue -Element $el2
                    if ($v2 -and $v2.Trim().Length -gt 0) { return $v2 }
                }
            }
        }
    } catch { }
    return $Element.Current.Name
}

function Get-UiaElements {
    <# Fetch elements by control type in bulk (e.g. all buttons at once). #>
    param([Parameter(Mandatory)][int64]$Window, [Parameter(Mandatory)][string]$ControlType,
          [int]$Max = 200)
    Initialize-Uia
    $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Window)
    $ct = [System.Windows.Automation.ControlType]::$ControlType
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ct)
    $found = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $out = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt [Math]::Min($found.Count, $Max); $i++) {
        $c = $found[$i].Current
        $out.Add([pscustomobject]@{ Index=$i; Element=$found[$i]; Name=$c.Name; AutomationId=$c.AutomationId
            Class=$c.ClassName; Enabled=$c.IsEnabled
            X=(ConvertTo-UiPixel $c.BoundingRectangle.X); Y=(ConvertTo-UiPixel $c.BoundingRectangle.Y)
            W=(ConvertTo-UiPixel $c.BoundingRectangle.Width); H=(ConvertTo-UiPixel $c.BoundingRectangle.Height) })
    }
    return $out
}

# ------------------------------------------------------------------ launch app / URL
function Start-UiApp {
    <#
      Launch a program and wait for its main window (returns the window object).
      Packaged apps (Windows 11 Notepad, Store apps) open the window in a second process, so a same-name
      window that did not exist before this launch counts too; the pre-launch handle snapshot keeps that
      from picking up an unrelated window of the same program.
    #>
    param([Parameter(Mandatory)][string]$Path,[string]$Arguments = "",
          [int]$TimeoutMs = 20000,[string]$Title)
    $before = @(Get-UiWindow -VisibleOnly | ForEach-Object { [int64]$_.Handle })
    $p = if ($Arguments) { Start-Process -FilePath $Path -ArgumentList $Arguments -PassThru }
         else { Start-Process -FilePath $Path -PassThru }
    $name = ''
    try { $name = (Get-Process -Id $p.Id -ErrorAction Stop).ProcessName } catch { }
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
        $w = @(Get-UiWindow -VisibleOnly | Where-Object {
                 ($_.Pid -eq $p.Id -or ($name -and $_.Process -eq $name)) -and
                 ($before -notcontains [int64]$_.Handle) -and $_.W -gt 120 -and $_.H -gt 80 })
        if ($w.Count -gt 0) {
            $hit = $w | Select-Object -First 1
            if ($Title) { $hit = @(Get-UiWindow -Title "*$Title*" -VisibleOnly | Select-Object -First 1) }
            return $hit
        }
    }
    throw "no window appeared within $TimeoutMs ms after launching $Path"
}

function Start-UiUrl {
    <# Open a URL in the default browser and wait for the browser window. #>
    param([Parameter(Mandatory)][string]$Url,[int]$TimeoutMs = 25000)
    Start-Process $Url | Out-Null
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 600
        $w = @(Get-UiWindow -VisibleOnly | Where-Object { $_.Process -in @('msedge','chrome','firefox','iexplore','brave','opera') -and $_.W -gt 400 })
        $fg = $w | Where-Object { $_.Foreground } | Select-Object -First 1
        if ($fg) { return $fg }
        if ($w.Count -gt 0) { return $w[0] }
    }
    throw "no browser window appeared after opening $Url"
}

# ------------------------------------------------------------------ batch steps
$script:UiCtx = @{ Window = 0 }
function Invoke-UiSteps {
    <# Run a list of steps in order (separated by |) - a whole scenario in one line or file.
       Common steps: win:<title>  activate  click:<id>  msgclick:<id>  dblclick:<id>
                 clicktext:<text>  clickxy:<x,y>  rclick:<id>
                 type:<text>  paste:<text>  key:<chord>  set:<id>=<text>
                 check:<id>=<0|1>  combo:<id>=<index>  tab:<id>=<index>  cmd:<commandId>
                 drag:<x1,y1,x2,y2>  wheel:<x,y,delta>  move:<x,y>
                 wait:<ms>  waitwin:<title>  waittext:<id>=<text>
                 uia:<name>  shot:<path>  log:<text>
                 shot:<path> writes a full-resolution PNG; read it back with `look`, which returns text and
                 deletes the picture right after - a capture never goes into the conversation.
    #>
    param([Parameter(Mandatory)][string]$Steps,[int64]$Window = 0,[switch]$Force)
    if ($Window -ne 0) { $script:UiCtx.Window = $Window }
    foreach ($raw in ($Steps -split '\|')) {
        $step = $raw.Trim(); if ($step -eq '') { continue }
        $i = $step.IndexOf(':'); $cmd = if ($i -lt 0) { $step } else { $step.Substring(0,$i).ToLower() }
        $arg = if ($i -lt 0) { '' } else { $step.Substring($i + 1) }
        $win = [int64]$script:UiCtx.Window
        switch ($cmd) {
            'win'       { $w = Get-UiWindowByTitle -Title $arg; $script:UiCtx.Window = $w.Handle; Write-UiLog 'win' @{ title=$w.Title; handle=$w.Handle } }
            'winh'      { $script:UiCtx.Window = [int64]$arg }
            'activate'  { [void](Set-UiFocus -Window $win) }
            'click'     { $h = Resolve-UiTarget -Window $win -Id ([int]$arg); Invoke-UiClick -Handle ([int64]$h) -Force:$Force | Out-Null }
            'msgclick'  { $h = Resolve-UiTarget -Window $win -Id ([int]$arg); Invoke-UiClick -Handle ([int64]$h) -Message -Force:$Force }
            'dblclick'  { $h = Resolve-UiTarget -Window $win -Id ([int]$arg); Invoke-UiClick -Handle ([int64]$h) -Double -Force:$Force | Out-Null }
            'rclick'    { $h = Resolve-UiTarget -Window $win -Id ([int]$arg); Invoke-UiClick -Handle ([int64]$h) -Button right -Force:$Force | Out-Null }
            'clicktext' { $h = Resolve-UiTarget -Window $win -Text $arg; Invoke-UiClick -Handle ([int64]$h) -Force:$Force | Out-Null }
            'clickxy'   { $xy = $arg -split ','; Invoke-UiMouseButton -Kind 'click' -X ([int]$xy[0]) -Y ([int]$xy[1]) -Window $win -Force:$Force }
            'type'      { [void](Assert-UiSafeToType -Window $win -Force:$Force); Send-UiText -Text $arg -Force:$Force }
            'paste'     { Send-UiText -Text $arg }
            'key'       { Send-UiKeys -Keys $arg -Force:$Force }
            'set'       { $kv = $arg -split '=',2; $h = Resolve-UiTarget -Window $win -Id ([int]$kv[0]); [void](Set-UiText -Handle ([int64]$h) -Text $kv[1] -Force:$Force) }
            'check'     { $kv = $arg -split '=',2; $h = Resolve-UiTarget -Window $win -Id ([int]$kv[0]); Set-UiCheck -Handle ([int64]$h) -Checked ([int]$kv[1] -ne 0) }
            'combo'     { $kv = $arg -split '=',2; $h = Resolve-UiTarget -Window $win -Id ([int]$kv[0]); Set-UiComboSelect -Handle ([int64]$h) -Index ([int]$kv[1]) }
            'tab'       { $kv = $arg -split '=',2; $h = Resolve-UiTarget -Window $win -Id ([int]$kv[0]); Set-UiTabSelect -Handle ([int64]$h) -Index ([int]$kv[1]) }
            'cmd'       { Invoke-UiCommand -Window $win -CommandId ([int]$arg) -Force:$Force }
            'drag'      { $d = $arg -split ','; Invoke-UiDrag -X1 ([int]$d[0]) -Y1 ([int]$d[1]) -X2 ([int]$d[2]) -Y2 ([int]$d[3]) -Handle $win -Force:$Force }
            'wheel'     { $d = $arg -split ','; Invoke-UiWheel -X ([int]$d[0]) -Y ([int]$d[1]) -Delta ([int]$d[2]) -Window $win -Force:$Force }
            'move'      { $xy = $arg -split ','; Move-UiMouse -X ([int]$xy[0]) -Y ([int]$xy[1]) }
            'wait'      { Start-Sleep -Milliseconds ([int]$arg) }
            'waitwin'   { if (-not (Wait-Ui -Window ((Get-UiWindowByTitle -Title $arg).Handle) -WindowVisible -TimeoutMs 15000)) { throw "timed out waiting for window: $arg" } }
            'waittext'  { $kv = $arg -split '=',2; $h = Resolve-UiTarget -Window $win -Id ([int]$kv[0])
                          if (-not (Wait-Ui -Handle ([int64]$h) -Text $kv[1] -TimeoutMs 8000)) { throw "timed out waiting for text: $arg" } }
            'uia'       { $el = Find-UiaElement -Window $win -Name $arg -Deep
                          if (-not $el) { $el = Find-UiaElement -Window $win -AutomationId $arg -Deep }
                          if (-not $el) { throw "UIA element not found: $arg" }
                          try { Invoke-UiaAction -Element $el -Action Invoke } catch { Invoke-UiaAction -Element $el -Action Select } }
            'shot'      { <# Full-resolution capture; read it back with look, never in-conversation. #>
                          $r = Invoke-UiShotWithPlan -Out $arg -Window $win
                          Write-UiLog 'shot' @{ arg = $arg; window = $win; image = $r.Image
                                                KB = [Math]::Round($r.Bytes / 1KB); px = $r.Dimensions } -Quiet }
            'log'       { Write-UiLog 'note' @{ text = $arg } }
            default     { Write-UiLog 'unknown-step' @{ step = $step } }
        }
        if ($cmd -notin @('log','win','winh','shot')) { Write-UiLog $cmd @{ arg = $arg; window = $script:UiCtx.Window } -Quiet }
    }
    return $script:UiCtx.Window
}

# === Occlusion handling: find the target and bring it into view ===

function Get-UiOccluders {
    <# List windows covering the target (by Z order, ignoring desktop/taskbar/shell windows). #>
    param([Parameter(Mandatory)][int64]$Window, [double]$MinOverlap = 0.15)
    $target = [UiKit]::RectOf([IntPtr]$Window)
    if ($target.Width -le 0 -or $target.Height -le 0) { return @() }
    $all = @(Get-UiWindow -VisibleOnly)
    $self = $all | Where-Object { $_.Handle -eq $Window } | Select-Object -First 1
    $selfZ = if ($self) { $self.Z } else { 9999 }
    $ignore = @('Progman','WorkerW','Shell_TrayWnd','Shell_SecondaryTrayWnd','Windows.UI.Core.CoreWindow',
                'ApplicationFrameWindow_Shell','MultitaskingViewFrame','ForegroundStaging','XamlExplorerHostIslandWindow')
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($w in $all) {
        if ($w.Handle -eq $Window) { continue }
        if ($w.Z -ge $selfZ) { continue }
        if ($ignore -contains $w.Class) { continue }
        if ($w.W -le 4 -or $w.H -le 4) { continue }
        $ix = [Math]::Max(0, [Math]::Min($target.Right, $w.X + $w.W) - [Math]::Max($target.Left, $w.X))
        $iy = [Math]::Max(0, [Math]::Min($target.Bottom, $w.Y + $w.H) - [Math]::Max($target.Top, $w.Y))
        $overlap = ($ix * $iy) / [double]($target.Width * $target.Height)
        if ($overlap -ge $MinOverlap) {
            $out.Add([pscustomobject]@{ Handle=$w.Handle; Z=$w.Z; Process=$w.Process; Class=$w.Class
                Title=$w.Title; X=$w.X; Y=$w.Y; W=$w.W; H=$w.H; Overlap=[Math]::Round($overlap,2)
                Safe=$w.Safe; PreExisting=$w.PreExisting
                Blocked=(Test-UiSafeTarget -Handle ([IntPtr]$w.Handle)).Reason })
        }
    }
    return $out
}

function Move-UiWindowAside {
    <# Move a window out of the way (prefers the bottom-right corner of the work area). #>
    param([Parameter(Mandatory)][int64]$Window, [int64]$Avoid = 0)
    $mons = Get-UiMonitor
    $m = $mons | Where-Object { $_.Primary } | Select-Object -First 1
    if (-not $m) { $m = $mons[0] }
    $r = [UiKit]::RectOf([IntPtr]$Window)
    $w = [Math]::Max(320, [Math]::Min($r.Width, [int]($m.WorkW * 0.5)))
    $h = [Math]::Max(240, [Math]::Min($r.Height, [int]($m.WorkH * 0.5)))
    $x = $m.WorkX + $m.WorkW - $w - 8
    $y = $m.WorkY + $m.WorkH - $h - 8
    if ($Avoid -ne 0) {
        $ar = [UiKit]::RectOf([IntPtr]$Avoid)
        if ([Math]::Abs($x - $ar.Left) -lt 40 -and [Math]::Abs($y - $ar.Top) -lt 40) { $x = $m.WorkX + 8; $y = $m.WorkY + 8 }
    }
    Set-UiWindowRect -Window $Window -X $x -Y $y -W $w -H $h
    return @{ X = $x; Y = $y; W = $w; H = $h }
}

function Find-UiShortcut {
    <# Find shortcuts/programs by name in the Start Menu (user + all users) and on the Desktop. #>
    param([Parameter(Mandatory)][string]$Name, [int]$Max = 12)
    <# Friendly name -> executable/alias so a short query still finds the app (UWP apps rely on this). #>
    $alias = @{
        'calculator'='calc'; 'notepad'='notepad'; 'paint'='mspaint'; 'wordpad'='write'
        'explorer'='explorer'; 'file explorer'='explorer'; 'files'='explorer'
        'task manager'='taskmgr'; 'control panel'='control'; 'browser'='msedge'
        'edge'='msedge'; 'settings'='systemsettings'; 'snip'='snippingtool'
        'snipping tool'='snippingtool'; 'camera'='camera'; 'clock'='clock'
        'calendar'='calendar'; 'store'='store'; 'terminal'='wt'
        'command prompt'='cmd'; 'cmd'='cmd'
    }
    $patterns = @($Name)
    foreach ($k in $alias.Keys) { if ($Name -like "*$k*" -or $k -like "*$Name*") { $patterns += $alias[$k] } }
    $dirs = @(
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"),
        (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"),
        ([Environment]::GetFolderPath("Desktop")),
        (Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) ""),
        (Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps")
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    $hits = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($d in $dirs) {
        foreach ($pat in $patterns) {
            Get-ChildItem -LiteralPath $d -Recurse -Include *.lnk, *.url, *.exe -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -like "*$pat*" } |
                ForEach-Object {
                    $full = $_.FullName
                    if ($hits.Count -lt $Max -and $seen.Add($full)) {
                        $hits.Add([pscustomobject]@{ Name=$_.BaseName; Path=$full
                            Kind=$_.Extension; Dir=$d; Matched=$pat })
                    }
                }
        }
    }
    <# UWP/Store apps: enumerate shell:AppsFolder (they are apps, not shortcut files). #>
    try {
        $shell = New-Object -ComObject Shell.Application
        $apps = $shell.NameSpace('shell:AppsFolder')
        foreach ($item in $apps.Items()) {
            if ($hits.Count -ge $Max) { break }
            $n = $item.Name
            foreach ($pat in $patterns) {
                if ($n -like "*$pat*" -and $seen.Add([string]$item.Path)) {
                    $hits.Add([pscustomobject]@{ Name=$n; Path=$item.Path; Kind='App'
                        Dir='shell:AppsFolder'; Matched=$pat })
                    break
                }
            }
        }
    } catch { }
    return $hits
}

function Start-UiFromShortcut {
    <# Locate and launch a program from the Start Menu / Desktop. #>
    param([Parameter(Mandatory)][string]$Name, [switch]$PassThru)
    $hit = (Find-UiShortcut -Name $Name | Select-Object -First 1)
    if (-not $hit) { throw "no Start Menu / Desktop shortcut matches $Name" }
    if ($hit.Kind -eq 'App') {
        Start-Process ("shell:AppsFolder\" + $hit.Path) -ErrorAction SilentlyContinue | Out-Null
        $p = $null
    } else {
        $p = Start-Process -FilePath $hit.Path -PassThru
    }
    if ($PassThru) { return @{ Shortcut = $hit; Process = $p } }
    return $hit
}

function Switch-UiTaskbar {
    <# Switch windows through the taskbar (UIA click, matched by name). #>
    param([Parameter(Mandatory)][string]$Name, [int]$TimeoutMs = 8000)
    <# The taskbar can be missing for a moment while Explorer animates/restarts, so retry before failing. #>
    $tb = $null
    $probeDeadline = (Get-Date).AddMilliseconds(3000)
    while (-not $tb -and (Get-Date) -lt $probeDeadline) {
        $found = @(Get-UiWindow -Class 'Shell_TrayWnd') | Select-Object -First 1
        if ($found) { $tb = $found } else { Start-Sleep -Milliseconds 300 }
    }
    if (-not $tb) { throw "taskbar not found (still missing after 3s)" }
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        $el = Find-UiaElement -Window $tb.Handle -Name $Name -Deep
        if (-not $el) {
            $btns = Get-UiaElements -Window $tb.Handle -ControlType Button -Max 80
            <# StrictMode: reading .Element off an empty match would throw, so test the match first. #>
            $hitBtn = $btns | Where-Object { $_.Name -like "*$Name*" } | Select-Object -First 1
            if ($hitBtn) { $el = $hitBtn.Element }
        }
        if ($el) {
            try { Invoke-UiaAction -Element $el -Action Invoke }
            catch { try { Invoke-UiaAction -Element $el -Action Select } catch { } }
            Start-Sleep -Milliseconds 500
            <# Verify the switch actually happened; otherwise fall back to SwitchToThisWindow / SetForegroundWindow. #>
            $tgt = @(Get-UiWindow -Title "*$Name*" -VisibleOnly | Select-Object -First 1)
            if ($tgt -and ([UiKit]::GetForegroundWindow() -eq [IntPtr]$tgt.Handle)) { return $true }
            if ($tgt) {
                [UiKit]::SwitchToThisWindow([IntPtr]$tgt.Handle, $true)
                Start-Sleep -Milliseconds 300
                if ([UiKit]::GetForegroundWindow() -eq [IntPtr]$tgt.Handle) { return $true }
                if (Set-UiFocus -Window $tgt.Handle) { return $true }
            }
            return $false
        }
        Start-Sleep -Milliseconds 400
    }
    return $false
}

function Restore-UiWindow {
    <# Restore a minimised/hidden window by title keyword. #>
    param([Parameter(Mandatory)][string]$Name)
    $cand = @(Get-UiWindow -Title "*$Name*")
    if ($cand.Count -eq 0) { return $null }
    $w = $null
    foreach ($c in $cand) { if ($c.Min) { $w = $c; break } }
    if (-not $w) { $w = $cand[0] }
    $handle = [int64]$w.Handle
    [void][UiKit]::ShowWindow([IntPtr]$handle, 9)            # SW_RESTORE
    Start-Sleep -Milliseconds 300
    [void](Set-UiFocus -Window $handle)
    return [pscustomobject]@{
        Handle = $handle
        Process = [string]$w.Process
        Title = [string]$w.Title
        WasMinimized = [bool]$w.Min
        Foreground = ([UiKit]::GetForegroundWindow() -eq [IntPtr]$handle)
    }
}

function Invoke-UiReveal {
    <#
      Bring the target window into a visible, clickable state. Strategies (auto tries them in order):
        activate  raise it directly
        minimize  minimise the blocking windows
        move      move the blocking windows aside
        close     close blocking windows (only ones created in this session, or with -AllowClose)
        taskbar   switch through the taskbar button
        search    find and launch a shortcut from the Start Menu / Desktop
      Returns @{ Ok; Steps; Occluders; Foreground }
    #>
    param(
        [Parameter(Mandatory)][int64]$Window,
        [ValidateSet('auto','activate','minimize','move','close','taskbar','search')][string]$Strategy = 'auto',
        [switch]$AllowClose, [string]$TargetName = '', [switch]$VerifyOnly
    )
    $steps = New-Object System.Collections.Generic.List[string]
    $targetTitle = if ($TargetName) { $TargetName } else { [UiKit]::TextOf([IntPtr]$Window) }
    $proc = ''
    try { $proc = (Get-Process -Id ([UiKit]::PidOf([IntPtr]$Window)) -ErrorAction Stop).ProcessName } catch { }

    if ($VerifyOnly) {
        $occ0 = @(Get-UiOccluders -Window $Window)
        return @{ Ok = ($occ0.Count -eq 0); Steps = @(); Occluders = $occ0
                  Foreground = ([UiKit]::GetForegroundWindow() -eq [IntPtr]$Window) }
    }

    $order = if ($Strategy -eq 'auto') { @('activate','minimize','move','taskbar','close','search') } else { @($Strategy) }
    foreach ($s in $order) {
        switch ($s) {
            'activate' {
                if (Set-UiFocus -Window $Window) {
                    $occ = @(Get-UiOccluders -Window $Window)
                    $steps.Add("activate:foreground ok (occluders $($occ.Count))")
                    if ($occ.Count -eq 0) {
                        return @{ Ok=$true; Steps=$steps; Occluders=@(); Foreground=$true }
                    }
                } else { $steps.Add('activate:rejected by the foreground lock') }
            }
            'minimize' {
                $occ = @(Get-UiOccluders -Window $Window)
                if ($occ.Count -gt 0) {
                    foreach ($o in $occ) {
                        if ($o.Class -in @('Progman','WorkerW','Shell_TrayWnd')) { continue }
                        [void][UiKit]::ShowWindow([IntPtr]$o.Handle, 2)     # SW_MINIMIZE
                        $steps.Add("minimize:$($o.Process)/$($o.Title)")
                    }
                    Start-Sleep -Milliseconds 350
                    [void](Set-UiFocus -Window $Window)
                    if ((@(Get-UiOccluders -Window $Window)).Count -eq 0) {
                        return @{ Ok=$true; Steps=$steps; Occluders=@(); Foreground=([UiKit]::GetForegroundWindow() -eq [IntPtr]$Window) }
                    }
                }
            }
            'move' {
                $occ = @(Get-UiOccluders -Window $Window)
                foreach ($o in $occ) {
                    if ($o.Class -in @('Progman','WorkerW','Shell_TrayWnd')) { continue }
                    $pos = Move-UiWindowAside -Window $o.Handle -Avoid $Window
                    $steps.Add("move:$($o.Process) -> $($pos.X),$($pos.Y)")
                }
                if ($occ.Count -gt 0) {
                    Start-Sleep -Milliseconds 300
                    [void](Set-UiFocus -Window $Window)
                    if ((@(Get-UiOccluders -Window $Window)).Count -eq 0) {
                        return @{ Ok=$true; Steps=$steps; Occluders=@(); Foreground=([UiKit]::GetForegroundWindow() -eq [IntPtr]$Window) }
                    }
                }
            }
            'taskbar' {
                $name = if ($targetTitle) { $targetTitle } else { $proc }
                if (Switch-UiTaskbar -Name $name) {
                    $steps.Add("taskbar:switched by name ($name)")
                    if ((@(Get-UiOccluders -Window $Window)).Count -eq 0) {
                        return @{ Ok=$true; Steps=$steps; Occluders=@(); Foreground=([UiKit]::GetForegroundWindow() -eq [IntPtr]$Window) }
                    }
                } else { $steps.Add('taskbar:no matching button (window may be a tray/hidden window)') }
            }
            'close' {
                $occ = @(Get-UiOccluders -Window $Window)
                $closed = 0
                foreach ($o in $occ) {
                    if ($o.Blocked) { $steps.Add("close:skipped protected window ($($o.Blocked))"); continue }
                    if ((-not $AllowClose) -and $o.PreExisting) {
                        $steps.Add("close:skipped pre-existing user window ($($o.Title))"); continue
                    }
                    [void][UiKit]::PostMessage([IntPtr]$o.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
                    $closed++
                    $steps.Add("close:$($o.Process)/$($o.Title)")
                }
                if ($closed -gt 0) {
                    Start-Sleep -Milliseconds 600
                    [void](Set-UiFocus -Window $Window)
                    if ((@(Get-UiOccluders -Window $Window)).Count -eq 0) {
                        return @{ Ok=$true; Steps=$steps; Occluders=@(); Foreground=([UiKit]::GetForegroundWindow() -eq [IntPtr]$Window) }
                    }
                }
            }
            'search' {
                $key = if ($TargetName) { $TargetName } elseif ($proc) { $proc } else { $targetTitle }
                $hits = @(Find-UiShortcut -Name $key)
                if ($hits.Count -gt 0) {
                    $steps.Add("search:found $($hits.Count) shortcuts -> $($hits[0].Name)")
                    Start-Process -FilePath $hits[0].Path | Out-Null
                    Start-Sleep -Seconds 2
                } else { $steps.Add("search:no Start Menu / Desktop shortcut matches $key") }
            }
        }
    }
    $occ = @(Get-UiOccluders -Window $Window)
    return @{ Ok = ($occ.Count -eq 0); Steps = $steps; Occluders = $occ
              Foreground = ([UiKit]::GetForegroundWindow() -eq [IntPtr]$Window) }
}

function Get-UiDecision {
    <#
      Decide whether UI automation is necessary (default: do not use UI):
        - explicitly requested by user or rules      -> use
        - no CLI/API/file channel exists             -> use
        - need to inspect real rendering/pixels      -> use
        - a more reliable CLI/API path exists        -> do not use
        - merely convenient or unsure                -> do not use (look for another way first)
    #>
    param([string]$Task = '', [switch]$Explicit, [switch]$NoApi, [switch]$Visual, [switch]$Cheaper)
    if ($Explicit) { return @{ UseUi=$true;  Rule='explicit';  Reason='UI automation explicitly requested by the user or rules' } }
    if ($NoApi)    { return @{ UseUi=$true;  Rule='no-api';    Reason='no CLI/API/file channel is available for this task' } }
    if ($Visual)   { return @{ UseUi=$true;  Rule='visual';    Reason='needs real rendering inspection (layout/fonts/occlusion/pixel quality)' } }
    if ($Cheaper)  { return @{ UseUi=$false; Rule='cheaper';   Reason='a more reliable CLI/API path exists; prefer it' } }
    return @{ UseUi=$false; Rule='default'; Reason='do not use UI by default; prove other approaches are impossible or insufficient first' }
}

# === Set-of-Marks: number the interactive elements on a screenshot (OmniParser-style grounding) ===
# Vision models read the numbered image and answer 'click 7'; text-only models use the marks table.

# ------------------------------------------------------------------ MSAA fallback
$script:UiMsaaRoles = @{
    0x2 = 'MenuBar'; 0x3 = 'ScrollBar'; 0x9 = 'Window'; 0xA = 'Pane'; 0xB = 'Menu'
    0xC = 'MenuItem'; 0xE = 'Application'; 0xF = 'Document'; 0x10 = 'Pane'; 0x12 = 'Dialog'
    0x14 = 'Group'; 0x15 = 'Separator'; 0x16 = 'ToolBar'; 0x17 = 'StatusBar'; 0x18 = 'Table'
    0x19 = 'HeaderItem'; 0x1C = 'DataItem'; 0x1D = 'DataItem'; 0x1E = 'Hyperlink'
    0x21 = 'List'; 0x22 = 'ListItem'; 0x23 = 'Tree'; 0x24 = 'TreeItem'; 0x25 = 'Tab'
    0x26 = 'TabItem'; 0x28 = 'Image'; 0x29 = 'Text'; 0x2A = 'Edit'; 0x2B = 'Button'
    0x2C = 'CheckBox'; 0x2D = 'RadioButton'; 0x2E = 'ComboBox'; 0x2F = 'ComboBox'
    0x30 = 'ProgressBar'; 0x32 = 'Edit'; 0x33 = 'Slider'; 0x34 = 'Spinner'; 0x35 = 'Image'
    0x37 = 'Document'; 0x38 = 'ButtonDropDown'; 0x39 = 'ButtonDropDown'; 0x3B = 'Separator'
    0x3C = 'Tab'; 0x3E = 'SplitButton'; 0x3F = 'Edit'; 0x40 = 'Button'
}

function Get-UiMsaaInfo {
    <# MSAA info for one HWND: real role/name/state/default action (the key to legacy Win32 controls). #>
    param([Parameter(Mandatory)][int64]$Handle)
    $acc = $null
    try { $acc = [Msaa]::Client([IntPtr]$Handle) } catch { }
    if (-not $acc) { try { $acc = [Msaa]::Self([IntPtr]$Handle) } catch { } }
    if (-not $acc) { return $null }
    $name = ''; $value = ''; $def = ''; $role = -1; $state = 0; $kids = 0
    try { $name  = [string]$acc.accName(0) } catch { }
    try { $value = [string]$acc.accValue(0) } catch { }
    try { $def   = [string]$acc.accDefaultAction(0) } catch { }
    try { $role  = [int]$acc.accRole(0) } catch { }
    try { $state = [int]$acc.accState(0) } catch { }
    try { $kids  = [int]$acc.accChildCount } catch { }
    $r = [UiKit]::RectOf([IntPtr]$Handle)
    $type = $script:UiMsaaRoles[$role]
    if (-not $type) { $type = 'Pane' }
    return [pscustomobject]@{
        Handle = $Handle; Type = $type; Name = $name; Value = $value
        DefaultAction = $def; Role = $role; ChildCount = $kids
        Enabled = (($state -band 0x1) -eq 0)
        Focused = (($state -band 0x4) -ne 0)
        Checked = (($state -band 0x10) -ne 0)
        Offscreen = ((($state -band 0x8000) -ne 0) -or (($state -band 0x10000) -ne 0))
        X = $r.Left; Y = $r.Top; W = $r.Width; H = $r.Height
        CX = [int]($r.Left + $r.Width / 2); CY = [int]($r.Top + $r.Height / 2) }
}

function Get-UiMsaaMap {
    <# Whole-window scan: one MSAA record per child HWND. #>
    param([Parameter(Mandatory)][int64]$Window)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($c in (Get-UiTree -Window $Window)) {
        $info = Get-UiMsaaInfo -Handle $c.Handle
        if ($info) { $list.Add($info) }
    }
    return $list
}

function Invoke-UiMsaaAction {
    <# Run the MSAA default action (equivalent to UIA Invoke, no mouse, no focus change). #>
    param([Parameter(Mandatory)][int64]$Handle)
    $acc = $null
    try { $acc = [Msaa]::Client([IntPtr]$Handle) } catch { }
    if (-not $acc) { try { $acc = [Msaa]::Self([IntPtr]$Handle) } catch { } }
    if (-not $acc) { throw "control exposes no MSAA interface" }
    $def = ''
    try { $def = [string]$acc.accDefaultAction(0) } catch { }
    if (-not $def) { throw "control has no default action (DefaultAction is empty)" }
    $acc.accDoDefaultAction(0)
    Start-Sleep -Milliseconds 150
    return $def
}

function Get-UiMarks {
    <# Enumerate and number the interactive elements of a window (UIA first, Win32 controls as a supplement). #>
    param([Parameter(Mandatory)][int64]$Window, [int]$Max = 120, [switch]$IncludeText)
    Initialize-Uia
    $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Window)
    $items = New-Object System.Collections.Generic.List[object]
    <# Build a Win32 index first so controls reported as 'Pane' can be enriched into Button/Edit/List. #>
    function Friendly([string]$cls) {
        switch -Regex ($cls) {
            '^Button'          { 'Button' }
            '^Edit|RichEdit'   { 'Edit' }
            '^SysListView'     { 'List' }
            '^SysTreeView'     { 'Tree' }
            '^SysTab'          { 'Tab' }
            '^ComboBox'        { 'ComboBox' }
            '^msctls_updown'   { 'Spinner' }
            '^msctls_progress' { 'ProgressBar' }
            '^ScrollBar'       { 'ScrollBar' }
            '^Static'          { 'Text' }
            default            { 'Win32' }
        }
    }
    $win32 = @(Get-UiTree -Window $Window)
    <# MSAA map: restore real roles for 'Pane' elements by rectangle and add their default actions. #>
    $msaa = @(Get-UiMsaaMap -Window $Window)
    <#
      Note: for legacy Win32 apps the .NET UIA client reports child controls as 'Pane',
      without Invoke/Value patterns, so instead of filtering by ControlType we take
      every descendant and keep those worth numbering (has a name / AutomationId / is focusable /
      exposes a pattern); the type is enriched from the Win32 class name for readability.
    #>
    $patternMap = @{
        'Invoke'         = [System.Windows.Automation.InvokePattern]::Pattern
        'Value'          = [System.Windows.Automation.ValuePattern]::Pattern
        'Toggle'         = [System.Windows.Automation.TogglePattern]::Pattern
        'SelectionItem'  = [System.Windows.Automation.SelectionItemPattern]::Pattern
        'ExpandCollapse' = [System.Windows.Automation.ExpandCollapsePattern]::Pattern
    }
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                             [System.Windows.Automation.Condition]::TrueCondition)
    } catch { $all = $null }
    if ($all) {
        for ($i = 0; $i -lt $all.Count; $i++) {
            if ($items.Count -ge $Max) { break }
            $el = $all[$i]; $c = $el.Current
            if ($c.IsOffscreen) { continue }
            $r = $c.BoundingRectangle
            if ($r.Width -lt 10 -or $r.Height -lt 10) { continue }
            if ($r.Width -ge 3000 -or $r.Height -ge 3000) { continue }
            <# A provider that reports Infinity here would poison every later computation - treat it as unusable. #>
            if ([double]::IsNaN([double]$r.X) -or [double]::IsInfinity([double]$r.X) -or
                [double]::IsNaN([double]$r.Y) -or [double]::IsInfinity([double]$r.Y)) { continue }
            $pats = @()
            foreach ($k in $patternMap.Keys) {
                $o = $null
                try { if ($el.TryGetCurrentPattern($patternMap[$k], [ref]$o)) { $pats += $k } } catch { }
            }
            $name = [string]$c.Name
            $auto = [string]$c.AutomationId
            $interesting = ($pats.Count -gt 0) -or ($name -ne '') -or ($auto -ne '')
            if (-not $interesting) { continue }
            if (-not $IncludeText -and $name -eq '' -and $auto -eq '') { continue }
            <# Enrich type and name from the Win32 class (important for legacy controls). #>
            $type = ($c.ControlType.ProgrammaticName -replace 'ControlType\.','')
            $cls = [string]$c.ClassName
            $canInvoke = ($pats -contains 'Invoke')
            $defaultAction = ''
            foreach ($w32 in $win32) {
                if ([Math]::Abs($w32.X - (ConvertTo-UiPixel $r.X)) -le 3 -and [Math]::Abs($w32.Y - (ConvertTo-UiPixel $r.Y)) -le 3) {
                    $hit = $null
                    foreach ($m in $msaa) { if ([Math]::Abs($m.X - (ConvertTo-UiPixel $r.X)) -le 3 -and [Math]::Abs($m.Y - (ConvertTo-UiPixel $r.Y)) -le 3) { $hit = $m; break } }
                    if ($hit -and ($type -eq 'Pane' -or $type -eq 'Custom')) { $type = $hit.Type }
                    if ($type -eq 'Pane' -or $type -eq 'Custom') { $type = Friendly $w32.Class }
                    if ($hit) {
                        if (-not $name -and $hit.Name) { $name = $hit.Name }
                        $defaultAction = $hit.DefaultAction
                        if ($hit.DefaultAction) { $canInvoke = $true }
                    }
                    if (-not $cls) { $cls = $w32.Class }
                    if (-not $name -and $w32.Text) { $name = [string]$w32.Text }
                    break
                }
            }
            $items.Add([pscustomobject]@{
                Type = $type
                Name = $name; AutomationId = $auto; Class = $cls
                Enabled = [bool]$c.IsEnabled; Patterns = ($pats -join '/')
                CanInvoke = [bool]$canInvoke; DefaultAction = $defaultAction
                X = (ConvertTo-UiPixel $r.X); Y = (ConvertTo-UiPixel $r.Y)
                W = (ConvertTo-UiPixel $r.Width); H = (ConvertTo-UiPixel $r.Height)
                CX = (ConvertTo-UiPixel ($r.X + $r.Width / 2)); CY = (ConvertTo-UiPixel ($r.Y + $r.Height / 2))
                Element = $el; Source = 'UIA' })
        }
    }
    <# Supplement: Win32 children UIA did not expose (custom-drawn controls, some standard ones). #>
    foreach ($c in $win32) {
        if ($items.Count -ge $Max) { break }
        if ($c.W -lt 12 -or $c.H -lt 12) { continue }
        if ($c.Class -in @('Static','SysHeader32','msctls_statusbar32')) { continue }
        $dup = $false
        foreach ($m in $items) { if ([Math]::Abs($m.X - $c.X) -le 3 -and [Math]::Abs($m.Y - $c.Y) -le 3 -and [Math]::Abs($m.W - $c.W) -le 4) { $dup = $true; break } }
        if ($dup) { continue }
        <# Prefer the real role, name and default action reported by MSAA. #>
        $m2 = $null
        foreach ($m in $msaa) { if ([Math]::Abs($m.X - $c.X) -le 3 -and [Math]::Abs($m.Y - $c.Y) -le 3) { $m2 = $m; break } }
        $friendly = if ($m2) { $m2.Type } else { Friendly $c.Class }
        $label = if ($m2 -and $m2.Name) { $m2.Name } else { [string]$c.Text }
        $items.Add([pscustomobject]@{
            Type = $friendly; Name = $label; AutomationId = "ID:$($c.ControlId)"
            Class = [string]$c.Class; Enabled = [bool]$c.Enabled
            Patterns = ''
            CanInvoke = [bool]($m2 -and $m2.DefaultAction); DefaultAction = $(if ($m2) { $m2.DefaultAction } else { '' })
            X = $c.X; Y = $c.Y; W = $c.W; H = $c.H
            CX = [int]($c.X + $c.W / 2); CY = [int]($c.Y + $c.H / 2)
            MsaaHandle = $(if ($m2) { $m2.Handle } else { 0 })
            Element = $null; Source = 'Win32' })
    }
    <# Number in reading order (top to bottom, then left to right) so numbers stay predictable. #>
    $sorted = $items | Sort-Object @{Expression={ [int]([Math]::Floor($_.Y / 24)) }}, X
    $n = 0
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($it in $sorted) {
        $n++
        $out.Add([pscustomobject]@{
            Index = $n; Type = $it.Type; Name = $it.Name; AutomationId = $it.AutomationId
            Class = $it.Class; Enabled = $it.Enabled; Patterns = $it.Patterns
            CanInvoke = [bool]$it.CanInvoke; DefaultAction = [string]$it.DefaultAction
            X = $it.X; Y = $it.Y; W = $it.W; H = $it.H; CX = $it.CX; CY = $it.CY
            Source = $it.Source; Element = $it.Element })
    }
    return $out
}

function Save-UiSomShot {
    <# Draw the numbers onto a window screenshot; returns @{ Image; Marks; MapFile }. #>
    param([Parameter(Mandatory)][int64]$Window, [Parameter(Mandatory)][string]$Out, [int]$Max = 120, [switch]$Cursor)
    Add-Type -AssemblyName System.Drawing
    $dir = Split-Path -Parent $Out
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $raw = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ("uia-raw-" + [Guid]::NewGuid().ToString('N') + ".png"))
    [void](Save-UiShotSmart -Out $raw -Window $Window -Cursor:$Cursor -MaxWidth 0)
    $marks = @(Get-UiMarks -Window $Window -Max $Max)
    $wr = [UiKit]::RectOf([IntPtr]$Window)
    $bmp = [System.Drawing.Bitmap]::FromFile($raw)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $fontSize = [Math]::Max(11, [int]($bmp.Width / 90))
    $font = New-Object System.Drawing.Font("Consolas", $fontSize, [System.Drawing.FontStyle]::Bold)
    $penBox = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(210, 30, 110, 220)), 1.6
    $brushBadge = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235, 20, 90, 200))
    $brushText = [System.Drawing.Brushes]::White
    foreach ($m in $marks) {
        $x = $m.X - $wr.Left; $y = $m.Y - $wr.Top
        $g.DrawRectangle($penBox, $x, $y, [Math]::Max(4, $m.W), [Math]::Max(4, $m.H))
        $label = [string]$m.Index
        $sz = $g.MeasureString($label, $font)
        $bw = [int]($sz.Width + 6); $bh = [int]($sz.Height + 2)
        $g.FillRectangle($brushBadge, $x, $y, $bw, $bh)
        $g.DrawString($label, $font, $brushText, $x + 3, $y)
    }
    $g.Dispose()
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    [void](Remove-UiTempPath -Path $raw)
    $mapFile = Save-UiMarks -Window $Window -Marks $marks
    return @{ Image = $Out; Marks = $marks; MapFile = $mapFile }
}

function Get-UiMark {
    <# Read the marks table from the last 'som' run (somclick can also regenerate it). #>
    param([Parameter(Mandatory)][int64]$Window)
    $mapFile = Get-UiMarkMapPath -Window $Window
    if (-not (Test-Path $mapFile)) { return $null }
    return (Get-Content -LiteralPath $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-UiMarkMapPath {
    <# Where the marks table for a window lives (text form of the Set-of-Marks data). #>
    param([Parameter(Mandatory)][int64]$Window)
    return (Join-Path $script:UiTempDir ("marks-$Window.json"))
}

function Save-UiMarks {
    <# Persist a marks table so later commands can act on the same numbering. #>
    param([Parameter(Mandatory)][int64]$Window, [Parameter(Mandatory)]$Marks)
    $mapFile = Get-UiMarkMapPath -Window $Window
    ($Marks | Select-Object Index,Type,Name,AutomationId,Class,Enabled,Patterns,CanInvoke,DefaultAction,
                          X,Y,W,H,CX,CY,Source) |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $mapFile -Encoding UTF8
    return $mapFile
}

function Invoke-UiMarkClick {
    <# Click by mark index (indices come from the last 'som' run). #>
    param([Parameter(Mandatory)][int64]$Window, [Parameter(Mandatory)][int]$Index,
          [switch]$Message, [switch]$Refresh, [switch]$PreferAction)
    $marks = Get-UiMark -Window $Window
    if (-not $marks) {
        <# No saved table: build one live so 'marks' and 'somclick' can be used independently. #>
        $marks = @(Get-UiMarks -Window $Window -Max 200)
        if ($marks.Count -gt 0) { [void](Save-UiMarks -Window $Window -Marks $marks) }
    }
    if (-not $marks) { throw "no interactive elements found for this window" }
    $m = $marks | Where-Object { $_.Index -eq $Index } | Select-Object -First 1
    if (-not $m) { throw "mark $Index does not exist (table has $(@($marks).Count) entries)" }
    <# -PreferAction: run the MSAA default action when available (no mouse, no focus change). #>
    if ($PreferAction -and $m.CanInvoke) {
        $pt = New-Object UiKit+POINT; $pt.X = [int]$m.CX; $pt.Y = [int]$m.CY
        $h = [UiKit]::WindowFromPoint($pt)
        try {
            $act = Invoke-UiMsaaAction -Handle ([int64]$h)
            return $m
        } catch { }
    }
    if ($Message) {
        $h = Resolve-UiTarget -Window $Window -Id ([int]($m.AutomationId -replace 'ID:','')) -ErrorAction SilentlyContinue
        if ($h) { [void](Assert-UiSafeInteract -Window $Window); Invoke-UiClick -Handle ([int64]$h) -Message; return $m }
    }
    [void](Assert-UiSafeInteract -Window $Window)
    [void](Assert-UiPointOwned -X $m.CX -Y $m.CY -Handle $Window -Retries 2)
    Invoke-UiMouseButton -Kind 'click' -X $m.CX -Y $m.CY -Window $Window
    if ($Refresh) { Start-Sleep -Milliseconds 300 }
    return $m
}
