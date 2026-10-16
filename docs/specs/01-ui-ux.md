# 01 — UI/UX

The windows, panels, gestures and shortcuts of the editor, and how agent edits appear in them. It is for anyone
building or reviewing the UI; the interactive mockup is [`mockups/bashcut-ui.html`](../../mockups/bashcut-ui.html)
(open it in a browser).

The UI is **English by default**, with Vietnamese shipped as a localization; all labels here are the English
strings. Parts not built yet are marked **Planned** (see [status markers](README.md#status-markers)); the
control-by-control gap list is in [mockup parity](../status/mockup-parity.md).

## 1. Windows

### 1.1 Welcome (no project open)

```text
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

The layout follows CapCut desktop, plus two side columns that show and hide on their own: the Inspector beside the viewer (the timeline spans the editor's width under it) and the agent dock at the window's right edge, the full height beside the timeline. They were two tabs of one right column (P1-6); selecting a timeline item brought the Inspector forward and took the agent away mid-work, so they are separate now.

```text
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
| **Tab rail** (far left) | Media 🎞, Audio ♪, Text T, Stickers ★, Effects ✦, Transitions ⇄, Filters ◐, Brand 🎨, then after a divider Tools 🔧 and, when a plugin has a panel, More ⋯ | Same idea as CapCut's left rail. Voiceover lives in Tools, plugin panels in the More popover. In a window shorter than 900 pt the tiles show icons only and the label is the tooltip |
| **Library** | Content of the selected tab: thumbnail grid, drag to timeline, hover-scrub | Each tab is described in §3 |
| **Viewer** | Preview in the project frame (9:16 / 16:9), timecode, toggleable TikTok safe area | Same engine as export. Heavy footage plays from automatic proxies; a manual quality picker (Full / ½ / Proxy) is Planned |
| **Inspector** | Properties of the selected item | A column beside the viewer (300 pt; 340 pt from a 1680 pt window), shown or hidden with ⌃⌘I or its toolbar button. Header: kind colour bar, name, kind and layer, timecode range and length (the ID is under Copy ID). Tabs by kind: clip Video, Audio, Color, Speed; graphic Video, Color; text and caption Text, Video; audio Audio, Speed; adjustment Color. With nothing selected it shows the project (format, frame rate, clip fit, length, sections, outputs). Every number can be scrubbed and typed. Selecting a timeline item never changes which columns show |
| **Timeline** | Tracks, Sections band, Beat band, edit toolbar | §2 |
| **Agent dock** | Claude / Codex / Shell terminal tabs, context chip, quick actions | §4. A column of its own at the window's right edge, the full height; the toolbar's agent status shows while it works. ⌘J or its toolbar button shows or hides it; **Pop out** moves it into its own window and the column leaves the editor until it comes back (⌘J) |

The minimum window size is 1280×800. The window grows to the agent column's width (editor 860 pt plus the 300 pt column) when it opens; the Inspector needs no extra width. `ui view --right-tab inspector|agent` shows that pane and leaves the other as it is.

## 2. Timeline

### 2.1 Default tracks

The tracks match the layers the workspace already uses. More video, adjustment, text and audio layers can be added
(**Add Layer**); their stacking order is explicit (see [02 — Project format](02-project-format.md)). An adjustment
layer grades every layer below it, so a look is a clip you can trim, move, stack and hide instead of a setting.

| Track | Role | Today's equivalent |
|---|---|---|
| Sections | Named ranges (hook, place 1, …). Double-click to rename, drag to move a boundary | `sec` in `edl.py` |
| Beat | Beat grid of the analyzed music track | `BEAT`/`PHASE`, `beatgrid.py` |
| Captions | Text items, editable inline, styled by preset | `make_subs.py` + Pillow overlay |
| Overlay (V2) | Banners, place cards, stickers, illustration images | `render_overlay.py`, `fxover.py` |
| Main (V1) | **Magnetic** main track, as in CapCut: deleting a clip closes the gap | V1 in Resolve |
| Dialogue (A1) | Location sound, linked to its Main clip by default | `location-sound.wav` |
| Voiceover (A2) | TTS or cloned voice | `voiceover.wav` |
| Music (A3) | Background music, auto-ducked under speech | `music.wav` |
| SFX (A4) | Sound effects | `sfx.wav` |

### 2.2 Clip roles on Main

Main clips are colored by role. The role comes from the old `kind` field and can be changed in the Inspector.
Review and the agent both use these roles.

| Role | Meaning |
|---|---|
| **Speech** | A real line spoken on camera; its sound is kept |
| **B-roll** | Cutaway; its sound is kept quiet |
| **Under VO** | Picture that sits under the voiceover |

### 2.3 Operations

| Operation | Key or gesture | Notes |
|---|---|---|
| Split at playhead | S / ⌘B | |
| Ripple delete / lift | ⌫ / ⇧⌫ | Lift leaves a gap |
| Trim, roll, slip | Drag an edge / ⌥-drag an edge / ⌘-drag the clip body | Roll and slip are also in the Inspector |
| Move | Drag a clip | Within a magnetic track, dragging reorders; linked Dialogue follows. Clicking a clip selects it without moving the playhead; click empty space to move the playhead |
| Snap | 🧲 Snap; hold ⌘ to suspend | Snaps to clip edges, the playhead, markers and beats |
| Beat snap | ♩ | **Planned** as a separate toggle (beats are already snap targets). Speech cuts should round up, like `snap()` in `edl.py` |
| Change framing | Inspector › Video › "Change framing" | Cycles Wide, Medium, Close and left/right emphasis presets so adjacent cuts get different framing. The `PUNCH` table from `edl.py` is the model |
| Freeze frame, speed | Inspector › Speed | Constant speed and freeze frame. Speed ramps are **Planned** |
| Borrow picture | ⌥-drop a clip onto a Main clip | **Planned.** Keeps the old clip's sound and takes the new clip's picture (`pic` in `edl.py`); already imported from `edl.json` |
| Ask the agent about the selection | ⌘K | §4.3 |
| Scrub | Drag the playhead grip, the red line or anywhere on the ruler | The cursor becomes ↔ over them; a timecode label follows; the playhead snaps to cuts, sections and beats; dragging past the edge scrolls. During playback the view turns the page when the playhead leaves it |
| Step | ← / → (⇧ for one second) | Timeline focused |
| Drag feedback | — | Moving a clip shows a see-through copy on the layer it would land on with a closed-hand cursor; trims show the new extent; a cyan line marks the target, a yellow line a snap, and a label shows the new start, duration or change |
| Hover | — | The clip under the pointer lights up and shows CapCut-style trim brackets; the cursor shows whether a drag moves (open hand) or trims (↔) |
| Context menu | Right-click a clip | Split, Delete, Lift, Freeze frame, Change framing, Unlink audio, Lock/Unlock layer (`clip.*` and `timeline.*` actions) |
| Delete a gap | Click the hatched gap on Main, then ⌫, or right-click › Delete gap | `timeline close-gap` |
| Drop media | Drag from the Media or Audio panel, or files from Finder | Lands on the layer under the pointer when it takes that kind of media (else main or music), at the snapped frame; spills like any placement |
| Layer header | Pinned on the left | Compact by default (78 pt): a short ID per layer (V1… visual layers from the back, A1… audio layers from the top; Main has a filled chip), an icon, and hide (visual layers), mute (audio layers) and lock switches (`layers set`). Hovering the ID shows `V3 · Captions`, double-click renames, the selected row shows its name. Drag the right edge for a wide header with full names; the width is remembered (`ui action timeline.header-compact` toggles). IDs come from the layer order and are not stored; `timeline get` reports them as `label` and `--track` accepts them. Clips on hidden, muted or locked layers are drawn faded or striped |

### 2.4 How agent changes appear

- Changed items get a small ◆ badge.
- All changes from one request form one labeled undo step, for example "Claude: Trim hotpot clip to 4 s". ⌘Z
  reverts the whole step.
- The **History** panel lists every step and its author: you, Claude, Codex, or an external file change.

## 3. Library tabs

### 3.1 Media 🎞

The tab has three sources:

| Source | Content |
|---|---|
| **Footage** | The shoot linked to this project (`footage/` → `viddeo-sources/<shoot>`) |
| **Project** | Files added to the project: images, downloaded clips, generated files |
| **Shared** | `assets/video-stock` and `assets/anh` in the workspace |

Thumbnails show resolution, frame rate and duration, hover-scrub through the clip, and carry badges:

| Badge | Meaning | Status |
|---|---|---|
| ⛔ **offline** | The file is missing, for example because an external drive is unplugged | Implemented |
| 🗣 **speech** | Speech was detected | Planned (needs the survey) |
| ▣ **static** | The sampled frames are identical: the camera was locked off, so the clip gives only one shot size | Planned (needs the survey) |

Heavy footage gets a preview proxy automatically; **Create Preview Proxy** in the tile menu makes one by hand.

Open a clip in the source viewer, set In/Out with I and O, then press E to insert at the playhead or Q to
overwrite.

The viewer header is a **Timeline | Source** switch, so it always says which picture is on screen. Source names
the Media clip, gets a cyan frame and a one-line hint, and is disabled until a clip has been opened. Esc, the
Timeline segment, or any click, drag, seek or selection on the timeline returns to the timeline; the Source
segment (`source.show`) shows the last clip again where it was left.

**Planned:**

- **List** view (duration, resolution, fps, codec) and **contact sheet** view (one row of N frames per clip, like
  `SHEET_*.jpg`).
- **Search by spoken words:** typing "lau bo" lists the clips that contain the phrase and jumps to the exact
  second.
- **[Survey Footage]:** a background job that produces thumbnails, specs, static-clip detection and an optional
  transcript (a few minutes), with progress in the status bar.

### 3.2 Audio ♪

Audio files can be imported and inserted into Music, SFX or Voiceover. **Beat detection** (Tools, on the selected audio clip or an audio file) runs an
`audio.beats` provider and creates the Beat band, which the timeline snaps to.

**Planned:**

- A **Music** catalog from `assets/music/`, with BPM, loudness and license read from `music-notes.md`, and license
  badges: ⚠ **TikTok rip, likely Content ID claimed** or ✓ **CC-BY, credit required**.
- An **SFX** catalog from `assets/sfx/`, grouped by type: whoosh, pop, ding, riser, meme.
- Hover preview before dragging a track to Music or SFX.
- A warning when the detected BPM looks like half the real tempo. This is a lesson from `beatgrid.py`, which once
  reported 58.7 BPM for a 117.5 BPM track.

Downloading from TikTok or myinstants links stays agent-only (`nolan-tiktok-music`, `nolan-sfx`), because it
involves the network and copyright.

### 3.3 Text T

**Text presets** (per caption; a style kit can set them all at once):

| Preset | Look |
|---|---|
| **Bold Outline** (food review) | White, heavy outline |
| **Cinematic Serif** | Small mustard-yellow serif, as in the workspace's `--style quinn` |
| **Keyword Sticker** | Colored sticker behind the word |
| **Place Card** | Name, address and opening hours |
| **Hook Title** | Large title for the hook |
| **Chapter Card** | Chapter heading |

**Auto captions** (Tools, on the selected clip or a media file) runs a `captions.transcribe` provider and fills the Captions track. Each line is editable
inline. Review warns about lines longer than 42 characters, because line length matters more than font size.

Captions can be imported from and exported to `.srt`.

### 3.4 Stickers ★ and Effects ✦

Stickers currently insert emoji as text items. The rest of this tab is **Planned**.

The library is generated from `nolan-effects/recipes.json` and filters two ways:

- **By genre:** food, travel, review, talking head, …
- **By moment:** hook, transition, emphasis, product reveal, humor, mood, rhythm, orientation.

There are two kinds of effects:

- **Clip effects** (zoom punch, shake, flash, glitch, film look): drop them on a Main clip.
- **Overlay effects** (pop text, word-by-word, typewriter, highlight, counter, banner, callout, REC frame, progress
  bar): drop them on Overlay.

Every effect has a "when to use" note. Special effects also carry *"1–2 times per video"*, from the playbook.

### 3.5 Transitions ⇄

The default is a hard cut. The panel groups the other 39 transitions as Fade, Whip, Wipe, Shape, Crash, Roll, Arc,
Infinite, Screen, Seamless and Stylized (the technique names of eyecannndy.com/technique/transition, plus its most used
cut techniques: flash cut, double exposure, colour shift, kaleidoscope); all of them render the
same in preview and export. Text, stickers, graphics and overlay clips that are not part of a cut use the same kinds as their own
In and Out (Inspector › Video or Text › In and Out, grouped like the panel, with length and easing), played inside
the item's frame; clicking a tile with such an item selected, or dragging a tile onto one, sets its In.

Select a clip beside a cut and choose a transition; the panel adjusts its duration in frames. A draggable handle
on the join is **Planned**.

### 3.6 Filters / LUT ◐

| Control | Content | Status |
|---|---|---|
| **Style kits** | Removed (C8/C9): a kit is skill data or a library pack (a look plus a text preset) | Removed |
| **Add adjustment** | An adjustment item over the selected clip's range, or 3 seconds at the playhead | Implemented |
| **Looks** | Original, Vivid, Muted film, Black & white, Bright & airy, Moody, plus looks saved in the project or user library: grade the selected clip or adjustment; with nothing selected, add an adjustment | Implemented |
| **3D LUTs** | Import a `.cube` into the project, apply it to a clip or adjustment with adjustable strength (nothing selected adds an adjustment) | Implemented |
| **Bundled looks** | `quinn-matte`, `quinn-am`, `quinn-ky-uc` from `looks.json` | Planned |
| **Basic adjustments** | Exposure, contrast, saturation (Inspector › Color) | Implemented |
| | Temperature, tint, vignette | Planned |
| **Scope** | One clip, or every layer below an adjustment item for its range | Implemented |
| **Compare** | Split before/after slider in the viewer | Implemented |

### 3.7 Voice 🎙 (now Tools › Voiceover)

This tab is the manual counterpart of the `nolan-voice-clone` skill.

```text
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

- **Generate** produces 3 takes, scores each one and marks the best, as `scripts/doc` does today.
- **Insert** puts the chosen take on Voiceover at the playhead. The timeline shows a red warning when the
  voiceover lands within 0.3 s of tagged speech; the rule comes from `mix.py`.
- **Record** captures a voiceover from the microphone (48 kHz mono WAV, with a level meter) and inserts it at the
  playhead **(to verify)** on real hardware.
- The tab resolves an installed `voice.synthesize` provider. If its model, venv or executable is missing, the tab
  links to Plugins, where the dependency probe and exact install command are shown before the user approves them.
  Switching providers does not change existing timeline items.
- **Clone New Voice** is **Planned**: a 3-step wizard.
  1. Pick about 8 s of audio, from media or recorded live, with the recording script from `voice-clone-script.md`
     on screen.
  2. Optionally remove background music with Demucs.
  3. Name the voice, add tags and test one sentence. The result is written to `assets/voices/voices.json`.

### 3.8 Plugins sheet 🧩

The Plugins sheet opens from the toolbar and from linked panels. Plugins hold optional, replaceable providers and
run outside the editor process. A ready plugin with `contributes.container` (plugin API 8) also adds an entry to the
rail's More popover (the last tile of the left rail); it opens the plugin's panel in the library column: a header with its settings
button, its declarative views (drawn natively from the components the plugin sends; only while on screen), and its
Tools, Skills, Requires and Uses ([plugin guide](../guides/plugins.md#plugin-panels-and-views)). Views can also
live in a tab of the agent dock (`location: dock`), a sheet (`location: sheet`, opened by the plugin or
`plugins show-view`) or a non-modal window (`location: window`, API 11, D2): 75% of the editor window, at least
900×600, remembered per view, keeping its state when closed until the project closes; **Dock** shows it over the
viewer instead (**Undock** or Esc).

- The sheet lists each plugin's name and version, capability IDs, provider choices, dependency health and manifest
  diagnostics.
- **Add Plugin…** (also a drop on Installed, and Settings › Plugins) takes a link (zip, GitHub repo, folder,
  `plugin.json` or release; optional `#sha256=`; a per-host token in `plugin-secrets.json`) or a plugin folder, its
  `plugin.json`, or a `.zip` / `.bashcutplugin` archive. It validates and stages a copy, shows an unsigned badge, the source and every
  dependency recipe, and installs into this Mac's or the open project's plugin folder.
  A folder can instead be installed as a link (developer mode), which Installed shows with **Reload**; copied
  plugins have **Replace…** to update from a new folder or zip with the same id.
- Discovery order is project (`.bashcut/plugins`), user (`Application Support/BashCut/Plugins`), then bundled.
- A project can pick a provider per capability. An unavailable preference falls back to a healthy provider by
  priority.
- A missing plugin disables only its feature. The project, timeline, preview and normal export stay available.

Capabilities used by panels today:

| Panel | Capability |
|---|---|
| Tools › Voiceover | `voice.synthesize` |
| Tools › Auto captions | `captions.transcribe` |
| Tools › Beat detection | `audio.beats` |
| Export › Normalize Audio | `audio.loudness` |

The app records plugin, provider and version provenance on generated assets and measurements. It never takes
plugin output directly as timeline JSON. Details are in the [plugins guide](../guides/plugins.md).

## 4. Agent dock

### 4.1 Anatomy

```text
┌ AGENT ─────────────────────────────── ⤢ ✕ ┐
│ [● Claude] [Codex] [+]                     │   one tab = one session; ● = running
├────────────────────────────────────────────┤
│ (real terminal: claude / codex TUI)        │
│                                            │
├────────────────────────────────────────────┤
│ @ c-25 · 0474 · hotpot · 38.1–44.6 s  [✕]  │   context chip (follows the selection)
│ [Review] [Export draft] [Grade]            │   quick actions for the project's state

└────────────────────────────────────────────┘
```

**The terminal is a real terminal** (SwiftTerm) running `claude` or `codex` in the workspace. Slash commands,
`nolan-*` skills, hooks and permission prompts behave exactly as they do outside BashCut.

**[+]** opens a new tab: Claude, Codex or *Shell* (plain zsh). When an earlier Claude or Codex conversation exists
for this project, the dock offers **Continue** or **New conversation**. A handoff moves the project context from
one agent to the other.

**Empty state.** Before any agent runs, the tab shows one primary button (**Start** the default agent, or **Continue** when this project has a conversation to pick up), an **Other agents** menu (chat agents such as AI Editor, the other terminal agents, New conversation) and a one-line explainer.

**Setup steps.** What is left to set up (the agent kit for Claude Code and Codex outside BashCut, and the shown chat
agent's API key) collapses into one "N setup steps for the agent" row under the tabs; it opens to each step with
its Set Up, Details…, Later or Settings… button.

**Quick starts.** The empty tab and an empty chat show a line about the project and 2–5 template cards for its
state, the first one wide, then **All templates (25) →**, which opens New brief (§4.3). A card puts its filled
request in the agent's input (with no agent open it opens the first chat agent, else New brief). The state comes
from the project (`BriefFit.state`):

| State | When | Cards | Quick actions under the input |
|---|---|---|---|
| none | No project, or nothing in it | Explainer, News | New project (Import media… in an empty project), Open… |
| footage | Media, empty timeline | Daily vlog, Travel, Food, Music montage, Product review | Survey footage, Rough cut, Write VO |
| talk | One clip with sound ≥ 10 min, at most that clip on the timeline | Clips from a long video, Talking to camera, Cut silences, Captions, Short video | Cut short clips, Remove silences, Captions |
| timeline | Items on the timeline | Stronger hook, Faster pace, Color grade, Captions, Export & post | Review (opens Review), Export draft (opens Export), Grade |
| selection | Timeline items selected | Fix the selection, Add B-roll, Color grade, Balance music & voice, Captions | Fix this clip, Replace shot, Review this part |

A quick action runs the editor action it names, or puts its request (a template or a short prompt) in the agent's
input to review before sending. A terminal tab, which has no message box, gets a **New brief…** button at the end
of the row. The workspace folder (where agent terminals start) is set from the **+** menu (**Workspace: name…**).

**Composer.** A chat tab's message box has **Templates** (the 25 templates by group, the ones that fit first),
**Frame** (attach the viewer frame) and **Expand…** (continue the message in New brief). Typing `/` at the start
opens one menu with the chat commands under **Commands** and the templates under their group headings; the
template search ignores case and accents ("dich" finds "Dịch phụ đề"). Picking a template puts its request in the
box with each empty field as `‹field›`, the first one selected so typing replaces it.

The dock also has a **Knowledge** sheet for the
project memo and project skills (kept in the project folder) and the notes every project reads. See the [automation guide](../guides/automation.md).

### 4.2 How the agent edits the timeline

The agent calls `timeline apply` (or a dedicated command) through MCP or the `bashcut` CLI; see
[05 — Agent integration](05-agent-integration.md). In the UI:

1. All changes land at once, each with a ◆ badge.
2. A toast appears: "Claude: Trim hotpot clip to 4 s · [Undo] [Show Changes]".
3. **[Show Changes]** highlights the changed items and opens a before/after list.

A thin "Claude is editing…" bar above the timeline is **Planned**.

Two guards protect your own edits:

- While you are mid-drag or mid-trim, an agent edit is rejected as busy, and the agent retries.
- If the agent read an older revision of the timeline, its edit is rejected and it has to read the timeline again
  (optimistic revision).

### 4.3 ⌘K: ask the agent

⌘K (Agent › New Brief…), **All templates** in the dock, **Expand…** in a chat tab or the **New brief…** button
under a terminal opens New brief ("Giao việc" in Vietnamese):

```text
┌ New brief ──────────────────────────────────────────── [Search templates…] ┐
│ To AI Editor · about Whole project · ⌘↩ sends                              │
├──────────────────────────┬─────────────────────────────────────────────────┤
│ RECENT                   │ 🚶 Daily vlog   recipe: vlog-daily              │
│  🕘 Explainer · orders   │ Topic   [a workday in Saigon            ]       │
│ SAVED                    │ Length  (30 s) (●60 s) (3 min) (8 min) (other…) │
│  ☆ My TikTok 30 s        │ Mood    (●chill) (fun) (cinematic) (other…)     │
│ MAKE A VIDEO          13 │ REQUEST TO SEND · EDITABLE   ↺ Reset to template│
│  Daily vlog         FITS │ ┌─────────────────────────────────────────────┐ │
│  Talking to camera (dim) │ │ Make a vlog about a workday in Saigon, …    │ │
│ FIX THE EDIT           8 │ └─────────────────────────────────────────────┘ │
│ FINISH                 4 │                                                 │
├──────────────────────────┴─────────────────────────────────────────────────┤
│ [ ] Attach current frame          [☆ Save as template] [Cancel] [Send]     │
└────────────────────────────────────────────────────────────────────────────┘
```

The list has **Recent** (the last five briefs sent in this project, kept in `.bashcut/briefs.json`), **Saved** (the
user's own templates from **Save as template**, for every project on this Mac) and the 25 templates in three groups:
Make a video (13), Fix the edit (8) and Finish (4). Each template names the agent kit recipe it belongs to; the ones
that fit the project's state carry **FITS** and come first, the others are dimmed but can be picked. The search
ignores case and accents. Chips replace the old `[brackets]`; **other…** takes a value of your own. The request
below is editable: edits by hand stay when chips change, until **Reset to template**. **Send** (⌘↩) sends it to the
shown agent: a terminal tab gets it pasted and Return pressed, a chat tab starts a turn. Only the request and the
attached frame's path are sent; the agent reads the selection and playhead with `context get`. The draft is kept
when the sheet is closed. Agents can answer the sheet with `ui respond send|clear|close` (`ui dialog` name `ask`).

## 5. Review

The toolbar button shows how many issues are open, for example **[Review ⚠3]**. Clicking an issue jumps the
timeline to that spot, and **[Ask agent to fix]** sends the issue to the active agent.

The checks come from the playbook and the workspace's lessons. Most work from timeline structure, clip roles and
voiceover timing; loudness comes from the last normalized export of the revision, and picture checks from
`review measure` (rendered frames of the revision, two a second).

| Check | Threshold | Source | Status |
|---|---|---|---|
| Gap on Main | any gap without picture | magnetic Main | Implemented |
| Two adjacent cuts with the same framing | same source clip and same transform | `nolan-beat-cut` | Implemented |
| Voiceover near real speech | gap < 0.3 s from tagged speech | `mix.py` | Implemented |
| Long caption line | > 42 characters | caption lessons | Implemented |
| Speech coverage | ≥ 90 % of runtime (food review) from tagged speech and voiceover | playbook §1 | Implemented |
| | ≥ 60 % (cinematic) | hanh-trinh-laca memo | Planned |
| Hook | ≤ 7 s, with a title | playbook §2 | Planned |
| Unintended silence | > 0.8 s | playbook §5 | Planned |
| Special effects | used more than 2 times | playbook §3 | Planned |
| Outro | the last 5 s contain speech or a call to action | playbook §2 | Planned |
| Loudness | −14 LUFS ± 1 | `nolan-audio-mix` | Planned (measured only during normalized export) |
| Black or empty picture | ≥ 0.5 s (a fade out of ≤ 1 s at the end passes) | #432 | Implemented (`review measure`) |
| Frozen picture | > 4 s vertical, 8 s landscape, outside freeze frames | Reelcrew study | Implemented (`review measure`) |
| Jump cut | < 6 % change across a hard cut on Main | #432 | Implemented (`review measure`) |
| Shot length | < 0.4 s, or > 8 s (15 s landscape) without motion; project `review` overrides | Reelcrew study | Implemented |
| Offline media, or TikTok-ripped music in a public export | any | | Planned |

## 6. Export

```text
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

| Preset | Output |
|---|---|
| TikTok / Reels | 9:16, H.264 |
| YouTube 1080p / 4K | 16:9, H.264 |
| Quick Draft | 720p, H.264 |
| ProRes | ProRes 422 HQ, to finish in another app |

- **Status bar.** Under the editor: the selection (`1 selected · name`), the project length and, while jobs run, `▶ n jobs` with a popover of their progress, Open and Cancel; a one-off notice shows in it for 8 s.
- **Background queue.** Exports run one at a time in the background, with progress in the status bar, so you can
  keep editing. Agent exports need approval in the app first.
- **Normalize audio** needs an installed `audio.loudness` provider; it runs a two-pass normalization to the target
  LUFS with a −1 dBTP ceiling.
- **After export,** the report shows duration, cut count, captions, LUFS (when normalized), tagged speech coverage
  and file size, compared with the previous export. Buttons: **[Open]** and **[Reveal in Finder]**. A
  **[Lessons]** button is **Planned**.
- **Other targets.** *Export OTIO* is Implemented. *Apply to DaVinci Resolve* is **Reserved** (see
  [03 — Architecture](03-architecture.md) §7).

## 7. Keyboard shortcuts

Shortcuts belong to editor actions; `bashcut ui actions` lists every action with its current shortcuts, and
`bashcut ui action <id|shortcut>` runs one.

| Key | Action | Status |
|---|---|---|
| Space | Play/pause (the source viewer when it is open) | Implemented |
| J K L | Reverse / stop / forward; press repeatedly to speed up | Planned |
| ← → (⇧) | Step 1 frame (1 s) | Planned (frame step exists as an action without a key) |
| I / O | Mark source in / out | Implemented |
| E / Q | Insert / overwrite from the source viewer | Implemented |
| Esc | Back to the timeline from the source viewer | Implemented |
| ⌥⌘F | Full-screen preview of the program picture (Esc or ⌥⌘F exits; J K L shuttle inside it) | Implemented |
| S, ⌘B | Split | Implemented |
| ⌫ / ⇧⌫ | Ripple delete / lift | Implemented |
| ⌘= / ⌘− | Zoom the timeline in / out around the playhead | Implemented |
| Pinch, ⌘ + scroll | Zoom the timeline around the pointer (scroll alone pans; ⇧ + wheel pans sideways) | Implemented |
| ⇧Z | Zoom the timeline to fit (timeline focused) | Implemented |
| ⌘Z / ⇧⌘Z | Undo / redo | Implemented |
| ⌘N / ⌘O / ⌘S | New / open / save project | Implemented |
| N | Snapping on/off | Planned |
| ⌘K | Ask the agent about the selection | Implemented |
| ⌘J | Show/hide the agent dock | Implemented |
| ⌘⇧A | Switch tab Claude ↔ Codex | Planned |
| ⌘E | Export | Implemented |
| ⌘⇧R | Review | Implemented |
| ⌘1…⌘8 | Asset panels (Media … Brand) | Implemented |
| ⌘T | Tools panel | Implemented |
| ⇧⌘F | All assets search: the whole library, project media and selects, grouped by kind (↩ uses, ↓ then Space previews, Search online opens Online resources); also All assets beside a panel's search field | Implemented |
