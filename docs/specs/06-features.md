# 06 — Features

The full feature list, with each feature's priority, build status and matching agent command. Use it to plan work
and to check that every UI feature has an agent counterpart.

## Columns

**Priority:**

| Priority | Meaning |
|---|---|
| **P0** | The first usable build: a whole vlog can be cut by hand, with agent support |
| **P1** | Right after P0: brings the existing `nolan-*` skills into the UI |
| **P2** | Later |
| **Reserved** | Not planned for now; the data model keeps room for it |

**Status** uses the markers from the [specs index](README.md#status-markers): Implemented, Planned, Reserved. A
feature that is only partly built is marked Implemented, with the missing part named as Planned. Details and test
coverage are in [implementation status](../status/implementation.md).

**Agent** names the matching `bashcut` CLI command (the MCP tool has the same name; see
[05 — Agent integration](05-agent-integration.md) and the [automation guide](../guides/automation.md)). Edit
operations sent through `timeline apply` are named in parentheses, for example `timeline apply` (`setProperties`).
Any editor button can also be run with `ui action <id>`; the action ID is given where no dedicated command exists.
A command in *italics* is planned and does not exist yet. "—" means manual only, or no command is needed.

## Project and media

| # | Feature | Priority | Status | Agent |
|---|---|---|---|---|
| P-1 | Welcome: recent projects, open, new | P0 | Implemented | `project recents`, `project open`, `project create` |
| P-2 | New Project: name, frame Auto (the first clip sets 9:16, 16:9 or 1:1) or a fixed shape, fps 29.97/30, content language, pick a shoot → symlink `footage/`, default folder ~/Movies/BashCut | P0 | Implemented | `project create`, `project folder` |
| P-3 | Atomic save, autosave, undo/redo, history with authors | P0 | Implemented (undo capped at 200 steps) | `project save`, `timeline undo`, `timeline redo` |
| P-4 | Reload on external file change, conflict handling | P0 | Implemented | `ui dialog`, `ui respond` (answer the conflict sheet) |
| P-5 | Import from `edl.json` with a comparison report | P1 | Implemented | `edl import` |
| M-1 | Media library: grid, thumbnails, hover-scrub, specs; list view | P0 | Implemented (list view Planned) | `media list`, `media import` |
| M-2 | Source viewer, In/Out, insert (E) / overwrite (Q) | P0 | Implemented | `ui source`, `ui action source.insert` / `source.overwrite`, `media place` |
| M-3 | Background survey: thumbnails, static-clip detection, contact sheet | P1 | Partial: contact sheets, exact source frames and filmstrips for agents are Implemented (`media frames --sheet`, `media frame`, `media strip`); background thumbnails in the library are Planned | `media frames`, `media frame`, `media strip` |
| M-8 | Shot descriptions: the agent writes per-shot facts (size, angle, move, direction, subjects, best moment) in a closed vocabulary, saved with the project, with coverage of the measured shots | P1 | Implemented (no UI yet) | `media describe`, `media description` |
| M-4 | Transcript through a replaceable `captions.transcribe` provider, speech badge, search by speech | P1 | Partial: source transcripts are Implemented (`media transcribe`, `media transcript`, reused by Auto Captions); speech badge and search are Planned | `media transcribe`, `media transcript`, *`media search`* |
| M-5 | Automatic preview proxies for heavy footage | P1 | Implemented | `media proxy` |
| M-6 | Transcode unsupported formats with ffmpeg on import | P2 | Planned | — |
| M-7 | Still images (JPEG, PNG with transparency, HEIC…) as clips of any length | P1 | Implemented | `media import` (kind `image`), `media place` |

## Timeline and editing

| # | Feature | Priority | Status | Agent |
|---|---|---|---|---|
| T-1 | Tracks: magnetic Main, Overlay, Captions, Dialogue, Voiceover, Music, SFX; extra layers | P0 | Implemented | `timeline get`, `layers add` |
| T-1a | Adjustment layers: a color grade (look, exposure/contrast/saturation, LUT) on every layer below an item for its range | P0 | Implemented | `adjustment add`, `layers add --kind adjustment` |
| T-1b | Style kits (food review, cinematic): one undoable edit adds a full-length adjustment and restyles captions | P1 | Implemented | `style apply` |
| T-2 | Split, ripple delete, lift, trim, roll, slip, move, snapping | P0 | Implemented | `timeline apply` (`split`, `delete`, `trim`, `roll`, `slip`, `move`), `timeline move` |
| T-3 | Clip roles speech / b-roll / under VO, color coding; Sections band | P0 | Implemented | `timeline apply` (`setProperties`, `upsertSection`) |
| T-4 | Linked picture and sound; borrow picture (keep the old clip's sound) | P1 | Implemented (borrow-picture gesture Planned; imported from `edl.json`) | `timeline apply` (`setLinkedAudio`) |
| T-5 | Beat detection through `audio.beats`, Beat band, beat snapping | P1 | Implemented | `beats detect` |
| T-6 | Reframe (zoom/pan/tilt) by hand | P0 | Implemented | `timeline apply` (`setProperties`) |
| T-7 | Automatic "Change framing" | P1 | Implemented | `timeline apply` (`setProperties`) |
| T-8 | Constant speed, freeze frame | P1 | Implemented | `timeline apply` (`setProperties`) |
| T-9 | Speed ramps (curve) | P2 | Planned | *`timeline apply` (`setProperties`)* |
| T-10 | Keyframes for zoom, pan, tilt, rotation and opacity (clips, images, text) and volume (audio, clips with sound), presets such as Ken Burns | P2 | Implemented | `clip motion`, `clip keyframe` |
| T-11 | ◆ badge on agent changes, undo toast, Show Changes | P0 | Implemented | `ui action agent.show-changes` / `agent.undo-changes` |
| T-12 | Face-aware placement (Vision): stickers and captions avoid faces; reframe keeps faces in frame | P2 | Planned | *`timeline apply` (`setProperties`)* |

## Text and captions

| # | Feature | Priority | Status | Agent |
|---|---|---|---|---|
| X-1 | Add text, inline edit, Inspector style (font, size, color, outline, shadow, position) | P0 | Implemented | `timeline apply` (`insert`, `setProperties`) |
| X-2 | Presets Bold Outline and Cinematic Serif | P0 | Implemented | `timeline apply` (`setProperties`) |
| X-3 | Presets Keyword Sticker, Place Card, Hook Title, Chapter Card | P1 | Implemented | `timeline apply` (`setProperties`) |
| X-4 | Auto Captions through a replaceable `captions.transcribe` provider | P1 | Implemented | `captions generate` |
| X-5 | Long-line warning (over 42 characters), TikTok safe area | P1 | Implemented | `review run`, `ui view` |
| X-6 | Text animation: pop, word-by-word, typewriter, highlight, counter | P2 | Partly implemented (fade, pop, slide and zoom presets, keyframes, word-by-word highlight/karaoke/reveal; typewriter and counter Planned) | `clip motion`, `captions words`, `captions generate --word-style` |
| X-7 | `.srt` import and export | P1 | Implemented | `captions import`, `captions export` |

## Audio and voice

| # | Feature | Priority | Status | Agent |
|---|---|---|---|---|
| A-1 | Clip/track volume, fades, mute/solo | P0 | Implemented (solo Planned) | `timeline apply` (`setProperties`, `setTrackProperties`) |
| A-2 | Waveforms | P0 | Implemented | `ui action timeline.refresh-waveforms` |
| A-3 | Music/SFX library with BPM, loudness, license badges | P1 | Planned | `media list` |
| A-4 | Automatic music ducking under speech | P1 | Implemented | `timeline apply` (`setTrackProperties`) |
| A-5 | −14 LUFS normalization through an `audio.loudness` provider | P1 | Implemented | `export start --normalize-audio` |
| A-6 | Voice tab: choose a `voice.synthesize` provider, generate 3 takes, score them, insert into Voiceover | P1 | Implemented | `voice speak` |
| A-7 | Clone New Voice wizard | P1 | Planned | *`voice enroll`* |
| A-8 | Warning when voiceover comes within 0.3 s of real speech | P1 | Implemented | `review run` |
| A-9 | Voice/background separation (Demucs) | P2 | Planned | *`audio separate`* |
| A-10 | Record voiceover directly | P2 | Implemented (to verify on hardware) | — |

## Effects and color

| # | Feature | Priority | Status | Agent |
|---|---|---|---|---|
| F-1 | Transitions: dissolve, whip, blink, zoom | P1 | Implemented | `timeline apply` (`upsertTransition`) |
| F-2 | Transitions: spin, shutter, wipe | P2 | Implemented | `timeline apply` (`upsertTransition`) |
| F-3 | Clip effects: zoom punch, shake, flash, glitch, film look | P2 | Planned | *`timeline apply` (`setProperties`)* |
| F-4 | Overlays: banner, callout, place card, REC frame, progress bar, stickers | P2 | Implemented (emoji stickers only; the rest Planned) | `timeline apply` (`insert`) |
| F-5 | Effect library by genre and moment from `recipes.json` | P2 | Planned | — (skill `nolan-effects`) |
| C-1 | `.cube` LUTs: import, apply, strength; bundled `quinn-matte`, `quinn-am`, `quinn-ky-uc` | P1 | Implemented (bundled looks Planned) | `luts import`, `timeline apply` (`setProperties`) |
| C-2 | Basic adjustments: exposure, contrast, saturation, temperature, tint | P1 | Implemented (temperature, tint Planned) | `timeline apply` (`setProperties`) |
| C-3 | Before/after split in the viewer | P1 | Implemented | `ui action view.compare` |

## Plugins and providers

| # | Feature | Priority | Status | Agent |
|---|---|---|---|---|
| PL-1 | Discover validated `bashcut.plugin/1` bundles from project, user and bundled catalogs | P1 | Implemented | `plugins list` |
| PL-2 | Capability/provider resolution with undoable project preferences and healthy-priority fallback | P1 | Implemented | `timeline apply` (`setProviderPreference`) |
| PL-3 | Plugins UI: local-folder install, exact dependency-plan approval, health checks, diagnostics | P1 | Implemented | `plugins health` (install is UI only) |
| PL-4 | Isolated one-request process RPC with time and output bounds, filtered environment, confined generated files | P1 | Implemented | — |
| PL-5 | Plugin, provider and version provenance; generated media stays usable after uninstall | P1 | Implemented | `project get` |
| PL-6 | Signed remote catalog; explicit credential and permission declarations | P2 | Planned | — |

## Agent

| # | Feature | Priority | Status | Agent |
|---|---|---|---|---|
| G-1 | Dock: Claude / Codex / Shell terminal tabs, show/hide, detach | P0 | Implemented | `ui action agent.toggle-dock` |
| G-2 | Automation socket, `bashcut-mcp` and `bashcut` CLI (read, UI, edit, privileged) | P0 | Implemented (48 commands) | `bashcut help` lists them |
| G-3 | ⌘K popover and context chip | P0 | Implemented | `ui action agent.ask`, `context get` |
| G-4 | Attach the current frame to ⌘K | P1 | Implemented | — |
| G-5 | Quick actions (prompt templates) | P1 | Implemented (Survey, Write VO, Review; Suggest FX, Lessons Planned) | — |
| G-6 | Per-project session resume, Claude ↔ Codex handoff | P1 | Implemented | — |
| G-7 | Privileged commands with a confirmation sheet; audit log | P1 | Implemented | `export start`, `export otio` |
| G-8 | Structured chat mode (headless) | P2 | Planned | — |

## Review, export and system

| # | Feature | Priority | Status | Agent |
|---|---|---|---|---|
| R-1 | Review against the playbook, jump to issue, Ask Agent to Fix | P1 | Implemented (structural checks only; measured checks Planned, see [01](01-ui-ux.md) §5) | `review run` |
| E-1 | Export H.264 1080×1920 / 1920×1080, background queue | P0 | Implemented | `export start`, `jobs status`, `jobs cancel` |
| E-2 | Presets: TikTok, YouTube 1080p/4K, Quick Draft 720p, ProRes | P1 | Implemented | `export start --preset` |
| E-3 | Post-export numbers (duration, cuts, LUFS, speech coverage), compare with previous | P1 | Implemented | `export status` |
| E-4 | OTIO export | P2 | Implemented | `export otio` |
| E-5 | **Apply to DaVinci Resolve** through the workspace bridge | Reserved | Reserved | *`resolve plan`*, *`resolve apply`* |
| D-1 | Doctor: workspace, `claude`, `codex`, optional tools, plugin catalog diagnostics, provider dependency health | P0 | Implemented | `doctor run` |
| D-2 | Fix hints per missing item; button to run the workspace's `scripts/setup.sh` (with confirmation) | P0 (hints) / P1 (button) | Implemented (hints; button Planned) | — |
| S-1 | Settings: workspace, default agent, agent edit permission, export presets, language (English / Tiếng Việt) | P0 | Implemented | `ui open settings` |

## Stays with the agent (not in the UI)

These need the network, judgment or research. The agent does them through skills, and the results appear in the
app's library.

| Skill or tool | Job |
|---|---|
| `nolan-tiktok-music`, `nolan-sfx` | Download music and SFX (copyright, so ask first) |
| `nolan-stock-illus` | Pexels images and clips, labeled as illustrations |
| `nolan-channel-study` | Learn a channel's style and write it back into skills or presets |
| `tools/llm/viet_loi.py`, content breakdown | Script writing |
| `nolan-self-learn` | Write lessons back into the skills |
