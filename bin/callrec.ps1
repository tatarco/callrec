# callrec - record any call on this PC (mic + system audio) and transcribe it locally.
# Works for Zoom, Meet, Teams, WhatsApp, phone-on-speaker - anything that makes sound.
# ponytail: no daemon, no service. One capture process, a state file, whisper.cpp.
[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet('start', 'stop', 'transcribe')][string]$Command,
    [Parameter(Position = 1)][string]$Arg
)

$ErrorActionPreference = 'Stop'
$Root    = if ($env:CALLREC_HOME)  { $env:CALLREC_HOME }  else { Join-Path $HOME '.callrec' }
$Dir     = if ($env:CALLREC_DIR)   { $env:CALLREC_DIR }   else { Join-Path $HOME 'Calls' }
$Model   = if ($env:CALLREC_MODEL) { $env:CALLREC_MODEL } else { Join-Path $Root 'models\ggml-large-v3-turbo.bin' }
$Whisper = if ($env:CALLREC_WHISPER) { $env:CALLREC_WHISPER } else { Join-Path $Root 'whisper\whisper-cli.exe' }
$LoopCap = Join-Path $Root 'bin\loopcap.exe'
$State   = Join-Path $env:TEMP 'callrec.state.json'
$StopF   = Join-Path $env:TEMP 'callrec.stop'

function Die($msg) { Write-Error $msg; exit 1 }

function Invoke-Ffmpeg([string[]]$FfArgs) {
    & ffmpeg -nostdin -loglevel error @FfArgs
    if ($LASTEXITCODE -ne 0) { Die "ffmpeg failed" }
}

function Start-Recording($label) {
    if (Test-Path $State) {
        $s = Get-Content $State -Raw | ConvertFrom-Json
        Die "already recording: $($s.out)"
    }
    foreach ($p in @($LoopCap, $Whisper, $Model)) {
        if (-not (Test-Path $p)) { Die "missing $p - run install.ps1" }
    }
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Remove-Item $StopF -ErrorAction SilentlyContinue

    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
    $name  = if ($label) { "$stamp-$($label -replace '[^\w\-]', '-')" } else { $stamp }
    $out   = Join-Path $Dir "$name.m4a"
    $sys   = Join-Path $env:TEMP "callrec-them-$stamp.wav"
    $mic   = Join-Path $env:TEMP "callrec-you-$stamp.wav"

    $p = Start-Process -FilePath $LoopCap -ArgumentList @($sys, $mic, $StopF) `
        -WindowStyle Hidden -PassThru
    [pscustomobject]@{ pid = $p.Id; out = $out; sys = $sys; mic = $mic } |
        ConvertTo-Json | Set-Content $State
    Write-Host "recording -> $out"
}

function Stop-Recording {
    if (-not (Test-Path $State)) { Die "not recording" }
    $s = Get-Content $State -Raw | ConvertFrom-Json
    New-Item -ItemType File -Path $StopF -Force | Out-Null
    try { Wait-Process -Id $s.pid -Timeout 20 } catch { Stop-Process -Id $s.pid -Force -ErrorAction SilentlyContinue }
    Remove-Item $State, $StopF -ErrorAction SilentlyContinue

    # @(...) around the pipeline, not just inside it: a single survivor would otherwise be a
    # bare string, and $have[0] on a string is its first character.
    $have = @(@($s.mic, $s.sys) | Where-Object { (Test-Path $_) -and (Get-Item $_).Length -gt 4096 })
    if ($have.Count -eq 0) { Die "recording produced no audio" }
    if ($have.Count -eq 1) {
        Write-Warning "only one side captured - check Windows sound settings for the missing device"
        Invoke-Ffmpeg @('-y', '-i', $have[0], '-c:a', 'aac', '-b:a', '64k', $s.out)
    }
    else {
        # both sides, mixed to one track - same filter as the mac build
        Invoke-Ffmpeg @('-y', '-i', $s.mic, '-i', $s.sys,
            '-filter_complex', '[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0[a]',
            '-map', '[a]', '-c:a', 'aac', '-b:a', '64k', $s.out)
    }
    Remove-Item $s.mic, $s.sys -ErrorAction SilentlyContinue
    Write-Host "saved -> $($s.out)"
    Transcribe $s.out
}

function Transcribe($audio) {
    if (-not (Test-Path $audio)) { Die "no such file: $audio" }
    $base = [IO.Path]::Combine([IO.Path]::GetDirectoryName($audio),
                               [IO.Path]::GetFileNameWithoutExtension($audio))
    $wav  = "$base.16k.wav"
    Invoke-Ffmpeg @('-y', '-i', $audio, '-ar', '16000', '-ac', '1', $wav)
    # ponytail: auto language. A call that switches between Hebrew and English is detected
    # per segment instead of one language being forced on the whole file.
    & $Whisper -m $Model -f $wav -l auto -otxt -of $base | Out-Null
    Remove-Item $wav -ErrorAction SilentlyContinue
    Write-Host "transcript -> $base.txt"
}

switch ($Command) {
    'start'      { Start-Recording $Arg }
    'stop'       { Stop-Recording }
    'transcribe' { if (-not $Arg) { Die "usage: callrec transcribe <file>" }; Transcribe $Arg }
    default      { Write-Host "usage: callrec start [label] | stop | transcribe <file>"; exit 1 }
}
