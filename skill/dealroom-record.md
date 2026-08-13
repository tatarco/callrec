---
name: dealroom-record
description: Record a client call locally (mic + system audio), transcribe it on-device, and file the transcript against that client's deal record. Use when Gal says "/dealroom-record <client>", is about to get on a call with a client, or wants a call transcribed and added to the deal log.
---

# Dealroom record

Wraps `callrec` (local recording + whisper.cpp transcription) and files the result into
`~/.dealroom/`. Nothing leaves the machine.

## Usage

`/dealroom-record <client>` — starts recording.
`/dealroom-record stop` (or just "stop the recording") — stops, transcribes, files it.

## Start

1. Resolve the client to a deal slug: `~/.claude/skills/dealroom/scripts/deal.sh list`.
   Match loosely (case-insensitive, partial). If no deal exists, ask whether to create one
   (`deal.sh new`) or record under a plain slug anyway.
2. `callrec start <slug>` — recording goes to `~/Calls/<date>_<time>-<slug>.m4a`.
3. Tell Gal it's recording, in one line, and remind him **once** to get the other party's
   consent on the call. Then stop talking — he's about to be on a call.

If `callrec` warns that BlackHole is missing, say so immediately and stop: without it only
Gal's own voice is captured, which makes the transcript worthless for advice.

## Stop

1. `callrec stop` — this transcribes automatically and prints the `.txt` path.
2. Move the audio + transcript into the deal's call archive:
   `mkdir -p ~/.dealroom/calls && mv <audio> <transcript> ~/.dealroom/calls/`
3. Read the transcript.
4. Append to `~/.dealroom/deals/<slug>.md`:
   - Under a `## Call transcripts` section (create it if absent), one line:
     `- YYYY-MM-DD — <duration or topic> — ~/.dealroom/calls/<file>.txt`
   - Under `## Nuggets`, any NEW client intel the call revealed: budget signals, who holds
     the cheque, competitors named, deadlines, their own words for the problem. Quote him
     verbatim where the phrasing matters — his words are the point of recording.
   - A dated `Log` line: what the call was about and what changed as a result.
5. Bump `updated:` in the frontmatter.

**Never paste the raw transcript into the deal record.** It's memory, not an archive — a
40k-character transcript makes it useless to read. The record gets the pointer and the
extracted facts; the transcript file holds the rest.

## Why this exists

Gal's own summary of a call is filtered through what he hoped the client meant. The advisory
board (`hormozi`, `naval`, `rubin`) and the `grilling` skill give sharper answers when fed the
client's actual words. When any of those run after a recorded call, pass them the transcript,
not the summary.

## Notes
- Requires `~/bin/callrec`, `~/bin/setout`, BlackHole 2ch, and the `Call Capture`
  Multi-Output Device (speakers + BlackHole). `callrec start` switches system output to
  `Call Capture` itself and `callrec stop` switches it back — no manual step. If the
  device is ever deleted, recreate it in Audio MIDI Setup (+ → Multi-Output Device,
  speakers on top as clock master, drift correction on BlackHole only).
- While recording, the volume keys don't work (a Multi-Output limitation). Set the level
  before starting.
- Hebrew and English auto-detect; mixed-language calls transcribe per segment.
- `~/.dealroom/` is confidential and never goes in a public repo. Transcripts especially.
