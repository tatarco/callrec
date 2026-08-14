# Windows build: untested. Handoff notes.

**Status: the Windows half of this repo has never been executed on Windows.** It was written
on a Mac. Everything below is an honest account of what that means, so whoever picks it up on
an actual Windows machine — a person or another Claude session — starts from facts instead of
from my confidence.

If you are that session: your job is to run it, find where it breaks, fix it, and delete the
warnings from this file and the README once they are no longer true. Read all of this first.
The "Where it will probably break" section is ranked by how likely I think each failure is,
and it is where the value of these notes actually is.

---

## What this tool is, in one paragraph

`callrec` records both sides of a call — your microphone and whatever is coming out of your
speakers — and transcribes it locally with whisper.cpp. No bot joins the meeting, nothing is
uploaded, there is no subscription. It doesn't care what the call is on: Zoom, Meet, Teams,
WhatsApp, a phone on speaker. It ships for macOS (working, in use daily) and now for Windows
(this, unverified). The two builds deliberately expose the identical interface:

```
callrec start [label]      # begin recording
callrec stop               # stop, mix, transcribe, print the .txt path
callrec transcribe <file>  # transcribe something you already have
```

Keep that parity. If a fix requires changing a verb or an output path, that is a real cost —
say so rather than silently diverging.

## Why the Windows design differs from the mac design

This is the part worth understanding before you debug anything, because most Windows guides on
the internet describe a different approach and you will be tempted to "fix" the code back
toward them.

macOS **will not let a program read an output device.** Your speakers are an output; there is
no API that hands you the audio going to them. That is a deliberate Apple decision, and it is
why every screen recorder on macOS shipped for a decade with "system audio not supported". The
mac build works around it with a virtual audio driver (BlackHole) that presents itself as a
fake microphone, plus a Multi-Output Device so sound reaches both your speakers and BlackHole
at once — which in turn means `callrec` has to switch your default output device on `start` and
switch it back on `stop`.

**Windows never made that decision.** WASAPI has supported loopback capture — opening a render
endpoint and reading what is being played through it — since Vista. It is documented by
Microsoft: <https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording>

So on Windows there is **no driver, no virtual cable, no aggregate device, and no change to
your sound settings.** You keep hearing the call. The volume keys keep working. That is not a
shortcut, it is the platform actually being better here.

### The approach I rejected, and why you should not reintroduce it

Nearly every "record system audio with ffmpeg on Windows" answer online says to install
`virtual-audio-capturer` (from `rdp/virtual-audio-capture-grabber-device`, usually via the
`screen-capture-recorder` package) and then run
`ffmpeg -f dshow -i audio="virtual-audio-capturer"`. This is tempting because it needs no
custom code at all — it is a two-line change from the mac script.

Do not go back to it without a strong reason:

- It is an unsigned COM DLL that must be registered system-wide with `regsvr32`.
- Its last substantive work was around 2015.
- Open issue #43 (May 2024): "Could not find audio only device with name [virtual-audio-capturer]".
- Open issue #47 (Nov 2025): EasyAntiCheat flags the audio capture driver as malicious.

For a tool whose entire pitch is "you do not need to install someone else's software for this",
registering an abandoned unsigned filter system-wide is a bad trade. It also wraps the same
WASAPI loopback call we now make directly, so it buys nothing but a dependency.

Also note: **ffmpeg cannot do this on its own.** It has no WASAPI input device — trac #9408 is
still open as of May 2025. Its only Windows audio input is DirectShow, which enumerates capture
devices, not render endpoints. So *something* has to speak WASAPI. Here that something is 70
lines of our own C#.

## The files

| File | Platform | What it does |
|---|---|---|
| `audio/LoopbackCapture.cs` | Windows | The only genuinely new logic. Opens the default **output** device in loopback mode and the default **input** device normally, writes one WAV each, stops when a stop-file appears. Compiled into `loopcap.exe` at install time. |
| `bin/callrec.ps1` | Windows | The recorder. `start` spawns `loopcap.exe` and records state to `%TEMP%\callrec.state.json`; `stop` touches the stop-file, waits, mixes the two WAVs with ffmpeg, transcribes; `transcribe` resamples to 16k mono and runs whisper. |
| `app/CallRecTray.ps1` | Windows | WinForms tray icon. Left-click toggles record/stop, right-click opens the folder or quits. Cosmetic — if it misbehaves, fix the CLI first and treat this as separate. |
| `install.ps1` | Windows | ffmpeg via winget, NAudio (pinned + SHA-256 checked), compiles `loopcap.exe`, downloads whisper.cpp + the model, PATH entry, Start-menu shortcut. Idempotent. |
| `bin/callrec`, `app/CallRecBar.swift`, `audio/*.swift` | macOS | The working build. Reference for intended behaviour. Don't touch these. |

Everything installs under `%USERPROFILE%\.callrec`. Uninstall is deleting that folder (plus the
PATH entry and the Start-menu shortcut). Nothing is registered system-wide, no admin needed.

## The one subtle thing in the design

**WASAPI loopback delivers no buffers at all while the output device is idle.** Not buffers of
zeroes — nothing. If the call goes quiet for a minute, that minute is *absent from the file*
rather than present as silence, so every word after it sits a minute earlier than it should,
and the mic track and the system track drift apart progressively.

You will not notice this by listening to the first ten seconds. You notice it an hour later
when a transcript stops lining up with reality.

The documented fix, which `LoopbackCapture.cs` implements, is to play silence through the
device for the duration of the capture so it never goes idle:
<https://github.com/naudio/NAudio/blob/main/Docs/WasapiLoopbackCapture.md>

**Test for this explicitly** (see the test plan). It is the single most important behaviour to
verify, and the easiest to miss.

## What was actually verified, and how

Run on macOS, so: static checks only.

- All three PowerShell files parse clean under PowerShell 7.6
  (`[System.Management.Automation.Language.Parser]::ParseFile`).
- `Invoke-ScriptAnalyzer -Severity Error` reports zero errors. The remaining warnings are
  `PSAvoidUsingWriteHost` (intentional — this is a CLI talking to a human) and
  `PSUseShouldProcessForStateChangingFunctions` (not warranted for these functions).
- `audio/LoopbackCapture.cs` **compiles with zero warnings** against the exact pinned NAudio
  1.10.0 `net35` assembly, targeting `net48` via `Microsoft.NETFramework.ReferenceAssemblies`.
  That is the same compile Windows performs, so every API name, overload and namespace in that
  file is confirmed to exist — `WasapiLoopbackCapture`, `WasapiCapture`, `SilenceProvider`,
  `WasapiOut.Init`, `WaveFileWriter`, `IWaveIn.DataAvailable`.

## What was NOT verified — assume all of this is broken until you see it work

- Nothing has run on Windows. Not once.
- No audio has been captured, mixed, or transcribed on Windows.
- Device enumeration: whether the default render/capture devices are picked up as expected.
- Whether `csc.exe` at the hardcoded Framework64 path exists and compiles the file on a real box.
- Whether the winget / whisper.cpp / model downloads succeed and land where the scripts expect.
- The tray app: icon rendering, click handling, the message pump, the balloon tip.
- PATH changes, the Start-menu shortcut, execution policy.
- Behaviour with Bluetooth headphones, USB interfaces, or a device switch mid-call.
- Anything on ARM64 Windows. `install.ps1` pulls an x64 whisper build and uses `Framework64`.

## Test plan

Do these in order. Stop at the first failure and diagnose before moving on.

**0. Environment.** Windows 10 or 11, x64. `git`, `winget` present. No admin rights should be
needed — if something demands elevation, that is a finding worth reporting, not something to
just click through.

**1. Install.**
```powershell
git clone https://github.com/tatarco/callrec.git
cd callrec
.\install.ps1
```
Expect: ffmpeg installed or already present; NAudio hash matching; `loopcap.exe` compiled;
whisper.cpp extracted; the ~1.6GB model downloaded. Then open a **new** terminal so the PATH
change takes effect. Re-run `.\install.ps1` once and confirm it is genuinely idempotent (it
should skip every download, and recompile only `loopcap.exe`).

**2. loopcap alone.** Before involving anything else, prove the capture works:
```powershell
Start-Process "$HOME\.callrec\bin\loopcap.exe" -ArgumentList "$env:TEMP\them.wav","$env:TEMP\you.wav","$env:TEMP\stop.flag"
# play a YouTube video and talk for ~20 seconds
New-Item -ItemType File "$env:TEMP\stop.flag" -Force
```
Both WAVs should exist and be substantially larger than a bare 44-byte header. Play them back.
`them.wav` must contain the video, `you.wav` must contain your voice. If `them.wav` is silent
or missing, the loopback path is broken and nothing else matters yet.

**3. The silence test — do not skip this.** Repeat step 2, but: talk for 10 seconds, then stay
completely silent with **nothing playing** for 30 seconds, then talk again for 10 seconds.
Both files must come out **the same length, ~50 seconds.** If `them.wav` is ~20 seconds, the
keep-alive silence is not working and the tracks will drift on every real call. That is a
blocking bug, not a cosmetic one.

**4. The CLI.**
```powershell
callrec start test
# talk, play something, ~30 seconds
callrec stop
```
Expect an `.m4a` and a `.txt` in `%USERPROFILE%\Calls`. Read the transcript: **both sides must
be in it.** A transcript containing only your half means the loopback WAV never made it into
the mix.

**5. Language auto-detection.** Record a call that switches between Hebrew and English
mid-sentence. whisper is invoked with `-l auto`, which detects per segment rather than forcing
one language on the whole file. This matters more to the author than almost anything else
about the tool — verify it rather than assuming.

**6. The tray app.** Launch CallRec from the Start menu. Click the dot, type a name, talk,
click again. Confirm the icon turns red, the tooltip counts up, and the transcript lands.

**7. Long call.** One real call, 30+ minutes, with genuine pauses in it. Then check the end of
the transcript against what was actually said near the end. This is where drift, if any
remains, becomes obvious.

## Where it will probably break — ranked

1. **`csc.exe` path.** `install.ps1` hardcodes
   `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`. Present on essentially every x64
   Windows with .NET Framework 4, absent on ARM64 and on a stripped image. If missing: fall
   back to `Add-Type -OutputAssembly` under **Windows PowerShell 5.1 only** (PowerShell 7's
   Roslyn path does not support `-OutputAssembly`), or locate a compiler via the registry.
   Note it is a C# 5 era compiler — `LoopbackCapture.cs` is deliberately written to C# 5, with
   no string interpolation, no null-conditional operators, no expression-bodied members. Keep
   it that way, or the compile breaks in a confusing manner.
2. **The keep-alive silence not keeping the device alive.** See test 3. If `WasapiOut` throws
   on `Init` (a format the shared-mode engine dislikes), or silently fails to keep the endpoint
   active, loopback goes idle during quiet stretches. If `new WasapiOut()` misbehaves, try
   constructing it against the same `MMDevice` as the capture, and use that device's
   `AudioClient.MixFormat` for the `SilenceProvider`.
3. **Two WAVs with different formats, or drift between them.** The mic and the loopback are
   independent WASAPI streams on possibly different clocks. `ffmpeg amix` aligns them at t=0
   and nothing re-syncs them afterwards. Short calls will be fine. If a long call drifts, the
   honest fix is to timestamp both streams and pad, not to fiddle with `amix`.
4. **ffmpeg not on PATH in the same session** that `winget` installed it. `install.ps1` says so,
   but if `callrec stop` dies at the mix step, that is the first thing to check.
5. **Execution policy.** The `.cmd` shim and the shortcut both pass `-ExecutionPolicy Bypass`,
   but a machine-wide policy set by group policy can still block. Report it rather than
   weakening anything.
6. **No microphone, or no output device.** `LoopbackCapture.cs` catches each independently and
   continues with whatever it has; `callrec.ps1` warns when only one side was captured. Worth
   testing by disabling a device, because a desktop with no mic is a real configuration.
7. **Device switching mid-call.** Both captures bind to whatever was default when they started.
   Plugging in headphones mid-call is untested and probably ends the loopback stream. At
   minimum this should fail loudly rather than produce a half-empty file.
8. **The tray app's message pump.** WinForms inside PowerShell is fussy; the click handler runs
   `callrec stop` synchronously and will freeze the icon during transcription. Acceptable, but
   if it is worse than that in practice, move the work to a background job.

## Ground rules for whoever finishes this

- **Do not break verb parity with the mac build.** Same commands, same output locations.
- **Do not add a system-wide install.** No drivers, no services, no `regsvr32`, no admin. That
  constraint is the product, not an implementation detail.
- **Do not add a dependency to solve something small.** NAudio is here because writing raw
  WASAPI COM interop by hand would be several hundred lines of untestable P/Invoke. That is the
  bar for adding anything else.
- **When you fix something, say what you actually ran.** "Tested on Windows 11 24H2, x64, Intel,
  Realtek onboard audio" is worth more than "works now". The next person inherits your evidence,
  not your confidence.
- **Delete the untested warnings** from `README.md` and the top of this file once the test plan
  passes, and note the machine it passed on. Leaving stale warnings up is its own kind of lie.

## Pinned versions

- NAudio `1.10.0`, `lib/net35/NAudio.dll`, SHA-256
  `BC4BACC3B8B28D898F1671B79F216CCA439F95EB60CD32D3E3ECAFBECAC42780`. Chosen over the current
  2.3.0 because 1.10.0 ships one self-contained `net35` assembly, which the in-box Windows C#
  compiler consumes without a .NET SDK or netstandard facades. Version 1.10.0 is also the
  release that introduced `SilenceProvider`, which the keep-alive depends on.
- whisper.cpp `v1.9.2`, `whisper-blas-bin-x64.zip` (CPU, 21MB) by default;
  `whisper-cublas-12.4.0-bin-x64.zip` (670MB) with `.\install.ps1 -Cuda` on NVIDIA hardware.
  The binary inside is `Release\whisper-cli.exe`, the same CLI name and flags as the mac build.
- Model: `ggml-large-v3-turbo.bin` from Hugging Face, ~1.6GB, same as macOS.

CPU transcription is the default because there is no Metal equivalent to lean on. A long call
will take a while. `-Cuda` is the answer for anyone with an NVIDIA card.
