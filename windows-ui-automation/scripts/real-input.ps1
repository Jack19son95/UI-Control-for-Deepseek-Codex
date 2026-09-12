# Convenience wrapper: real mouse/keyboard input through Invoke-UiSteps - the same step vocabulary as
# `ui.ps1 steps` (win: activate click: msgclick: dblclick: rclick: clicktext: clickxy: type: paste:
# key: set: check: combo: tab: cmd: drag: wheel: move: wait: waitwin: waittext: uia: shot: log:).
#
#   real-input.ps1 -Window 123456 -Do "activate|type:hello|key:CTRL+A|wait:300|shot:C:\temp\a.png"
#   real-input.ps1 -Process notepad -Do "activate|type:hello|key:ENTER"
#   real-input.ps1 -Do "move:400,300|clickxy:400,300"      # no window = use the foreground window
param(
    [string]$Window = "",
    [string]$Process = "",
    [string]$Do = "",
    [int]$SettleMs = 300,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "uikit.ps1")
Initialize-UiKit

if (-not $Window) {
    if ($Process) {
        $w = @(Get-UiWindow -Process $Process -VisibleOnly | Where-Object { $_.W -gt 120 } | Select-Object -First 1)
        if (-not $w) { throw "no visible window found for process $Process" }
    } else {
        $w = @(Get-UiWindow -VisibleOnly | Where-Object { $_.Foreground } | Select-Object -First 1)
        if (-not $w) { throw "no foreground window found; pass -Window or -Process" }
    }
    $Window = [string]$w.Handle
}

if (-not $Do) { Write-Output ("resolved target window handle: " + $Window); return }
if ($DryRun) { Write-Output ("DRY-RUN target=" + $Window + "  steps=" + $Do); return }
<# -Window takes a handle or a title keyword, exactly like the CLI. #>
$h = if ($Window -match '^\d+$') { [int64]$Window } else { [int64](Get-UiWindowByTitle -Title $Window).Handle }
[void](Invoke-UiSteps -Steps $Do -Window $h -Force:$Force)
Start-Sleep -Milliseconds $SettleMs
