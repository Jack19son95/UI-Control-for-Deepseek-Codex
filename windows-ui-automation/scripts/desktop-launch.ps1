# desktop-launch.ps1 -- launch an app the human way (SKILL.md rule 6) with a verified landing point.
#
#   pwsh -File desktop-launch.ps1 icons                        list desktop icons (physical rects)
#   pwsh -File desktop-launch.ps1 find    "<name>"             resolve a desktop icon
#   pwsh -File desktop-launch.ps1 verify  "<name>"             resolve + move cursor + prove the landing point (no click)
#   pwsh -File desktop-launch.ps1 dclick  "<name>" [-DryRun]   verified real double-click on the desktop icon
#   pwsh -File desktop-launch.ps1 launch  "<name>" [-DryRun]   rule 6 order: desktop icon -> shortcut fallback
#   pwsh -File desktop-launch.ps1 click   -X <n> -Y <n> [-Window <h>]   verified real click at physical coords
#
# Enumeration and clicking both happen inside this DPI-aware process, so they share one coordinate space;
# the landing point is proven with Assert-UiPointOwned before any real input, and the effect is confirmed
# afterwards (a new top-level window must appear). Nothing is clicked blindly.

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Cmd = 'help',
    [Parameter(Position = 1)][string]$Name = '',
    [int]$X = [int]::MinValue,
    [int]$Y = [int]::MinValue,
    [int64]$Window = 0,
    [switch]$DryRun,
    [switch]$NoShowDesktop,
    [int]$Timeout = 8
)

. (Join-Path $PSScriptRoot "uikit.ps1")
Initialize-UiKit

<# FindWindowEx returns 0 for the shell's desktop list on this build, so walk the tree instead.
   Compiled through the shared cache (Import-UiKitType), which is ~20 ms instead of ~0.5 s per run. #>
Import-UiKitType -Name 'DeskFind' -Source @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class DeskFind {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr p);
  delegate bool EnumProc(IntPtr h, IntPtr p);
  public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
  public static List<IntPtr> Kids(IntPtr root) {
    var res = new List<IntPtr>();
    EnumChildWindows(root, (h, p) => { res.Add(h); return true; }, IntPtr.Zero);
    return res;
  }
}
'@

function Find-DesktopListView {
    <# The icon list is SysListView32 under SHELLDLL_DefView, hosted by Progman or a WorkerW. #>
    $roots = @(Get-UiWindow | Where-Object { $_.Class -eq 'Progman' -or $_.Class -eq 'WorkerW' })
    foreach ($root in $roots) {
        foreach ($c in [DeskFind]::Kids([IntPtr]$root.Handle)) {
            if ([DeskFind]::Cls($c) -ne 'SysListView32') { continue }
            $rect = [UiKit]::RectOf($c)
            if ($rect.Width -le 0 -or $rect.Height -le 0) { continue }
            try {
                $acc = [Msaa]::Client($c)
                if ($acc -and $acc.accChildCount -gt 0) { return $c }
            } catch { }
        }
    }
    return [IntPtr]::Zero
}

function Get-DesktopIcon {
    <# MSAA children of the desktop list = the icons, with physical rects (this process is DPI aware). #>
    param([string]$Match = '')
    $lv = Find-DesktopListView
    if ($lv -eq [IntPtr]::Zero) { throw "desktop icon list not found" }
    $acc = [Msaa]::Client($lv)
    if (-not $acc) { throw "desktop list has no accessibility tree (MSAA unavailable)" }
    $items = New-Object System.Collections.Generic.List[object]
    for ($i = 1; $i -le $acc.accChildCount; $i++) {
        try { $n = $acc.accName($i) } catch { continue }
        if (-not $n) { continue }
        $ix = 0; $iy = 0; $iw = 0; $ih = 0
        try { $null = $acc.accLocation([ref]$ix, [ref]$iy, [ref]$iw, [ref]$ih, $i) } catch { continue }
        if ($iw -le 0 -or $ih -le 0) { continue }
        $items.Add([pscustomobject]@{
            Name = "$n"; X = $ix; Y = $iy; W = $iw; H = $ih; ListView = [int64]$lv
        })
    }
    if (-not $Match) { return $items }
    $exact = @($items | Where-Object { $_.Name -eq $Match })
    if ($exact.Count -ge 1) { return $exact }
    return @($items | Where-Object { $_.Name -like "*$Match*" })
}

function Get-IconPoint {
    <# Aim at the icon glyph (upper part of the cell); the label below it is not the hit target. #>
    param($Icon)
    return [pscustomobject]@{ X = [int]($Icon.X + $Icon.W / 2); Y = [int]($Icon.Y + $Icon.H * 0.32) }
}

function Assert-LandingPoint {
    param($Icon, $Point)
    Assert-UiPointOwned -X $Point.X -Y $Point.Y -Handle ([int64]$Icon.ListView) -Retries 2 | Out-Null
}

function Show-DesktopFor {
    <# Make the icon clickable: reuse the shell shortcut, else minimise whatever covers the point. #>
    param($Icon, $Point)
    try { Assert-LandingPoint $Icon $Point; return 'already visible' } catch { }
    if (-not $NoShowDesktop) {
        try { Invoke-UiKey -Keys 'WIN+D'; Start-Sleep -Milliseconds 800 } catch { }
        try { Assert-LandingPoint $Icon $Point; return 'desktop shown (WIN+D)' } catch { }
        $moved = New-Object System.Collections.Generic.List[string]
        foreach ($w in @(Get-UiWindow -VisibleOnly)) {
            if (@('Progman', 'WorkerW', 'Shell_TrayWnd') -contains $w.Class) { continue }
            $r = [UiKit]::RectOf([IntPtr]$w.Handle)
            if ($Point.X -ge $r.Left -and $Point.X -lt ($r.Left + $r.Width) -and
                $Point.Y -ge $r.Top -and $Point.Y -lt ($r.Top + $r.Height)) {
                Set-UiWindowState -Window ([int64]$w.Handle) -State min
                $moved.Add("$($w.Process)#$($w.Handle)")
            }
        }
        Start-Sleep -Milliseconds 500
        try {
            Assert-LandingPoint $Icon $Point
            return ("desktop shown (minimised blockers: " + ($moved -join ', ') + ")")
        } catch { }
    }
    $owner = Get-UiPointOwner -X $Point.X -Y $Point.Y
    $who = try { (Get-Process -Id ([UiKit]::PidOf([IntPtr]$owner.Handle)) -ErrorAction Stop).ProcessName } catch { '?' }
    throw ("landing point $($Point.X),$($Point.Y) is still covered by ${who}: refusing to click blindly")
}

function Invoke-VerifiedIconDoubleClick {
    param($Icon, [switch]$AsDryRun)
    $pt = Get-IconPoint $Icon
    $reveal = Show-DesktopFor $Icon $pt
    [void][UiKit]::SetCursorPos($pt.X, $pt.Y); Start-Sleep -Milliseconds 130
    $p = New-Object UiKit+POINT; [void][UiKit]::GetCursorPos([ref]$p)
    if ([Math]::Abs($p.X - $pt.X) -gt 2 -or [Math]::Abs($p.Y - $pt.Y) -gt 2) {
        throw "cursor readback mismatch: asked $($pt.X),$($pt.Y) got $($p.X),$($p.Y)"
    }
    Assert-LandingPoint $Icon $pt
    if ($AsDryRun) {
        return [pscustomobject]@{ Icon = $Icon.Name; Point = "$($pt.X),$($pt.Y)"; Reveal = $reveal; Clicked = $false }
    }
    $before = @(Get-UiWindow -VisibleOnly | ForEach-Object { [int64]$_.Handle })
    Invoke-UiMouseButton -Button left -Kind double -X $pt.X -Y $pt.Y -Window ([int64]$Icon.ListView)
    $deadline = (Get-Date).AddSeconds($Timeout)
    $new = $null
    while (-not $new -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
        $new = Get-UiWindow -VisibleOnly | Where-Object { $before -notcontains [int64]$_.Handle } | Select-Object -First 1
    }
    return [pscustomobject]@{
        Icon = $Icon.Name; Point = "$($pt.X),$($pt.Y)"; Reveal = $reveal; Clicked = $true
        NewWindow = if ($new) { "$($new.Handle) $($new.Process) - $($new.Title)" } else { 'NONE (no new window appeared)' }
    }
}

switch ($Cmd.ToLower()) {
    'icons' { Get-DesktopIcon | Select-Object Name, X, Y, W, H | Format-Table -AutoSize }
    'find' {
        $hits = @(Get-DesktopIcon -Match $Name)
        if ($hits.Count -eq 0) { Write-Output "NOT_FOUND $Name" }
        else { $hits | Select-Object Name, X, Y, W, H | Format-Table -AutoSize }
    }
    'verify' {
        $icon = @(Get-DesktopIcon -Match $Name) | Select-Object -First 1
        if (-not $icon) { throw "no desktop icon matches '$Name'" }
        Invoke-VerifiedIconDoubleClick -Icon $icon -AsDryRun | Format-List
    }
    'dclick' {
        $icon = @(Get-DesktopIcon -Match $Name) | Select-Object -First 1
        if (-not $icon) { throw "no desktop icon matches '$Name'" }
        Invoke-VerifiedIconDoubleClick -Icon $icon -AsDryRun:$DryRun | Format-List
    }
    'launch' {
        $icon = @(Get-DesktopIcon -Match $Name) | Select-Object -First 1
        if ($icon) { Invoke-VerifiedIconDoubleClick -Icon $icon -AsDryRun:$DryRun | Format-List; break }
        $hit = @(Find-UiShortcut -Name $Name | Select-Object -First 1)
        if (-not $hit) { Write-Output "NOT_FOUND: no desktop icon and no Start Menu/Desktop shortcut matches '$Name'"; break }
        $res = Start-UiFromShortcut -Name $Name -PassThru
        Write-Output ("no desktop icon; launched from shortcut: " + $res.Shortcut.Name + " (" + $res.Shortcut.Path + ")")
    }
    'click' {
        if ($X -eq [int]::MinValue -or $Y -eq [int]::MinValue) { throw "click needs -X and -Y (physical pixels)" }
        [void](Assert-UiSafePoint -X $X -Y $Y -Window $Window)
        if ($Window -ne 0) { Assert-UiPointOwned -X $X -Y $Y -Handle $Window -Retries 2 | Out-Null }
        [void][UiKit]::SetCursorPos($X, $Y); Start-Sleep -Milliseconds 130
        $p = New-Object UiKit+POINT; [void][UiKit]::GetCursorPos([ref]$p)
        if ([Math]::Abs($p.X - $X) -gt 2 -or [Math]::Abs($p.Y - $Y) -gt 2) {
            throw "cursor readback mismatch: asked $X,$Y got $($p.X),$($p.Y)"
        }
        Invoke-UiMouseButton -Button left -Kind click -X $X -Y $Y -Window $Window
        Write-Output "clicked-verified $X,$Y"
    }
    default {
        @'
desktop-launch.ps1 -- human-order launching with a verified landing point (all coords are physical pixels)

  icons                          list desktop icons
  find    "<name>"               resolve a desktop icon
  verify  "<name>"               measure + move cursor + prove the landing point, no click
  dclick  "<name>" [-DryRun]     verified real double-click on that icon
  launch  "<name>" [-DryRun]     rule 6: desktop icon first, Start Menu/shortcut only otherwise
  click   -X n -Y n [-Window h]  verified real click at absolute physical coordinates

  -NoShowDesktop   do not try WIN+D / minimising blockers when the icon is covered
  -Timeout n       seconds to wait for the launched window to appear (default 8)
'@ | Write-Output
    }
}
