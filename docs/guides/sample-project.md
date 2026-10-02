# Sample project

`scripts/sample-project.py` builds a small project that puts every kind of thing the editor draws on one
timeline, so you can open it and try a change against all of them, and checks the result end to end.

```bash
scripts/run.sh                          # build and open build/BashCut.app
scripts/sample-project.py               # make: generate media, build the project, run the checks (~10 s)
scripts/sample-project.py --light       # the same without the 4K HEVC clip
scripts/sample-project.py check         # re-run the checks against the open sample project
scripts/sample-project.py open          # open build/sample-project/bashcut-sample again
```

It needs `ffmpeg` (`brew install ffmpeg`) and Python 3 (it comes with Xcode's command line tools). The project
lives in `build/sample-project/bashcut-sample`, which git ignores; `make` deletes and rebuilds it each time.
It refuses to replace a project with unsaved changes unless you pass `--discard-current`.

## How it is built

The script drives the running app with the same `bashcut` commands agents use: `project create`,
`media import`, `luts import`, `timeline apply` with fixed item IDs, `captions import`, `layers add` and
`layers set`. A broken command or rule makes `make` fail, so it is also an end-to-end test of the automation
surface. Media is synthetic (ffmpeg test patterns, tones, noise), a few seconds each.

## What is on the timeline

The project is 1080×1920 at 30 fps and 28 s long, with sections Hook (0 s), Body (8 s) and Outro (22 s).

| Layer | Items | What it exercises |
|---|---|---|
| Captions | `title` (hook-title style), four cues from `captions.srt` | Text items, SRT import |
| Hidden overlay | `o3-hidden` | Hidden layer: faded, left out of preview and export |
| Locked overlay | `o2-locked` | Locked layer: stripes, edits are refused |
| Overlay | `o1-pip` | Picture in picture: zoom, pan, tilt, opacity |
| Main | `m1-portrait` | Linked sound, `speech` tag, LUT at 80 % with exposure and saturation |
| | `m2-landscape` | Landscape clip reframed (zoom 1.35); dissolve from `m1`; the agent-changed clip (sparkle) |
| | `m3-silent` | Silent video, `underVO` tag, freeze frame |
| | gap (20–22 s) | Hatched gap: select it, Delete closes it |
| | `m4-fast` | 2× speed with muted linked sound |
| | `m5-4k` | 4K HEVC, so a preview proxy is made (not with `--light`) |
| Dialogue | `d1-portrait`, `d2-landscape`, `d4-fast` | Linked audio partners, waveforms |
| Voiceover | `vo1-overlap`, `vo2` | `vo1` overlaps speech: red warning in the timeline and Review |
| Music | `music` | −6 dB, fades, ducking under speech, a 120 BPM beat grid (orange lines) |
| SFX (muted) | `sfx-whoosh`, `sfx-ding` | Muted layer |

The project catalog has one LUT, `Warm look`, imported from a generated `.cube` file.

## The checks

`check` reads the project back and fails on anything missing: every layer role, the LUT reference, links,
freeze frame, speed, the gap, transition, sections, captions, locked/hidden/muted layers, ducking, the beat
grid, the 4K clip, and the voiceover warning from `review run`. Then it drives the editor: zoom to fit, select a
clip, `shift+right`, a move on the locked layer (must be refused), split at the playhead and undo. It leaves the
project as it was and saved.

## Adding a case

When a feature adds something the timeline or viewer shows, add it here: generate any media it needs in
`make_media`, put it on the timeline in `build` with a fixed ID, assert it in `check`, and add a row to the
table above.
