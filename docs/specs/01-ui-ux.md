# 01 — UI/UX

An interactive mockup lives at [`../../mockups/bashcut-ui.html`](../../mockups/bashcut-ui.html).
Open it in a browser.

The UI language is **English by default**, and Vietnamese ships as a localization. All labels in
this document are the English strings.

## 1. Windows

### 1.1 Welcome (no project open)

```
┌──────────────────────────── BashCut ────────────────────────────┐
│  [+ New Project]   [Open…]   [Import from edl.json…]             │
│                                                                  │
│  Recent                                                          │
│  ▣ Lau bo noi dat        9:16 · 1:49 · edited 2 hours ago        │
│  ▣ Hanh trinh Laca       9:16 · 2:50 · edited yesterday          │
│  ▣ Mint video 1          9:16 · 0:58 · Sep 27                    │
│                                                                  │
│  Workspace: ~/Desktop/nolan-video-workspace  [Change]  ● Doctor OK│
└──────────────────────────────────────────────────────────────────┘
```

### 1.2 Editor window

The layout follows CapCut desktop, plus an agent dock on the right.

```
┌ Toolbar ──────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ ◀ Lau bo noi dat ▾   ↶ ↷   │ 9:16 1080×1920 · 29.97 │                 [Review ⚠3]  [Export ⤓]  [⌘J Agent ◧] │
├────┬──────────────────────┬───────────────────────────────────┬──────────────────────┬──────────────────────────┤
│ 🎞 │ LIBRARY              │            VIEWER                 │ INSPECTOR            │ AGENT  [Claude][Codex][+]│
│ ♪  │ [Footage][Project]   │        ┌─────────────┐            │ Video  Audio  Color  │ ┌──────────────────────┐ │
│ T  │ ┌────┐┌────┐┌────┐   │        │             │            │ ─────────────────    │ │ $ claude             │ │
│ ★  │ │0449││0450││0451│   │        │   (9:16)    │            │ Zoom        1.22     │ │ > trim the hotpot bit│ │
│ ✦  │ └────┘└────┘└────┘   │        │  caption…   │            │ Pan / Tilt  40 / −30 │ │ ● context get        │ │
│ ⇄  │ 🗣 speech  ▣ static  │        └─────────────┘            │ Speed       1.0×     │ │ ● timeline apply ✓   │ │
│ ◐  │                      │  ◀◀ ▶ ▶▶   00:38.12 / 01:49.81    │ Volume      −6 dB    │ │                      │ │
│ 🎙 │                      │                                   │ LUT  quinn-matte ▾   │ └──────────────────────┘ │
│    │                      │                                   │                      │ @ c-25 0474 38.1–44.6s ✕ │
├────┴──────────────────────┴───────────────────────────────────┴──────────────────────┤ [Survey][Write VO]       │
│ TIMELINE  ✂ S  ⌫  ❄  ⏩  │ 🧲 Snap  ♩ Beat snap │ ─────○──── zoom                     │ [Suggest FX][Review]     │
│ Sections │hook  │street    │grill      │hotpot ◆agent  │eat      │sidewalk│outro      │                          │
│ Beat     ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ ┆ │                          │
│ Captions │▭▭ ▭▭▭  ▭▭  ▭▭▭▭   ▭▭ ▭▭▭                                                │                          │
│ Overlay  │      ▯banner           ▯place card                                      │                          │
│ Main     │▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮▮ (color: speech / b-roll / VO)   │                          │
│ Dialogue │░░░░░░░░    ░░░░░░░░░░    ░░░░░░  (location sound, linked to Main)        │                          │
│ Voiceover│        ▒▒▒▒      ▒▒▒▒▒   ▒▒▒                                            │                          │
│ Music    │≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈ (ducked under speech)                 │                          │
│ SFX      │   ◇whoosh    ◇ding         ◇riser                                        │                          │
└──────────────────────────────────────────────────────────────────────────────────────┴──────────────────────────┘
```

### 1.3 Regions

| Region | Content | Notes |
|---|---|---|
| **Tab rail** (far left) | Media 🎞, Audio ♪, Text T, Stickers ★, Effects ✦, Transitions ⇄, Filters ◐, Voice 🎙 | Same idea as CapCut's left rail |
| **Library** | Content of the selected tab: thumbnail grid, drag to timeline, hover-scrub | Each tab is described in §3 |
| **Viewer** | Preview in the project frame (9:16 / 16:9) | TikTok safe-area overlay can be toggled; timecode; preview quality (Full / ½ / Proxy). Same engine as export |
| **Inspector** | Properties of the selected item | Tabs by item type: Video, Audio, Text, Color, Speed. Every number can be scrubbed and typed |
| **Timeline** | Tracks, section band, beat band, edit toolbar | §2 |
| **Agent dock** | Claude/Codex terminal tabs, context chip, quick actions | §4. Toggle with ⌘J; can be detached into its own window |

The minimum window size is 1280×800. On small screens the agent dock floats by default instead
of taking a column.

## 2. Timeline

### Default tracks

The tracks match the layers the workspace already uses.

| Track | Role | Today's equivalent |
|---|---|---|
| Sections | Named ranges: hook, place 1, … Double-click to rename, drag to move a boundary | `sec` in `edl.py` |
| Beat | Beat grid of the analyzed music track | `BEAT`/`PHASE`, `beatgrid.py` |
| Captions | Text items, editable inline, styled by preset | `make_subs.py` + Pillow overlay |
| Overlay (V2) | Banners, place cards, stickers, illustration images | `render_overlay.py`, `fxover.py` |
| Main (V1) | **Magnetic** main track (like CapCut): deleting a clip closes the gap | V1 in Resolve |
| Dialogue (A1) | Location sound, linked to its Main clip by default | `tieng-hien-truong.wav` |
| Voiceover (A2) | TTS / cloned voice | `giong-doc.wav` |
| Music (A3) | Background music, auto-ducked under speech | `nhac-nen.wav` |
| SFX (A4) | Sound effects | `hieu-ung.wav` |

### Clip roles on Main

Main clips are colored by role. The role comes from the old `kind` field and can be changed in
the Inspector.

| Role | Meaning |
|---|---|
| **Speech** | A real line spoken on camera; its sound is kept. |
| **B-roll** | Cutaway; its sound is kept quiet. |
| **Under VO** | Picture that sits under the voiceover. |

Review and the agent both use these roles.

### Operations

| Operation | Key / gesture | Notes |
|---|---|---|
| Split at playhead | S / ⌘B | |
| Ripple delete / lift | ⌫ / ⇧⌫ | |
| Trim, roll, slip | drag an edge / ⌥-drag / ⌘-drag the clip body | |
| Snap | 🧲, hold ⌘ to suspend | snaps to clip edges, playhead, markers |
| Beat snap | ♩ | edges snap to the nearest beat. Speech cuts round up, like `snap()` in `edl.py` |
| Auto reframe | context menu → "Change framing" | cycles the `PUNCH` table (zoom/pan/tilt) so two adjacent cuts never share a framing |
| Freeze frame, speed | ❄, ⏩ | speed ramps live in Inspector › Speed |
| Borrow picture | ⌥-drop a clip onto a Main clip | keeps the old clip's sound and takes the new clip's picture (`pic` in `edl.py`) |
| Ask the agent about the selection | ⌘K | §4.3 |

### How agent changes appear

- Changed items get a small ◆ badge.
- All changes from one request are grouped into one labeled undo step, for example
  "Claude: Trim hotpot clip to 4 s". ⌘Z reverts the whole step.
- The **History** panel lists every step and its author: you, Claude, Codex, or an external file
  change.

## 3. Library tabs

### 3.1 Media 🎞

The tab has three sources:

- **Footage**: the shoot linked to this project (`footage/` → `viddeo-sources/<shoot>`).
- **Project**: files added to the project, such as images, downloaded clips and generated files.
- **Shared**: `assets/video-stock` and `assets/anh` in the workspace.

Thumbnails carry badges from the survey:

| Badge | Meaning |
|---|---|
| 🗣 **speech** | Speech was detected. |
| ▣ **static** | The sampled frames are identical: the camera was locked off, so the clip gives only one shot size. |
| ⛔ **offline** | The file is missing, for example because an external drive is unplugged. |

Views:

- **Grid**.
- **List**: duration, resolution, fps, codec.
- **Contact sheet**: one row per clip with N frames, like `SHEET_*.jpg`.

Search and editing:

- **Search by spoken words.** Typing "lau bo" lists the clips that contain that phrase and jumps
  to the exact second.
- Open a clip in the source viewer and set I/O. Press E to insert at the playhead or Q to
  overwrite.

Survey:

- **[Survey Footage]** runs in the background and produces thumbnails, specs, static-clip
  detection and a transcript.
- The transcript is optional and takes a few minutes. Progress shows in the status bar.

### 3.2 Audio ♪

**Music** comes from `assets/nhac/`. BPM, loudness and license are read from `GHI-CHU-NHAC.md`.
Tracks get a license badge:

- ⚠ **TikTok rip, likely Content ID claimed**.
- ✓ **CC-BY, credit required**.

**SFX** come from `assets/sfx/` and are grouped by type: whoosh, pop, ding, riser, meme.

Hover a track to preview it, then drag it to Music or SFX.

**[Detect Beats]** on a music track does two things:

- It creates the Beat band.
- It warns when the detected BPM looks like half the real tempo. This is a lesson from
  `beatgrid.py`, which once reported 58.7 BPM for a 117.5 BPM track.

Downloading from TikTok or myinstants links stays agent-only (`nolan-tiktok-music`,
`nolan-sfx`), because it involves the network and copyright.

### 3.3 Text T

**Style presets:**

| Preset | Look |
|---|---|
| **Bold Outline** (food review) | White, heavy outline |
| **Cinematic Serif** | Small mustard-yellow serif, as in `--style quinn` |
| **Keyword Sticker** | Colored sticker behind the word |
| **Place Card** | Name / address / opening hours |
| **Hook Title** | Large title for the hook |
| **Chapter Card** | Chapter heading |

**[Auto Captions]** runs speech-to-text on Speech clips and the voiceover and fills the Captions
track. Each line is editable inline. Lines that are too long get a warning, because line length
matters more than font size.

Captions can be exported as `.srt`.

### 3.4 Stickers ★ and Effects ✦

The library is generated from `nolan-effects/recipes.json` and can be filtered two ways:

- **By genre**: food, travel, review, talking head, …
- **By moment**: hook, transition, emphasis, product reveal, humor, mood, rhythm, orientation.

There are two kinds of effects:

- **Clip effects** (zoom punch, shake, flash, glitch, film look): drop them on a Main clip.
- **Overlay effects** (pop text, word-by-word, typewriter, highlight, counter, banner, callout,
  REC frame, progress bar): drop them on Overlay.

Every effect has a "when to use" note. Special effects also carry *"1–2 times per video"*, taken
from the playbook.

### 3.5 Transitions ⇄

The default is a hard cut. The other transitions are whip, blink, zoom, spin, shutter, wipe and
dissolve.

Drop a transition on the join between two clips. It shows as a small handle; drag the handle to
change the duration.

### 3.6 Filters / LUT ◐

- **Looks** from `looks.json`: `quinn-matte`, `quinn-am`, `quinn-ky-uc`. You can also import a
  `.cube`.
- **Basic adjustments**: exposure, contrast, saturation, temperature, tint, vignette.
- **Scope**: apply to one clip, to the selection, or to the whole video.
- **Compare**: a split before/after slider in the viewer.

### 3.7 Voice 🎙

This tab is the manual counterpart of the `nolan-voice-clone` skill.

```
┌ Voice ────────────────────────────────────────┐
│ Voice: [nolan_podcast_ip1 ▾]  (default)       │
│   tags: podcast · slow · warm · clean         │
│ ┌───────────────────────────────────────────┐ │
│ │ Trong lúc chờ lẩu sôi, tụi mình gọi thêm  │ │
│ │ một mâm đồ nướng.                         │ │
│ └───────────────────────────────────────────┘ │
│ Speed 1.12×   [Normalize text ✓]              │
│ [Generate → 3 takes]                          │
│  ○ take 1  ▶  match 98 %   2.9 s              │
│  ● take 2  ▶  match 100 %  3.1 s  ★ best      │
│  ○ take 3  ▶  match 91 %   3.0 s              │
│ [Insert into Voiceover at playhead]           │
│ ───────────────────────────────────────────── │
│ [+ Clone New Voice…]                          │
└───────────────────────────────────────────────┘
```

- **Generate** produces 3 takes, scores each one with speech-to-text, and marks the best. This
  matches what `scripts/doc` does today.
- **Insert** shows a red warning on the timeline if the voiceover lands within 0.3 s of real
  speech. The rule comes from `mix.py`.
- **Clone New Voice** is a 3-step wizard:
  1. Pick about 8 s of audio, from media or recorded live. The recording script from
     `KICH-BAN-THU-GIONG.md` is shown.
  2. Optionally remove background music with Demucs.
  3. Name the voice, add tags and test one sentence. The result is written to
     `assets/giong/voices.json`.
- If the workspace venv `tools/.venvs/vieneu` is missing, the tab shows the install command
  (`bash tools/editor-skills/nolan-voice-clone/setup.sh --demucs`) and a button that runs it after
  confirmation.

## 4. Agent dock

### 4.1 Anatomy

```
┌ AGENT ─────────────────────────────── ⤢ ✕ ┐
│ [● Claude] [Codex] [+]                     │   one tab = one session; ● = running
├────────────────────────────────────────────┤
│ (real terminal: claude / codex TUI)        │
│                                            │
├────────────────────────────────────────────┤
│ @ c-25 · 0474 · hotpot · 38.1–44.6 s  [✕]  │   context chip (follows the selection)
│ [Survey] [Write VO] [Suggest FX] [Review]  │   quick actions (prompt templates)
│ [Lessons]                                  │
└────────────────────────────────────────────┘
```

**The terminal is a real terminal** (SwiftTerm) running `claude` or `codex` with `cwd` set to the
workspace. Slash commands, `nolan-*` skills, hooks and permission prompts all behave exactly as
they do outside BashCut.

**[+]** opens a new tab:

- Choose Claude, Codex, or *Shell* (plain zsh).
- If an earlier Claude or Codex session exists for this project, the app offers to resume it.

**The context chip** follows the timeline or library selection. Click ✕ to send nothing.

**Quick actions** insert a prompt template into the terminal. You can edit it before pressing
Enter. The templates are stored in English; the agent replies in the language you write in.

| Button | Template (summary) |
|---|---|
| Survey | "Run nolan-footage-survey on this project's footage, look at the contact sheets, say plainly if coverage is missing" |
| Write VO | "Extract the spoken lines of Speech clips, draft continuous narration so speech covers ≥ 90 %, with a lead-in before each real line" |
| Suggest FX | "Suggest effects for the selection from memos/hieu-ung-tra-cuu.md, at most 1–2 special effects" |
| Review | "Run bashcut review, explain each issue and propose a fix" |
| Lessons | "Run nolan-self-learn for this session" |

### 4.2 How the agent edits the timeline

The agent calls `timeline apply` through MCP or the `bashcut` CLI (see
`05-agent-integration.md`). In the UI you see:

1. A thin "Claude is editing…" bar above the timeline.
2. All changes landing at once, each with a ◆ badge.
3. A toast: "Claude: Trim hotpot clip to 4 s · [Undo] [Show Changes]".

**[Show Changes]** highlights the changed items and opens a before/after list.

Two guards protect your own edits:

- If you are mid-drag or mid-trim, the agent's operation waits until you finish.
- If the agent read an older revision of the timeline, its operation is rejected and it has to
  read the timeline again (optimistic revision).

### 4.3 ⌘K: ask the agent in place

Select a clip, a time range or a caption line, then press ⌘K. A small popover opens next to the
selection:

```
┌ Ask the agent… ──────────────────────────┐
│ c-25 · 0474 · hotpot · 38.1–44.6 s  [📷 frame]│
│ ┌──────────────────────────────────────┐ │
│ │ trim to 4 s, keep the "so much        │ │
│ │ topping" line                         │ │
│ └──────────────────────────────────────┘ │
│            [Send to Claude ⏎] [Codex ⌥⏎] │
└──────────────────────────────────────────┘
```

The popover sends a `[BashCut context]…` block and your sentence to the active agent tab. It also
opens the dock if the dock is hidden.

## 5. Review

The toolbar button shows how many issues are open, for example **[Review ⚠3]**. The checks come
from the playbook and the workspace's lessons:

| Check | Threshold | Source |
|---|---|---|
| Hook | ≤ 7 s, with a title | playbook §2 |
| Speech coverage | ≥ 90 % of runtime (food review), ≥ 60 % (cinematic) | playbook §1, hanh-trinh-laca memo |
| Unintended silence | > 0.8 s | playbook §5 |
| Voiceover overlapping real speech | gap < 0.3 s | `mix.py` |
| Two adjacent cuts with the same framing | same source clip and same zoom | `nolan-beat-cut` |
| Special effects | used more than 2 times | playbook §3 |
| Outro | the last 5 s contain speech or a call to action | playbook §2 |
| Loudness | −14 LUFS ± 1 | `nolan-audio-mix` |
| Offline media, or TikTok-ripped music in a public export | any | |

Clicking an issue jumps the timeline to that spot. Each issue also has a **[Ask Agent to Fix]**
button.

## 6. Export

```
┌ Export ───────────────────────────────────────┐
│ Name      lau-bo-noi-dat-v8                    │
│ Preset    [TikTok / Reels 9:16 ▾]              │
│           1080×1920 · 29.97 fps · H.264 16 Mbps│
│ Audio     AAC 320 kbps · normalize −14 LUFS ✓  │
│ Save to   projects/lau-bo-noi-dat/render/      │
│ ☐ Include .srt captions                       │
│ ⚠ 3 review issues still open  [Show]           │
│                         [Cancel]  [Export ⏎]   │
└────────────────────────────────────────────────┘
```

**Background queue.** Exports run in a background queue with progress in the status bar, so you
can keep editing.

**After export:**

- The app shows duration, cut count, LUFS, speech coverage and file size.
- Buttons: [Open], [Reveal in Finder], [Compare with Previous], [Lessons].

**Presets:**

- TikTok/Reels 9:16
- YouTube 16:9 1080p / 4K
- Quick Draft 720p
- ProRes 422 HQ (to finish in another app)

Later, the dialog gains *Export OTIO* and *Apply to DaVinci Resolve* targets (see
`03-architecture.md` §7). They are not part of v1.

## 7. Keyboard shortcuts

| Key | Action |
|---|---|
| Space / J K L | play/pause; reverse/stop/forward (press repeatedly to speed up) |
| ← → (⇧) | 1 frame (1 s) |
| I / O | mark in / out |
| S, ⌘B | split |
| ⌫ / ⇧⌫ | ripple delete / lift |
| E / Q | insert / overwrite from the source viewer |
| N | snapping on/off |
| ⌘K | ask the agent about the selection |
| ⌘J | show/hide the agent dock |
| ⌘⇧A | switch tab Claude ↔ Codex |
| ⌘E | export |
| ⌘⇧R | review |
| ⌘1…⌘8 | library tabs |
