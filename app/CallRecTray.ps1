# CallRecTray - tray front end for callrec, the Windows twin of the mac menu bar app.
# Click the dot: it asks who the call is with, then records. Click again: stop + transcribe.
# ponytail: no installer, no XAML, no C#. WinForms has had a tray icon since 2002.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic

$Root    = if ($env:CALLREC_HOME) { $env:CALLREC_HOME } else { Join-Path $HOME '.callrec' }
$Dir     = if ($env:CALLREC_DIR)  { $env:CALLREC_DIR }  else { Join-Path $HOME 'Calls' }
$Callrec = Join-Path $Root 'bin\callrec.ps1'
$LastFile = Join-Path $Root 'last-label.txt'

function New-Dot([System.Drawing.Color]$Color) {
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.FillEllipse((New-Object System.Drawing.SolidBrush $Color), 3, 3, 10, 10)
    $g.Dispose()
    [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$IdleIcon = New-Dot ([System.Drawing.Color]::FromArgb(140, 140, 140))
$RecIcon  = New-Dot ([System.Drawing.Color]::FromArgb(220, 50, 47))
$BusyIcon = New-Dot ([System.Drawing.Color]::FromArgb(230, 180, 40))

function Invoke-Callrec([string[]]$CallArgs) {
    Start-Process powershell -ArgumentList (
        @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Callrec) + $CallArgs
    ) -WindowStyle Hidden -Wait
}

$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = $IdleIcon
$icon.Text = 'CallRec - click to record'
$icon.Visible = $true

$state = [pscustomobject]@{ recording = $false; started = $null }

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    if ($state.recording) {
        $t = [datetime]::Now - $state.started
        $icon.Text = 'Recording {0:mm\:ss}' -f $t
    }
})

$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Open recordings folder', $null, {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Start-Process explorer.exe $Dir
})
[void]$menu.Items.Add('Quit', $null, {
    if ($state.recording) { Invoke-Callrec @('stop') }
    $icon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})
$icon.ContextMenuStrip = $menu

$icon.Add_MouseClick({
    if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }

    if (-not $state.recording) {
        $last = if (Test-Path $LastFile) { Get-Content $LastFile -Raw } else { '' }
        $label = [Microsoft.VisualBasic.Interaction]::InputBox(
            'Who is this call with?', 'CallRec', $last.Trim())
        if ($null -eq $label) { return }
        $label = $label.Trim()
        if ($label) { Set-Content $LastFile $label }

        Invoke-Callrec @('start', $label)
        $state.recording = $true
        $state.started = [datetime]::Now
        $icon.Icon = $RecIcon
        $timer.Start()
        return
    }

    $timer.Stop()
    $state.recording = $false
    $icon.Icon = $BusyIcon
    $icon.Text = 'Transcribing...'
    Invoke-Callrec @('stop')
    $icon.Icon = $IdleIcon
    $icon.Text = 'CallRec - click to record'
    $icon.BalloonTipTitle = 'Transcript ready'
    $icon.BalloonTipText = $Dir
    $icon.ShowBalloonTip(4000)
})

[System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))
