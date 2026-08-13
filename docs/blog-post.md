# Your Mac can already record your calls. It just doesn't tell you.

I record client calls now. Not because I like the sound of my own voice, but because my
memory of a call is not a recording of it — it's a summary written by the guy who wanted
the deal to go well.

Last week I caught myself doing it. A prospect said something about his customers' setups
being fragmented, and by the time I wrote it down it had become "he needs a
platform-agnostic layer" — which is a thing *I* wanted to build, dressed up as a thing
*he* said. The transcript would have shown me the difference. There was no transcript.

So I went looking for a tool. What I found was a category: a bot that joins your meeting,
uploads the audio to someone's cloud, sends you a summary, and charges monthly forever.

That fails in three ways at once for me. It doesn't work on WhatsApp, which is where half
my calls happen. It's another subscription in a stack that already has too many. And I'd
have to open a call about a client's confidential rates by telling him a third party is
listening.

Then I remembered that all of this runs on my laptop already.

## The one thing macOS won't do

Here's the wall everyone hits, and it's worth understanding because it explains the whole
shape of the solution.

macOS lets you record **inputs**. Microphones, line-ins, anything the system classifies as
a capture device. Your speakers are an **output**, and there is no API that hands you the
audio going *to* them. This isn't an oversight — it's a deliberate boundary, and it's why
every screen recorder for a decade shipped with "system audio not supported."

So you record what you can (your own microphone) and you get a transcript of a monologue.
Useless. The half of the conversation worth keeping is the other person's.

The way around it is a **virtual audio driver**: a fake sound card that accepts output and
re-presents it as an input. [BlackHole](https://github.com/ExistentialAudio/BlackHole) is
the good free one — a 2-channel HAL driver, open source, one Homebrew cask.

```bash
brew install --cask blackhole-2ch
sudo killall coreaudiod   # it won't appear until CoreAudio restarts
```

Now your Mac has a device that is simultaneously a place to send sound and a place to
record it from. The rest is plumbing.

## Recording is one ffmpeg command

Two inputs, one mixed track:

```bash
ffmpeg -f avfoundation -i ":$MIC" -f avfoundation -i ":$BLACKHOLE" \
  -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0[a]" \
  -map "[a]" -c:a aac -b:a 64k call.m4a
```

`amix` folds you and them into one mono track. That's the right trade for transcription and
the wrong one for editing — if you want the speakers separated, record two files and
diarize afterwards. I wanted words, so: one track, 64kbps, an hour of call is about 28MB.

## Transcription is one more

[whisper.cpp](https://github.com/ggerganov/whisper.cpp) is a C++ port of OpenAI's Whisper
that runs on Apple Silicon's GPU through Metal:

```bash
brew install whisper-cpp
whisper-cli -m ggml-large-v3-turbo.bin -f call.wav -l auto -otxt
```

`-l auto` is the part that made this viable for me. My calls slide between Hebrew and
English mid-sentence, and the large-v3-turbo model detects per segment rather than forcing
one language on the whole file. A six-second clip transcribes in about two seconds on an
M4. The model is a 1.6GB download, once. After that you're offline forever.

## The part that would have killed it

Here's where a weekend project usually dies.

Sending audio to BlackHole means *making it your output device* — which means you can't
hear anything, because the sound now goes into a virtual sink instead of your speakers. The
fix is a **Multi-Output Device**: a fake device that fans one stream to several real ones.
You build it by hand in Audio MIDI Setup, tick your speakers and BlackHole, and select it
before each call.

And then you don't. Because you have to remember to select it, remember to switch back
after, and while it's selected **your volume keys stop working** — Multi-Output Devices
have no master volume. Three weeks of that and the tool is dead.

So the script owns the switch. `callrec start` sets the output device to the multi-output
and `callrec stop` puts back whatever you had. Both are a dozen lines of CoreAudio.

The device itself is worth a footnote, because it isn't in the docs anywhere obvious: a
Multi-Output Device is just an **aggregate device with `kAudioAggregateDeviceIsStackedKey`
set to 1**. Which means you can create the thing programmatically instead of asking a user
to click it together:

```swift
let desc: [String: Any] = [
    kAudioAggregateDeviceNameKey as String: "Call Capture",
    kAudioAggregateDeviceIsStackedKey as String: 1,          // stacked == Multi-Output
    kAudioAggregateDeviceIsPrivateKey as String: 0,          // persists across reboots
    kAudioAggregateDeviceMasterSubDeviceKey as String: speakersUID,
    kAudioAggregateDeviceSubDeviceListKey as String: [
        [kAudioSubDeviceUIDKey as String: speakersUID, kAudioSubDeviceDriftCompensationKey as String: 0],
        [kAudioSubDeviceUIDKey as String: blackHoleUID, kAudioSubDeviceDriftCompensationKey as String: 1],
    ],
]
AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newID)
```

Real hardware is the clock master; drift correction goes on the virtual device, which has
no crystal of its own and will slowly slide out of sync without it.

## A dot in the menu bar

The CLI was enough for me and not enough for anyone else, so there's a menu bar app: click
the dot, type who the call is with, talk, click again. It's one Swift file, 160 lines,
built with `swiftc` — no Xcode project, no storyboard, no dependencies. An `.app` bundle is
a folder with a binary and an `Info.plist`; `codesign -s -` with a fixed identifier is
enough to keep the microphone permission across rebuilds.

## What it's actually for

The recording was never the point. The point is what you can hand to a model afterwards.

I run a `/dealroom-record` skill in Claude Code that takes the transcript, files it into a
private per-client folder, and appends only the extracted facts to my deal record — budget
signals, who signs, deadlines, and the client's own words for their problem, quoted
verbatim. Not the transcript itself; a 40,000-character wall of text makes a deal record
unreadable. The pointer and the facts.

Then when I ask for advice on the deal, the advice is fed the client's actual sentences
instead of my recollection of them. That difference is the entire return on a weekend.

## It's 350 lines

A 72-line bash script, a 160-line Swift file for the menu bar, and two CoreAudio utilities
under 120 lines together. Nothing
leaves the machine, nothing runs monthly, and it doesn't care what you're calling on —
Zoom, Meet, Teams, WhatsApp, a phone on speaker, a YouTube video you want notes from. If it
makes sound on this Mac, it gets recorded.

**[github.com/tatarco/callrec](https://github.com/tatarco/callrec)** — MIT.

One thing before you run it: tell people you're recording. Some jurisdictions need every
party's consent, some need one, and none of them care that the tool made it easy.
