# ============================================================================
# ui.ps1 -- command line front end for the Windows UI automation core (uikit.ps1)
#
#   ui.ps1 <command> [options...]
#
#   windows   list windows        ui.ps1 windows [-Process name] [-Title keyword] [-Visible] [-Tree]
#   monitors  monitor information
#   procs     list processes      ui.ps1 procs [-Name keyword]
#   tree      control tree        ui.ps1 tree -Window <handle|title>
#   focus     focused control     ui.ps1 focus -Window <handle|title>
#   activate  bring to front      ui.ps1 activate -Window <handle|title> [-Id controlId]
#   move      move/resize window  ui.ps1 move -Window <handle|title> -X -Y -W -H
#   state     min/max/restore     ui.ps1 state -Window <handle|title> -State min|max|normal
#   topmost   always on top       ui.ps1 topmost -Window <handle|title> [-Off]
#   click     click               ui.ps1 click -Window <handle|title> [-Id controlId] [-Text t] [-XY x,y] [-Button left|right|middle] [-Double] [-Message]
#   type      type text           ui.ps1 type -Text "..." [-Raw]        (goes to the focused window: activate first)
#   key       key chord           ui.ps1 key -Keys "CTRL+S"              (goes to the focused window)
#   drag      drag                ui.ps1 drag -From x,y -To x,y [-Button left|right]
#   wheel     mouse wheel         ui.ps1 wheel [-XY x,y] [-Delta -360]
#   Safety: clicks / keys / drags / wheel are refused on terminals, consoles, security & credential UI,
#           password managers and the Codex window; typing also refuses user document windows. -Force
#           relaxes the document rule only (never the hard categories).
#   cursor    cursor position     ui.ps1 cursor
#   get       read text           ui.ps1 get -Handle <controlHandle> | ui.ps1 get -Window <handle> -Id <controlId>
#   set       write text          ui.ps1 set -Window <handle> -Id <controlId> -Text "value"
#   check     check/uncheck       ui.ps1 check -Window <handle> -Id <controlId> [-Off]
#   combo     select combo item   ui.ps1 combo -Window <handle> -Id <controlId> -Index 0
#   tab       switch tab          ui.ps1 tab -Window <handle> -Id <controlId> -Index 1
#   cmd       post WM_COMMAND     ui.ps1 cmd -Window <handle> -CommandId 1205
#   list      list summary        ui.ps1 list -Window <handle> -Id <controlId>
#   dismiss   close a dialog      ui.ps1 dismiss -Window <handle> [-Choice ok|yes|cancel]
#   marks     index of clickable elements   ui.ps1 marks -Window <handle> [-Max n] [-Json]
#   som       numbered screenshot           ui.ps1 som -Window <handle> -Out <png> [-Max n]
#   somclick  click by mark index           ui.ps1 somclick -Window <handle> -Index n [-PreferAction|-Message]
#   msaa      MSAA roles/actions            ui.ps1 msaa -Window <handle> [-Json]
#   msaaaction run an MSAA default action  ui.ps1 msaaaction -Window <handle> -Id <controlId>
#   occluders list covering windows        ui.ps1 occluders -Window <handle> [-Json]
#   reveal    occlusion rescue             ui.ps1 reveal -Window <handle> [-Strategy auto|activate|minimize|move|close|taskbar|search] [-AllowClose]
#   taskbar   switch via taskbar           ui.ps1 taskbar -Name <title keyword>
#   searchapp search Start Menu/Desktop/UWP apps   ui.ps1 searchapp -Name <name> [-Path <name>]
#   restore   restore a minimised window   ui.ps1 restore -Name <title keyword>
#   typein    focus then type     ui.ps1 typein -Window <handle> [-Id <controlId>] -Text "..." [-Raw]
#   decide    decide whether UI automation is needed   ui.ps1 decide -Task "..." [-Explicit|-NoApi|-Visual|-Cheaper]
#   newbaseline rebuild the window baseline            ui.ps1 newbaseline
#   shot      screenshot          ui.ps1 shot -Out path [-Window handle] [-Monitor 0] [-Region x,y,w,h] [-Cursor] [-Print] [-MaxWidth n]
#             Always full resolution (same frame, same pixels). The reply carries the read line: hand the
#             PNG to `look` - a UI capture never goes into this conversation.
#   look      out-of-band read     ui.ps1 look -Path shot.png [-Ask "question"] [-Keep] [-LookTimeout 240]
#             A throw-away Codex run gets the full-resolution file and returns text only; the picture is
#             deleted the moment the read is over, so no picture byte ever enters this conversation.
#   cleanup   delete a shot       ui.ps1 cleanup -Path shot.png [-Force]   (a picture that is not needed any more)
#   budget    context status      ui.ps1 budget   (live conversation size + shots still waiting on disk)
#   wait      wait for a condition  ui.ps1 wait -Window <handle> [-Visible] [-Foreground] [-Timeout 8000]
#   uia       modern app elements   ui.ps1 uia tree -Window <handle> [-Depth 3]
#                                   ui.ps1 uia find -Window <handle> [-Name text] [-AutomationId id] [-Deep]
#                                   ui.ps1 uia invoke -Window <handle> -Name text [-Action Invoke|Select|SetValue] [-Value v]
#   clip      clipboard           ui.ps1 clip [-Set "text"]
#   open      launch app / URL    ui.ps1 open -Path notepad.exe | -Url https://example.com
#   steps     batch steps         ui.ps1 steps -Window <handle|title> -Do "activate|type:hello|key:ENTER|shot:a.png" [-Force]
#   log       action log          ui.ps1 log [-Tail 20]
#   selftest  environment self-check
# ============================================================================
param(
    [Parameter(Position=0)][string]$Command = "help",
    [Parameter(Position=1)][string]$Sub = "",
    [string]$Window = "", [int]$Id = [int]::MinValue, [int64]$Handle = 0,
    [string]$Text, [string]$Keys, [string]$From, [string]$To, [string]$XY,
    [string]$Process, [string]$Title, [string]$Class, [string]$Name, [string]$AutomationId,
    [string]$Out, [string]$Value, [string]$Do, [string]$Path, [string]$Url, [string]$Set,
    [ValidateSet('auto','activate','minimize','move','close','taskbar','search')][string]$Strategy = 'auto',
    [switch]$AllowClose, [switch]$Explicit, [switch]$NoApi, [switch]$Visual, [switch]$Cheaper,
    [string]$Task,
    [int]$Index = 0, [int]$CommandId = 0, [int]$Delta = -360, [int]$Timeout = 8000,
    <# -MaxWidth: 0 (default) captures at full resolution; pass a number only to shrink the capture on purpose.
       For 'som' it doubles as the mark limit (-Max), which defaults to 1560 when unset. #>
    [int]$Depth = 3, [int]$Tail = 20, [int]$MaxWidth = 0,
    [string]$Ask, [int]$LookTimeout = 240,
    [ValidateSet('left','right','middle')][string]$Button = 'left',
    [ValidateSet('min','max','normal','restore','hide')][string]$State = 'normal',
    [ValidateSet('Invoke','Select','SetValue','Expand','Collapse','Toggle','Focus','ScrollIntoView')][string]$Action = 'Invoke',
    <# Note: PowerShell variable names are case-insensitive, so window geometry parameters
       use WinX/WinY/WinW/WinH to avoid clashing with local $x/$y/$w/$h (-X/-Y/-W/-H stay as aliases). #>
    [Alias('X')][int]$WinX = [int]::MinValue,
    [Alias('Y')][int]$WinY = [int]::MinValue,
    [Alias('W')][int]$WinW = 0,
    [Alias('H')][int]$WinH = 0,
    [int]$Monitor = -1, [string]$Region,
    [switch]$Visible, [switch]$Tree, [switch]$Double, [switch]$Message,
    [switch]$Cursor, [switch]$Print, [switch]$Off, [switch]$Deep, [switch]$Foreground,
    [switch]$RectStable, [switch]$Json, [switch]$Force, [switch]$NewOnly, [switch]$Raw, [switch]$Keep,
    [switch]$PreferAction, [ValidateSet('ok','yes','cancel')][string]$Choice = 'ok'
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "uikit.ps1")
Initialize-UiKit

function Resolve-WindowArg {
    <# -Window accepts a numeric handle or a title keyword. #>
    param([string]$Value)
    if (-not $Value) { throw "-Window <handle|title> is required" }
    $n = 0
    if ([int64]::TryParse($Value, [ref]$n)) { return [int64]$n }
    return [int64](Get-UiWindowByTitle -Title $Value).Handle
}
function Show($obj) {
    if ($Json) { $obj | ConvertTo-Json -Depth 6 } else { $obj | Format-Table -AutoSize }
}

switch ($Command.ToLower()) {
    'windows' {
        $list = Get-UiWindow -Process $Process -Title $Title -Class $Class -VisibleOnly:$Visible -IncludeChildren:$Tree -NewOnly:$NewOnly
        if ($Foreground) { $list = @($list | Where-Object { $_.Foreground }) }
        if ($Json) { $list | ConvertTo-Json -Depth 6 } else {
            $list | Select-Object Handle,Pid,Process,Class,Title,X,Y,W,H,Dpi,Visible,Safe,PreExisting | Format-Table -AutoSize }
    }
    'monitors' { Show (Get-UiMonitor) }
    'procs' {
        $p = if ($Name) { Get-Process | Where-Object { $_.ProcessName -like "*$Name*" } } else { Get-Process }
        $p | Select-Object Id,ProcessName,MainWindowTitle,@{n='Handle';e={[int64]$_.MainWindowHandle}} |
            Sort-Object ProcessName | Format-Table -AutoSize
    }
    'tree' {
        $h = Resolve-WindowArg $Window
        $t = Get-UiTree -Window $h -Depth $Depth
        if ($Json) { $t | ConvertTo-Json -Depth 5 } else { $t | Format-Table -AutoSize }
    }
    'focus' { Show (Get-UiFocusedControl -Window (Resolve-WindowArg $Window)) }
    'activate' {
        $h = Resolve-WindowArg $Window
        $c = if ($Id -ne [int]::MinValue) { [int64](Resolve-UiTarget -Window $h -Id $Id) } else { 0 }
        $ok = Set-UiFocus -Window $h -Control $c
        Write-Output ("activated=" + $ok)
    }
    'move' { Set-UiWindowRect -Window (Resolve-WindowArg $Window) -X $WinX -Y $WinY -W $WinW -H $WinH -Activate }
    'state' { Set-UiWindowState -Window (Resolve-WindowArg $Window) -State $State; Write-Output "state=$State" }
    'topmost' { Set-UiWindowTopMost -Window (Resolve-WindowArg $Window) -Off:$Off; Write-Output ("topmost=" + (-not $Off)) }
    'click' {
        $h = Resolve-WindowArg $Window
        if ($XY) {
            $xy = $XY -split ','; Invoke-UiMouseButton -Button $Button -Kind $(if($Double){'double'}else{'click'}) -X ([int]$xy[0]) -Y ([int]$xy[1]) -Window $h -Force:$Force
            Write-Output "clicked xy=$XY"
        } else {
            $target = if ($Id -ne [int]::MinValue) { Resolve-UiTarget -Window $h -Id $Id }
                      elseif ($Text) { Resolve-UiTarget -Window $h -Text $Text }
                      elseif ($Class) { Resolve-UiTarget -Window $h -Class $Class }
                      else { [IntPtr]$h }
            $r = Invoke-UiClick -Handle ([int64]$target) -Message:$Message -Button $Button -Double:$Double -Force:$Force
            Write-Output ("clicked handle=" + ([int64]$target) + $(if ($r) { " at $($r.X),$($r.Y)" } else { "" }))
        }
    }
    'type' { Send-UiText -Text $Text -Raw:$Raw -Force:$Force; Write-Output ("typed " + $Text.Length + " chars" + $(if ($Raw) { " (raw unicode)" } else { " (clipboard paste)" })) }
    'typein' {
        <# Ensure focus with Assert-UiForeground before typing (recommended when switching apps). #>
        $h = Resolve-WindowArg $Window
        [void](Assert-UiSafeToType -Window $h -Force:$Force)
        $c = if ($Id -ne [int]::MinValue) { [int64](Resolve-UiTarget -Window $h -Id $Id) } else { 0 }
        [void](Assert-UiForeground -Window $h -Control $c)
        Send-UiText -Text $Text -Raw:$Raw -Force:$Force
        Write-Output ("typed " + $Text.Length + " chars into " + $h)
    }
    'key'  { Send-UiKeys -Keys $Keys -Force:$Force; Write-Output "keys=$Keys" }
    'drag' {
        $a = $From -split ','; $b = $To -split ','
        $dh = if ($Window) { Resolve-WindowArg $Window } else { 0 }
        Invoke-UiDrag -X1 ([int]$a[0]) -Y1 ([int]$a[1]) -X2 ([int]$b[0]) -Y2 ([int]$b[1]) -Button $Button -Handle $dh -Force:$Force
        Write-Output "dragged $From -> $To"
    }
    'wheel' {
        $wh = if ($Window) { Resolve-WindowArg $Window } else { 0 }
        if ($XY) { $xy = $XY -split ','; Invoke-UiWheel -X ([int]$xy[0]) -Y ([int]$xy[1]) -Delta $Delta -Window $wh -Force:$Force }
        else { Invoke-UiWheel -Delta $Delta -Force:$Force }
        Write-Output "wheel delta=$Delta"
    }
    'cursor' { Show (Get-UiCursor) }
    'get' {
        $h = if ($Handle) { $Handle }
             elseif ($Id -ne [int]::MinValue -or -not $Class) { [int64](Resolve-UiTarget -Window (Resolve-WindowArg $Window) -Id $Id) }
             else { [int64](Resolve-UiTarget -Window (Resolve-WindowArg $Window) -Class $Class) }
        Write-Output (Get-UiText -Handle $h)
    }
    'set' {
        $h = Resolve-UiTarget -Window (Resolve-WindowArg $Window) -Id $Id
        Write-Output (Set-UiText -Handle ([int64]$h) -Text $Text -Force:$Force)
    }
    'check' {
        $h = Resolve-UiTarget -Window (Resolve-WindowArg $Window) -Id $Id
        Set-UiCheck -Handle ([int64]$h) -Checked (-not $Off)
        Write-Output ("checked=" + (Get-UiCheck -Handle ([int64]$h)))
    }
    'combo' {
        $h = Resolve-UiTarget -Window (Resolve-WindowArg $Window) -Id $Id
        Set-UiComboSelect -Handle ([int64]$h) -Index $Index
        Show (Get-UiComboInfo -Handle ([int64]$h))
    }
    'tab' {
        $h = Resolve-UiTarget -Window (Resolve-WindowArg $Window) -Id $Id
        Set-UiTabSelect -Handle ([int64]$h) -Index $Index
        Show (Get-UiTabInfo -Handle ([int64]$h))
    }
    'cmd' { Invoke-UiCommand -Window (Resolve-WindowArg $Window) -CommandId $CommandId -Force:$Force; Write-Output "cmd=$CommandId" }
    'list' {
        $h = Resolve-UiTarget -Window (Resolve-WindowArg $Window) -Id $Id
        Show (Get-UiListInfo -Handle ([int64]$h))
    }
    'shot' {
        <# Full-resolution capture; the line that follows hands it to the out-of-band reader. #>
        $w = if ($Window) { Resolve-WindowArg $Window } else { 0 }
        $reg = if ($Region) { [int[]]($Region -split ',') } else { $null }
        $r = Invoke-UiShotWithPlan -Out $Out -Window $w -Monitor $Monitor -Region $reg -Cursor:$Cursor -Print:$Print -MaxWidth $MaxWidth
        Write-Output ($r.Image + "   (full resolution " + $r.Dimensions + ", " + [Math]::Round($r.Bytes / 1KB) + " KB)")
        Write-Output (Format-UiReadAdvice -Path $r.Image)
    }
    'look' {
        <#
          Read a screenshot out of band: a throw-away Codex run gets the full-resolution file, answers the
          question, and the picture is deleted the moment the answer arrives. The image never enters this
          conversation, so nothing accumulates and no request can grow past the gateway limit.
        #>
        if (-not $Path) { throw "look needs -Path <image>" }
        $question = if ($Ask) { $Ask } elseif ($Text) { $Text } else { 'Describe what is visible and read out the text that matters.' }
        $r = Invoke-UiLook -Path $Path -Ask $question -Keep:$Keep -TimeoutSec $LookTimeout
        if ($r.Ok) {
            Write-Output $r.Answer
            Write-Output ("(full-resolution out-of-band read in " + $r.Seconds + "s" +
                          $(if ($r.Deleted) { "; image deleted" } elseif ($r.Kept) { "; image kept (-Keep)" } else { "; image kept" }) +
                          "; 0 picture bytes in this conversation)")
        } else {
            Write-Output ("LOOK-FAILED: " + $r.Error +
                          $(if ($r.Kept) { " - the image is still at " + $r.Path }
                            else { " - the picture was deleted as always; capture again if you still need it" }) +
                          "; fall back to the text channels (tree / marks -Json / uia text / msaa) or re-run look with -LookTimeout.")
        }
    }
    'budget' {
        <# How close this conversation is to the gateway limit, and what is still waiting to be read. #>
        $r = Get-UiContextReport
        if ($Json) {
            [pscustomobject]@{ BodyBytes = $r.BodyBytes; Dir = $r.Dir; Look = $r.Look
                               ShotCount = $r.ShotCount; ShotBytes = $r.ShotBytes
                               Shots = @($r.Shots | Select-Object Name,Length) } | ConvertTo-Json -Depth 4
        } else { Write-Output (Format-UiContextReport $r) }
    }
    'cleanup' {
        <#
          Delete one picture that is not needed any more - already read, or answered from the marks table.
          Nothing is ever deleted by age: `look` deletes its own picture, and this covers the rest, so
          between the two nothing lingers.
        #>
        if (-not $Path) { throw "cleanup needs -Path <image> (shots are never deleted by age; budget lists what is on disk)" }
        $full = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).Path
        $tempRoot = Get-UiTempDir
        if (-not $full) { Write-Output ("nothing to delete: " + $Path) }
        elseif ($full -notmatch '\.(png|jpg|jpeg|bmp)$') { Write-Output ("refusing to delete a non-picture path: " + $full) }
        elseif ((-not $Force) -and -not $full.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            <# Anything outside the skill's own temp folder is somebody else's file: needs -Force. #>
            Write-Output ("would delete " + $full + " (outside " + $tempRoot + " - re-run with -Force to confirm)")
        } else {
            if (Remove-UiTempPath -Path $full) { Write-Output ("deleted " + $full) }
            else { Write-Output ("could not delete " + $full) }
        }
    }
    'wait' {
        $h = if ($Window) { Resolve-WindowArg $Window } else { 0 }
        $ok = Wait-Ui -Window $h -Visible:$Visible -Foreground:$Foreground -RectStable:$RectStable -TimeoutMs $Timeout
        Write-Output ("wait=" + $ok)
    }
    'uia' {
        $h = Resolve-WindowArg $Window
        switch ($Sub.ToLower()) {
            'tree'   { $t = Get-UiaTree -Window $h -Depth $Depth; if ($Json) { $t | ConvertTo-Json -Depth 5 } else { $t | Format-Table -AutoSize } }
            'find'   { $el = Find-UiaElement -Window $h -Name $Name -AutomationId $AutomationId -Class $Class -Deep:$Deep -Index $Index
                       if (-not $el) { Write-Output "NOT_FOUND" } else {
                           [pscustomobject]@{ Name=$el.Current.Name; AutomationId=$el.Current.AutomationId
                                              Class=$el.Current.ClassName; ControlType=($el.Current.ControlType.ProgrammaticName -replace 'ControlType\.','')
                                              X=(ConvertTo-UiPixel $el.Current.BoundingRectangle.X); Y=(ConvertTo-UiPixel $el.Current.BoundingRectangle.Y)
                                              W=(ConvertTo-UiPixel $el.Current.BoundingRectangle.Width); H=(ConvertTo-UiPixel $el.Current.BoundingRectangle.Height) } | Format-List } }
            'value'  {
                <# Prefer ValuePattern; many elements (e.g. the calculator display) expose the value as Name, so fall back. #>
                $el = Find-UiaElement -Window $h -Name $Name -AutomationId $AutomationId -Class $Class -Deep:$Deep -Index $Index
                if (-not $el) { Write-Output "NOT_FOUND" }
                else {
                    $v = Get-UiaValue -Element $el
                    if (-not $v) { $v = [string]$el.Current.Name }
                    Write-Output $v
                }
            }
            'text'   { $el = if ($Name -or $AutomationId -or $Class) { Find-UiaElement -Window $h -Name $Name -AutomationId $AutomationId -Class $Class -Deep:$Deep -Index $Index } else { Get-UiaElement -Handle $h }
                       if (-not $el) { Write-Output "NOT_FOUND" } else { Write-Output (Get-UiaText -Element $el) } }
            'buttons'{ Get-UiaElements -Window $h -ControlType Button | Select-Object Index,Name,AutomationId,Enabled,X,Y,W,H | Format-Table -AutoSize }
            'invoke' { $el = Find-UiaElement -Window $h -Name $Name -AutomationId $AutomationId -Deep:$Deep -Index $Index
                       if (-not $el) { throw "UIA element not found: $Name$AutomationId" }
                       Invoke-UiaAction -Element $el -Action $Action -Value $Value
                       Write-Output "uia $Action ok" }
            default  { Write-Output "usage: ui.ps1 uia tree|find|invoke" }
        }
    }
    'clip' {
        if ($Set) { Set-UiClipboard -Text $Set; Write-Output "clipboard set" } else { Write-Output (Get-UiClipboard) }
    }
    'open' {
        if ($Url) { $w = Start-UiUrl -Url $Url } else { $w = Start-UiApp -Path $Path }
        $o = $w | Select-Object Handle,Pid,Process,Class,Title,X,Y,W,H,Dpi,Safe,PreExisting
        if ($Json) { $o | ConvertTo-Json -Depth 4 } else { $o | Format-List }
    }
    'steps' { $h = if ($Window) { Resolve-WindowArg $Window } else { 0 }
              Invoke-UiSteps -Steps $Do -Window $h -Force:$Force | Out-Null; Write-Output "steps done" }
    'log' {
        <# The log only exists once something has been logged: say so instead of throwing in a fresh session. #>
        $logPath = Get-UiLogPath
        if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail $Tail -Encoding UTF8 }
        else { Write-Output ("nothing logged yet: " + $logPath) }
    }
    'selftest' {
        Write-Output ("inner size : " + [UiKit]::InputSize() + " bytes (expected 40 on x64)")
        Write-Output ("DPI aware  : ok")
        Write-Output ("monitors   : " + @(Get-UiMonitor).Count)
        Write-Output ("windows    : " + @(Get-UiWindow -VisibleOnly).Count + " visible top-level windows")
        Initialize-Uia
        Write-Output ("UIA        : ok (desktop root: " + [System.Windows.Automation.AutomationElement]::RootElement.Current.Name + ")")
        Write-Output ("log        : " + (Get-UiLogPath))
    }
    'newbaseline' { Write-Output ("baseline rebuilt with " + (Reset-UiBaseline) + " windows (only windows opened after this count as NewOnly)") }
    'occluders' { $h = Resolve-WindowArg $Window; $o = @(Get-UiOccluders -Window $h)
                  if ($Json) { if ($o.Count -eq 0) { Write-Output "[]" } else { $o | ConvertTo-Json -Depth 5 } }
                  elseif ($o.Count -eq 0) { Write-Output "no occlusion: the target is already on top" }
                  else { $o | Format-Table -AutoSize } }
    'reveal' {
        $h = Resolve-WindowArg $Window
        $r = Invoke-UiReveal -Window $h -Strategy $Strategy -AllowClose:$AllowClose -TargetName $Name
        if ($Json) { $r | ConvertTo-Json -Depth 5 } else {
            Write-Output ("visible-and-usable = " + $r.Ok + "  target-in-foreground = " + $r.Foreground)
            foreach ($s in $r.Steps) { Write-Output ("  - " + $s) }
            if ($r.Occluders.Count -gt 0) { Write-Output "  still covered by:"; $r.Occluders | Select-Object Process,Title,Overlap | Format-Table -AutoSize }
        }
    }
    'taskbar' {
        $ok = Switch-UiTaskbar -Name $Name
        Write-Output ("taskbar switch = " + $ok)
    }
    'searchapp' {
        if ($Path) {
            $hit = Start-UiFromShortcut -Name $Path
            if ($Json) { $hit | ConvertTo-Json -Compress } else { Write-Output ("launched: " + $hit.Name + "  (" + $hit.Path + ")") }
        }
        else {
            $hits = @(Find-UiShortcut -Name $Name)
            if ($hits.Count -eq 0) { Write-Output "NOT_FOUND" }
            else { if ($Json) { $hits | ConvertTo-Json -Depth 4 } else { $hits | Format-Table -AutoSize } }
        }
    }
    'restore' {
        $w = Restore-UiWindow -Name $Name
        if ($w) {
            if ($Json) { $w | ConvertTo-Json -Compress }
            else { Write-Output ("restored: " + $w.Title + "  handle=" + $w.Handle + "  was-minimised=" + $w.WasMinimized + "  foreground=" + $w.Foreground) }
        } else { Write-Output "NOT_FOUND" }
    }
    'decide' {
        $taskText = if ($Task) { $Task } else { $Text }
        $d = Get-UiDecision -Task $taskText -Explicit:$Explicit -NoApi:$NoApi -Visual:$Visual -Cheaper:$Cheaper
        if ($Json) { $d | ConvertTo-Json -Compress } else {
            Write-Output ("use UI automation = " + $d.UseUi + "   (rule: " + $d.Rule + ")")
            Write-Output ("reason: " + $d.Reason)
            if (-not $d.UseUi) { Write-Output "suggestion: try CLI / API / file channels first; add -Explicit/-NoApi/-Visual to re-evaluate if they are impossible or insufficient." }
        }
    }
    'marks' {
        $h = Resolve-WindowArg $Window
        $m = @(Get-UiMarks -Window $h -Max $MaxWidth -IncludeText:(-not $Raw))
        if ($m.Count -gt 0) { [void](Save-UiMarks -Window $h -Marks $m) }   # persist so somclick can act on the same numbering
        $view = $m | Select-Object Index,Type,Name,AutomationId,Class,Enabled,CanInvoke,DefaultAction,X,Y,W,H,CX,CY,Source
        if ($Json) { $view | ConvertTo-Json -Depth 4 }
        else { $view | Select-Object Index,Type,Name,AutomationId,CanInvoke,DefaultAction,CX,CY | Format-Table -AutoSize }
    }
    'som' {
        <# Set-of-Marks screenshot: the marks table answers most questions; if the pixels matter, look the PNG. #>
        $h = Resolve-WindowArg $Window
        $outPath = if ($Out) { $Out } else { Join-Path (Get-UiTempDir) ("som-$h.png") }
        <# -Max on the CLI historically aliases -MaxWidth; keep the mark limit meaningful either way. #>
        $markMax = if ($MaxWidth -gt 0) { $MaxWidth } else { 1560 }
        $r = Save-UiSomShot -Window $h -Out $outPath -Max $markMax -Cursor:$Cursor
        Write-Output ("marks image: " + $r.Image + "   " + (@($r.Marks).Count) + " interactive elements (table: " + $r.MapFile + ")")
        Write-Output (Format-UiReadAdvice -Path $outPath)
        if ($Json) { @($r.Marks) | Select-Object Index,Type,Name,AutomationId,CX,CY | ConvertTo-Json -Depth 4 }
        else { @($r.Marks) | Select-Object Index,Type,Name,AutomationId,CX,CY | Format-Table -AutoSize }
    }
    'somclick' {
        $h = Resolve-WindowArg $Window
        $m = Invoke-UiMarkClick -Window $h -Index $Index -Message:$Message -PreferAction:$PreferAction
        Write-Output ("clicked mark " + $m.Index + ": " + $m.Type + " '" + $m.Name + "'  (" + $m.CX + "," + $m.CY + ")")
    }
    'msaa' {
        $h = Resolve-WindowArg $Window
        $map = @(Get-UiMsaaMap -Window $h)
        if ($Json) { $map | Select-Object Handle,Type,Name,DefaultAction,Enabled,Focused,X,Y,W,H | ConvertTo-Json -Depth 4 }
        else { $map | Select-Object Handle,Type,Name,DefaultAction,Enabled,X,Y,W,H | Format-Table -AutoSize }
    }
    'msaaaction' {
        $h = Resolve-UiTarget -Window (Resolve-WindowArg $Window) -Id $Id
        $a = Invoke-UiMsaaAction -Handle ([int64]$h)
        Write-Output ("MSAA default action executed: " + $a)
    }
    'dismiss' {
        <# Close a dialog shown by the target program: -Choice ok|yes|cancel. #>
        $h = Resolve-WindowArg $Window
        $r = Close-UiDialog -Window $h -Choice $Choice
        if ($r) {
            if ($Json) { $r | ConvertTo-Json -Compress } else { Write-Output ("dialog closed: '" + $r.Dialog + "' (" + $r.Action + ")") }
        } else { Write-Output "NO_DIALOG" }
    }
    default {
        <# Print the full command reference on demand (the header comment block) so SKILL.md stays small. #>
        $self = $PSCommandPath
        if (-not $self) { $self = Join-Path $PSScriptRoot "ui.ps1" }
        $stop = $false
        Get-Content -LiteralPath $self -Encoding UTF8 | Select-Object -Skip 1 | ForEach-Object {
            if ($stop) { return }
            if ($_ -match '^param\(') { $stop = $true; return }
            $_
        }
        return
    }
}
