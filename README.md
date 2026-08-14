# callrec

Record any call on your Mac or PC - both sides - and transcribe it locally. No bot joins
the meeting, no subscription, no upload.

It doesn't care what you're calling on. Zoom, Meet, Teams, WhatsApp, Slack, a phone on
speaker, a YouTube video you want notes from. If it makes sound on this machine, it gets
recorded.

```
click the dot → name the call → talk → click again → transcript in your Calls folder
```

## Why this exists

Every meeting-notes product solves this the same way: a bot joins your call, your audio goes
to their servers, and you pay monthly for the privilege. That breaks the moment you're on
WhatsApp instead of Zoom, and it's an awkward thing to announce at the start of a
conversation that was supposed to be private.

Your memory of a conversation is a reconstruction. A transcript is not. That matters for
an interview, a lecture, a call with a supplier, an appointment you want to remember
correctly, or anything where someone's exact words are worth more than your summary of them.

The primitives to do this locally have been sitting on your machine the whole time. This is
glue over them - about 350 lines on macOS, about 250 on Windows.

## How it works

The hard part is capturing *the other side*. Your microphone records you; the person you're
talking to comes out of your speakers, and speakers are an output. The two operating systems
disagree completely about whether you're allowed to read one.

### macOS

| Piece | Job |
|---|---|
| **BlackHole 2ch** | A virtual audio driver. macOS can only record *inputs*, and your speakers aren't one - so BlackHole loops system output back in as a fake microphone. That's the only reason recording the other side is possible at all. |
| **ffmpeg** | Records two inputs (your mic + BlackHole) and mixes them to one AAC track. |
| **whisper.cpp** | Transcribes on-device, Metal-accelerated. Auto-detects language - a call that switches between English and Hebrew transcribes per segment. |

The one piece of friction is that system audio only reaches BlackHole if your output device
is a **Multi-Output Device** (speakers + BlackHole together). Selecting it by hand before
every call - and remembering to switch back, because the volume keys stop working while it's
selected - is exactly the kind of thing you stop doing after a week. So `callrec` switches
to it on `start` and switches back on `stop`.

### Windows

> **Untested.** The Windows build was written on a Mac and has never been run on Windows. The
> PowerShell parses clean and the C# compiles against the pinned NAudio assembly, but no audio
> has ever been captured with it. If you're trying it, read
> [TESTING-WINDOWS.md](TESTING-WINDOWS.md) first - it has the test plan, the ranked list of
> where it is most likely to break, and enough context to finish the job. Findings welcome.

Windows never made that decision. [WASAPI loopback](https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording)
has let any program read the audio going to a render device since Vista, so there is no
driver to install, no fake sound card, no Multi-Output Device, and nothing about your sound
settings changes while you record. You keep hearing the call and the volume keys keep working.

| Piece | Job |
|---|---|
| **`loopcap.exe`** | 70 lines of C# over [NAudio](https://github.com/naudio/NAudio) (MIT). Opens the default output device in loopback mode and the default input device normally, and writes one WAV each. Compiled at install time by the C# compiler that already ships in Windows - no SDK, no build tools. |
| **ffmpeg** | Mixes the two WAVs to one AAC track after the call, and resamples for whisper. |
| **whisper.cpp** | Same as macOS. CPU/BLAS by default; `-Cuda` at install pulls the cuBLAS build. |

One trap worth knowing about, because it is invisible until you check a transcript against
the clock: WASAPI loopback delivers *nothing at all* while the output device is idle. A quiet
minute doesn't arrive as a minute of silence, it doesn't arrive - so everything after it
lands a minute early against the mic track and the two sides drift apart. The
[documented fix](https://github.com/naudio/NAudio/blob/main/Docs/WasapiLoopbackCapture.md) is
to play silence through the device for the duration of the recording, which is what
`loopcap.exe` does.

What the two platforms do *not* share is the reason people usually cite for this being hard.
The widely copy-pasted Windows answer is a DirectShow filter called `virtual-audio-capturer`.
It works by the same WASAPI loopback underneath, but it's an unsigned COM DLL last worked on
around 2015, with open reports of the device not being found at all and of EasyAntiCheat
flagging it as malicious. For a tool whose entire point is not needing someone else's
software, registering that system-wide would be a strange trade. Calling the API directly is
less code anyway.

## Install

**macOS**

```bash
git clone https://github.com/tatarco/callrec.git && cd callrec && ./install.sh
```

Installs ffmpeg, whisper-cpp and BlackHole via Homebrew, downloads the whisper model
(~1.6GB, once), creates the `Call Capture` Multi-Output Device via CoreAudio, and builds the
menu bar app into `~/Applications`. Re-running is safe.

**Windows** (PowerShell, no admin rights needed) - [untested, see TESTING-WINDOWS.md](TESTING-WINDOWS.md)

```powershell
git clone https://github.com/tatarco/callrec.git; cd callrec; .\install.ps1
```

Installs ffmpeg via winget, downloads NAudio (pinned and hash-checked) and whisper.cpp,
compiles `loopcap.exe`, downloads the model, and puts `callrec` on your PATH with a CallRec
shortcut in the Start menu. Everything lands in `%USERPROFILE%\.callrec` - uninstalling is
deleting that folder. Add `-Cuda` if you have an NVIDIA card.

## Use

**Menu bar / tray** - `open ~/Applications/CallRec.app` on macOS, or CallRec in the Start
menu on Windows. Click the dot, type who the call is with, talk. The dot turns red with a
running timer. Click it again: it stops, transcribes, and points you at the transcript.
Right-click for the folder and quit.

**Terminal** - same thing, scriptable. Identical verbs on both platforms:

```bash
callrec start standup       # → ~/Calls/2026-08-13_2309-standup.m4a
callrec stop                # → stops, transcribes, prints the .txt path
callrec transcribe file.m4a # → transcribe something you already have
```

Both write to `~/Calls/` (`%USERPROFILE%\Calls` on Windows). Nothing else touches the file.

## Feeding it to something else

The output is a plain `.txt` next to the audio in `~/Calls/`, so there is nothing to
integrate with. Pipe it wherever you want:

```bash
callrec stop                                  # prints the transcript path
claude "summarise the action items" < ~/Calls/2026-08-13_2309-standup.txt
grep -ril "renewal date" ~/Calls/             # search everything you ever recorded
```

Agents like [Claude Code](https://claude.com/claude-code) are the obvious destination -
pull out decisions and action items, answer "what did they actually say about X", or diff
what was agreed against what shipped. Worth doing on the transcript rather than on your own
notes, since the transcript is the only version that isn't already an interpretation.

## Notes and limits

- **Consent.** Recording laws vary and some are one-party, some all-party. Tell people
  you're recording. This tool makes it easy to be a good actor; it doesn't make it legal to
  be a bad one.
- Both sides land on one mixed mono track - good for transcription, not for editing. If you
  want speakers separated, keep the two files instead of using `amix` and diarize after. On
  Windows they are already two separate WAVs until `stop` merges them.
- **macOS:** volume keys don't work while recording (a Multi-Output Device limitation). Set
  the level before you start. Bluetooth headphones: pick your headphones as the speaker half
  when you create the device (`make-multi-output "<name>"`), or you'll capture silence.
  Apple Silicon assumed (Metal). It'll run on Intel, slower.
- **Windows:** it records whatever is currently the *default* output and input device, so
  swapping to headphones mid-call moves the recording with it. x64 only. Transcription runs
  on the CPU unless you installed with `-Cuda`, so a long call takes a while.

## Layout

```
bin/callrec                     macOS   the whole recorder, one bash script
app/CallRecBar.swift            macOS   menu bar app - one file, swiftc, no Xcode
audio/make-multi-output.swift   macOS   creates the Multi-Output Device via CoreAudio
audio/setout.swift              macOS   switch the default output device from the CLI

bin/callrec.ps1                 Windows the whole recorder, one PowerShell script
app/CallRecTray.ps1             Windows tray app - WinForms, no compiler needed
audio/LoopbackCapture.cs        Windows WASAPI loopback + mic capture, compiled at install

TESTING-WINDOWS.md              what is verified, what isn't, and how to finish it
```

Longer write-up, including the CoreAudio details: https://gal.tidhar.org.il/blog/callrec/

MIT.
