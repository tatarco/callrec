# callrec

Record any call on your Mac — both sides — and transcribe it locally. No bot joins the
meeting, no subscription, no upload.

It doesn't care what you're calling on. Zoom, Meet, Teams, WhatsApp, Slack, a phone on
speaker, a YouTube video you want notes from. If it makes sound on this machine, it gets
recorded.

```
click the menu bar dot → name the call → talk → click again → transcript in ~/Calls
```

## Why this exists

Every meeting-notes product solves this the same way: a bot joins your call, your audio
goes to their servers, and you pay monthly for the privilege. That breaks the moment you're
on WhatsApp instead of Zoom, and it's a hard sell for a conversation with a client about
their confidential numbers.

The primitives to do it locally have been sitting on your Mac the whole time. This is about
120 lines of glue over them.

## How it works

Three pieces, each replaceable:

| Piece | Job |
|---|---|
| **BlackHole 2ch** | A virtual audio driver. macOS can only record *inputs*, and your speakers aren't one — so BlackHole loops system output back in as a fake microphone. That's the only reason recording the other side is possible at all. |
| **ffmpeg** | Records two inputs (your mic + BlackHole) and mixes them to one AAC track. |
| **whisper.cpp** | Transcribes on-device, Metal-accelerated. Auto-detects language — a call that switches between English and Hebrew transcribes per segment. |

The one piece of friction is that system audio only reaches BlackHole if your output device
is a **Multi-Output Device** (speakers + BlackHole together). Selecting it by hand before
every call — and remembering to switch back, because the volume keys stop working while it's
selected — is exactly the kind of thing you stop doing after a week. So `callrec` switches
to it on `start` and switches back on `stop`.

## Install

```bash
git clone https://github.com/tatarco/callrec.git && cd callrec && ./install.sh
```

Installs ffmpeg, whisper-cpp and BlackHole via Homebrew, downloads the whisper model
(~1.6GB, once), creates the `Call Capture` Multi-Output Device via CoreAudio, and builds the
menu bar app into `~/Applications`. Re-running is safe.

## Use

**Menu bar** — `open ~/Applications/CallRec.app`. Click the dot, type who the call is with,
talk. The icon turns into a red stop button with a running timer. Click it again: it stops,
transcribes, and offers to reveal the transcript. Right-click for the folder and quit.

**Terminal** — same thing, scriptable:

```bash
callrec start acme-corp     # → ~/Calls/2026-08-13_2309-acme-corp.m4a
callrec stop                # → stops, transcribes, prints the .txt path
callrec transcribe file.m4a # → transcribe something you already have
```

Both write to `~/Calls/`. Nothing else touches the file.

## Feeding it to an AI

The reason I built this: my own summary of a client call is filtered through what I *hoped*
they meant. A transcript isn't.

`skill/dealroom-record.md` is the [Claude Code](https://claude.com/claude-code) skill I use —
it records the call, files the transcript into a private deal folder, and appends only the
extracted facts (budget signals, who signs, deadlines, their exact words for the problem) to
the deal record. The raw transcript stays in a file; the record stays readable.

It's ~40 lines of markdown and hardcodes my folder layout. Read it as a worked example, not
a dependency.

## Notes and limits

- **Consent.** Recording laws vary and some are one-party, some all-party. Tell people
  you're recording. This tool makes it easy to be a good actor; it doesn't make it legal to
  be a bad one.
- Volume keys don't work while recording (a Multi-Output Device limitation). Set the level
  before you start.
- Both sides land on one mixed mono track — good for transcription, not for editing. If you
  want speakers separated, record two files instead of using `amix` and diarize after.
- Bluetooth headphones: pick your headphones as the speaker half when you create the device
  (`make-multi-output "<name>"`), or you'll capture silence.
- Apple Silicon assumed (Metal). It'll run on Intel, slower.

## Layout

```
bin/callrec                     the whole recorder, one bash script
app/CallRecBar.swift            menu bar app — one file, built with swiftc, no Xcode
audio/make-multi-output.swift   creates the Multi-Output Device via CoreAudio
audio/setout.swift              switch the default output device from the CLI
skill/dealroom-record.md        example: transcript → structured notes via Claude Code
```

MIT.
