# Convenience wrapper: message-level control (no mouse movement, no focus change)
#
#   drive-controls.ps1 -Window <handle> -Click 101,102             # BM_CLICK by control ID
#   drive-controls.ps1 -Window <handle> -SetText "201=hello|202=world"
#   drive-controls.ps1 -Window <handle> -DismissOk                 # close a dialog of that process
#   drive-controls.ps1 -Process notepad -SendCommand 1001          # post WM_COMMAND
#
# Message-level input is gated like real input: terminals/credentials are always refused, a user document
# window needs -Force.
param(
    [string]$Window = "",
    [string]$Process = "",
    [int[]]$Click = @(),
    [string]$SetText = "",
    [int]$SendCommand = 0,
    [string]$Shot = "",
    [int]$Delay = 250,
    [switch]$Force,
    [switch]$DismissOk,
    [switch]$DismissCancel,
    [int]$DismissCount = 1,
    [switch]$Kill
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "uikit.ps1")
Initialize-UiKit

if (-not $Window) {
    if (-not $Process) { throw "-Window <handle> or -Process <name> is required" }
    $w = @(Get-UiWindow -Process $Process -VisibleOnly | Where-Object { $_.W -gt 120 } | Select-Object -First 1)
    if (-not $w) { throw "no visible window found for process $Process" }
    $Window = [string]$w.Handle
}
$h = if ($Window -match '^\d+$') { [int64]$Window } else { [int64](Get-UiWindowByTitle -Title $Window).Handle }

foreach ($id in $Click) {
    Invoke-UiClick -Handle ([int64](Resolve-UiTarget -Window $h -Id $id)) -Message -Force:$Force | Out-Null
    Start-Sleep -Milliseconds $Delay
}

foreach ($pair in ($SetText -split '\|')) {
    if (-not $pair.Trim()) { continue }
    $i = $pair.IndexOf('=')
    if ($i -lt 1) { continue }
    [void](Set-UiText -Handle ([int64](Resolve-UiTarget -Window $h -Id ([int]$pair.Substring(0, $i)))) `
                      -Text $pair.Substring($i + 1) -Force:$Force)
    Start-Sleep -Milliseconds $Delay
}

if ($SendCommand -ne 0) { Invoke-UiCommand -Window $h -CommandId $SendCommand -Force:$Force; Write-Output "cmd=$SendCommand" }

for ($n = 0; $n -lt $DismissCount; $n++) {
    if ($DismissOk)     { if (Close-UiDialog -Window $h -Choice 'ok')     { Write-Output "dialog closed (ok)" } }
    if ($DismissCancel) { if (Close-UiDialog -Window $h -Choice 'cancel') { Write-Output "dialog closed (cancel)" } }
    Start-Sleep -Milliseconds 300
}

if ($Shot) {
    $r = Invoke-UiShotWithPlan -Out $Shot -Window $h
    Write-Output ("saved " + $r.Image + "   (full resolution " + $r.Dimensions + ")")
    Write-Output (Format-UiReadAdvice -Path $r.Image)
}
if ($Kill -and $Process) { Get-Process -Name $Process -ErrorAction SilentlyContinue | Stop-Process -Force }
