# Convenience wrapper: capture a window or a monitor (engine logic lives in uikit.ps1/ui.ps1).
#
#   capture-window.ps1 -Out shot.png                    # foreground window
#   capture-window.ps1 -Out shot.png -Process notepad   # main window of a process
#   capture-window.ps1 -Out shot.png -Window 123456     # by window handle
#   capture-window.ps1 -Out shot.png -Monitor 0 -Cursor # monitor 0 with the cursor drawn
#
# Always full resolution; the reply carries the out-of-band read line (`look`), never a direct read.
param(
    [string]$Out = "shot.png",
    [string]$Process = "",
    [string]$Window = "",
    [int]$Monitor = -1,
    [string]$Region = "",
    [int]$MaxWidth = 0,   # 0 = full resolution: pass a number only to shrink the capture on purpose
    [int]$WaitMs = 800,
    [switch]$Cursor,
    [switch]$Print,
    [switch]$TopMost,
    [switch]$Kill
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "uikit.ps1")
Initialize-UiKit

if ($WaitMs -gt 0) { Start-Sleep -Milliseconds $WaitMs }

if (-not $Window) {
    if ($Process) {
        $w = @(Get-UiWindow -Process $Process -VisibleOnly | Where-Object { $_.W -gt 120 } | Select-Object -First 1)
        if (-not $w) { throw "no visible window found for process $Process" }
    } else {
        $w = @(Get-UiWindow -VisibleOnly | Where-Object { $_.Foreground } | Select-Object -First 1)
        if (-not $w) { throw "no foreground window found" }
    }
    $Window = [string]$w.Handle
}
$h = if ($Window -match '^\d+$') { [int64]$Window } else { [int64](Get-UiWindowByTitle -Title $Window).Handle }

if ($TopMost) { Set-UiWindowTopMost -Window $h }
$reg = if ($Region) { [int[]]($Region -split ',') } else { $null }
$r = Invoke-UiShotWithPlan -Out $Out -Window $h -Monitor $Monitor -Region $reg `
                           -Cursor:$Cursor -Print:$Print -MaxWidth $MaxWidth
if ($TopMost) { Set-UiWindowTopMost -Window $h -Off }
if ($Kill -and $Process) { Get-Process -Name $Process -ErrorAction SilentlyContinue | Stop-Process -Force }

Write-Output ($r.Image + "   (full resolution " + $r.Dimensions + ", " + [Math]::Round($r.Bytes / 1KB) + " KB)")
Write-Output (Format-UiReadAdvice -Path $r.Image)
