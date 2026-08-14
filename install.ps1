# callrec installer for Windows. Idempotent - safe to re-run.
#   git clone https://github.com/tatarco/callrec.git; cd callrec; .\install.ps1
[CmdletBinding()]
param(
    # NVIDIA card? -Cuda pulls the cuBLAS build of whisper.cpp instead of the CPU one.
    # 670MB instead of 21MB, and several times faster on a long call.
    [switch]$Cuda
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # or Invoke-WebRequest crawls
$Root = if ($env:CALLREC_HOME) { $env:CALLREC_HOME } else { Join-Path $HOME '.callrec' }
$Src  = $PSScriptRoot
if (-not $Src) { throw 'Run this from a clone of the repo (it compiles a source file next to it).' }

# Pinned, and checked. This is the one binary dependency that is not a signed installer,
# so it does not get to arrive unverified.
$NAudioVersion = '1.10.0'
$NAudioSha256  = 'BC4BACC3B8B28D898F1671B79F216CCA439F95EB60CD32D3E3ECAFBECAC42780'
$WhisperTag    = 'v1.9.2'

foreach ($d in 'bin', 'lib', 'whisper', 'models') {
    New-Item -ItemType Directory -Force -Path (Join-Path $Root $d) | Out-Null
}

function Get-File($Url, $Dest) {
    if (Test-Path $Dest) { return }
    Write-Host "    downloading $(Split-Path $Dest -Leaf)"
    # Download to .part and rename, so an interrupted 1.6GB model is retried next run
    # instead of sitting there looking finished.
    Invoke-WebRequest -Uri $Url -OutFile "$Dest.part" -UseBasicParsing
    Move-Item "$Dest.part" $Dest -Force
}

Write-Host '==> ffmpeg'
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    Write-Host '    already installed'
}
elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements
    Write-Host '    installed - a new terminal will be needed for it to be on PATH'
}
else {
    throw 'ffmpeg not found and winget is unavailable. Install ffmpeg and re-run.'
}

Write-Host '==> NAudio (WASAPI loopback, MIT)'
$nupkg = Join-Path $env:TEMP "naudio-$NAudioVersion.zip"
$dll   = Join-Path $Root 'lib\NAudio.dll'
if (-not (Test-Path $dll)) {
    Get-File "https://www.nuget.org/api/v2/package/NAudio/$NAudioVersion" $nupkg
    $stage = Join-Path $env:TEMP "naudio-$NAudioVersion"
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive $nupkg -DestinationPath $stage
    # net35 build: one self-contained assembly, no netstandard facades, so the C# compiler
    # that already ships with Windows can consume it without a .NET SDK anywhere in sight.
    $got = (Get-FileHash (Join-Path $stage 'lib\net35\NAudio.dll') -Algorithm SHA256).Hash
    if ($got -ne $NAudioSha256) { throw "NAudio.dll hash mismatch: $got" }
    Copy-Item (Join-Path $stage 'lib\net35\NAudio.dll') $dll
    Remove-Item $stage -Recurse -Force
}
Write-Host '    ok'

Write-Host '==> capture helper'
# ponytail: no build tools, no SDK, no Visual Studio. Every Windows since 8 ships the
# .NET Framework C# compiler; the helper is one file, so that is enough.
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "C# compiler not found at $csc" }
$exe = Join-Path $Root 'bin\loopcap.exe'
& $csc /nologo /target:exe /out:$exe /reference:$dll (Join-Path $Src 'audio\LoopbackCapture.cs')
if ($LASTEXITCODE -ne 0) { throw 'failed to compile loopcap.exe' }
Copy-Item $dll (Join-Path $Root 'bin\NAudio.dll') -Force
Write-Host "    $exe"

Write-Host '==> whisper.cpp'
if (-not (Test-Path (Join-Path $Root 'whisper\whisper-cli.exe'))) {
    $asset = if ($Cuda) { 'whisper-cublas-12.4.0-bin-x64.zip' } else { 'whisper-blas-bin-x64.zip' }
    $zip   = Join-Path $env:TEMP $asset
    Get-File "https://github.com/ggml-org/whisper.cpp/releases/download/$WhisperTag/$asset" $zip
    $stage = Join-Path $env:TEMP 'whisper-stage'
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive $zip -DestinationPath $stage
    Copy-Item (Join-Path $stage 'Release\*') (Join-Path $Root 'whisper') -Force
    Remove-Item $stage -Recurse -Force
}
Write-Host '    ok'

Write-Host '==> whisper model (~1.6GB, once)'
Get-File 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin' `
    (Join-Path $Root 'models\ggml-large-v3-turbo.bin')
Write-Host '    ok'

Write-Host '==> cli'
Copy-Item (Join-Path $Src 'bin\callrec.ps1') (Join-Path $Root 'bin\callrec.ps1') -Force
Copy-Item (Join-Path $Src 'app\CallRecTray.ps1') (Join-Path $Root 'bin\CallRecTray.ps1') -Force
@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0callrec.ps1" %*
"@ | Set-Content (Join-Path $Root 'bin\callrec.cmd') -Encoding ASCII

$binDir = Join-Path $Root 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$binDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$binDir", 'User')
    Write-Host "    added $binDir to your PATH (new terminals only)"
}

Write-Host '==> tray app'
$lnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'CallRec.lnk'
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$s.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$s.Arguments  = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$binDir\CallRecTray.ps1`""
$s.WorkingDirectory = $binDir
$s.Save()

@"

Done.

  CallRec (Start menu)                # tray dot: click, name the call, record
  callrec start <name> / callrec stop # same thing from the terminal

First recording will ask for microphone permission. Say yes.
Nothing is installed system-wide: no audio driver, no service, no changed sound settings.
"@ | Write-Host
