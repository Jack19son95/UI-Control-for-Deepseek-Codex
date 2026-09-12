# Convenience wrapper: list windows or dump a control tree (engine logic lives in uikit.ps1/ui.ps1).
#
#   list-windows.ps1                       # every visible top-level window
#   list-windows.ps1 -Process notepad      # only that process
#   list-windows.ps1 -Window 123456 -Tree  # control tree (with control IDs)
param(
    [string]$Process = "",
    [string]$Window = "",
    [int]$Depth = 5,
    [switch]$Tree,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "uikit.ps1")
Initialize-UiKit

if ($Tree) {
    $h = if ($Window) { [int64]$Window }
         else {
             $w = @(Get-UiWindow -Process $Process -VisibleOnly |
                    Where-Object { $_.W -gt 120 -and $_.H -gt 80 } | Select-Object -First 1)
             if (-not $w) { throw "no usable target window found (pass -Window <handle> explicitly)" }
             [int64]$w.Handle
         }
    $t = Get-UiTree -Window $h -Depth $Depth
    if ($Json) { $t | ConvertTo-Json -Depth 5 } else { $t | Format-Table -AutoSize }
    return
}

$list = Get-UiWindow -Process $Process -VisibleOnly
if ($Json) { $list | ConvertTo-Json -Depth 6 }
else { $list | Select-Object Handle,Pid,Process,Class,Title,X,Y,W,H,Dpi,Visible,Safe,PreExisting |
                   Format-Table -AutoSize }
