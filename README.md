# callrec

Record any call on your Mac - both sides - and transcribe it locally. No bot joins the
meeting, no subscription, no upload.

It doesn't care what you're calling on. Zoom, Meet, Teams, WhatsApp, Slack, a phone on
speaker, a YouTube video you want notes from. If it makes sound on this machine, it gets
recorded.

```
click the menu bar dot → name the call → talk → click again → transcript in ~/Calls
```

## Why this exists

Every meeting-notes product solves this the same way: a bot joins your call, your audio goes
to their servers, and you pay monthly for the privilege. That breaks the moment you're on
WhatsApp instead of Zoom, and it's an awkward thing to announce at the start of a
conversation that was supposed to be private.

Your memory of a conversation is a reconstruction. A transcript is not. That matters for
an interview, a lecture, a call with a supplier, an appointment you want to remember
correctly, or anything where someone's exact words are worth more than your summary of them.

The primitives to do this locally have been sitting on your Mac the whole time. This is 350
lines of glue over them.

## How it works

Three pieces, each replaceable:

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

## Install

```bash
git clone https://github.com/tatarco/callrec.git && cd callrec && ./install.sh
```

Installs ffmpeg, whisper-cpp and BlackHole via Homebrew, downloads the whisper model
(~1.6GB, once), creates the `Call Capture` Multi-Output Device via CoreAudio, and builds the
menu bar app into `~/Applications`. Re-running is safe.

## Use

**Menu bar** - `open ~/Applications/CallRec.app`. Click the dot, type who the call is with,
talk. The icon turns into a red stop button with a running timer. Click it again: it stops,
transcribes, and offers to reveal the transcript. Right-click for the folder and quit.

**Terminal** - same thing, scriptable:

```bash
callrec start standup       # → ~/Calls/2026-08-13_2309-standup.m4a
callrec stop                # → stops, transcribes, prints the .txt path
callrec transcribe file.m4a # → transcribe something you already have
```

Both write to `~/Calls/`. Nothing else touches the file.

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
- Volume keys don't work while recording (a Multi-Output Device limitation). Set the level
  before you start.
- Both sides land on one mixed mono track - good for transcription, not for editing. If you
  want speakers separated, record two files instead of using `amix` and diarize after.
- Bluetooth headphones: pick your headphones as the speaker half when you create the device
  (`make-multi-output "<name>"`), or you'll capture silence.
- Apple Silicon assumed (Metal). It'll run on Intel, slower.

## Layout

```
bin/callrec                     the whole recorder, one bash script
app/CallRecBar.swift            menu bar app - one file, built with swiftc, no Xcode
audio/make-multi-output.swift   creates the Multi-Output Device via CoreAudio
audio/setout.swift              switch the default output device from the CLI
```

Longer write-up, including the CoreAudio details: https://gal.tidhar.org.il/blog/callrec/

MIT.
