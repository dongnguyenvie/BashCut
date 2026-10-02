# 06 — Feature list

Each feature has a priority:

- **P0**: the first usable build. You can cut a whole vlog by hand, with agent support.
- **P1**: right after P0. Brings the existing skills into the UI.
- **P2**: later.
- **Reserved**: not built, but the data model keeps room for it.

The "Agent" column names the matching command from `05-agent-integration.md`. "—" means manual
only, or no command needed.

## Project and media

| # | Feature | Priority | Agent |
|---|---|---|---|
| P-1 | Welcome: recent projects, open, new | P0 | `project open/create` |
| P-2 | New Project: name, frame 9:16/16:9, fps 29.97/30, content language, pick a shoot → symlink `footage/`, style preset | P0 | `project create` |
| P-3 | Atomic save, autosave, unlimited undo/redo, history with authors | P0 | — |
| P-4 | Reload on external file change, conflict handling | P0 | — |
| P-5 | Import from `edl.json` with a comparison report | P1 | `project create --from-edl` |
| M-1 | Media library: grid, list, thumbnails, hover-scrub, specs | P0 | `media list` |
| M-2 | Source viewer, I/O, insert (E) / overwrite (Q) | P0 | `timeline apply` (insert) |
| M-3 | Background survey: thumbnails, static-clip detection, contact sheet | P1 | — (skill `nolan-footage-survey`) |
| M-4 | Transcript through a replaceable `captions.transcribe` provider, speech badge, search by speech | P1 | `media search` |
| M-5 | Automatic proxies for heavy footage | P1 | — |
| M-6 | Transcode unsupported formats with ffmpeg on import | P2 | — |

## Timeline and editing

| # | Feature | Priority | Agent |
|---|---|---|---|
| T-1 | Tracks: magnetic Main, Overlay, Captions, Dialogue, Voiceover, Music, SFX | P0 | `timeline get` |
| T-2 | Split, ripple delete, trim, roll, slip, move, snapping | P0 | `timeline apply` |
| T-3 | Clip roles speech / b-roll / under VO, color coding; Sections band | P0 | `setProperties`, `setMarkers` |
| T-4 | Linked picture and sound; borrow picture (keep the old clip's sound) | P1 | `timeline apply` |
| T-5 | Beat detection through `audio.beats`, Beat band, beat snapping | P1 | `beats detect` |
| T-6 | Reframe (zoom/pan/tilt) by hand | P0 | `setProperties` |
| T-7 | Automatic "change framing" | P1 | `setProperties` |
| T-8 | Constant speed, freeze frame | P1 | `setProperties` |
| T-9 | Speed ramps (curve) | P2 | `setProperties` |
| T-10 | Simple keyframes for transform / volume | P2 | `setProperties` |
| T-11 | ◆ badge on agent changes, undo toast, Show Changes | P0 | — |
| T-12 | Face-aware placement (Vision): stickers/captions avoid faces; reframe keeps faces in frame | P2 | `setProperties` |

## Text and captions

| # | Feature | Priority | Agent |
|---|---|---|---|
| X-1 | Add text, inline edit, Inspector style (font, size, color, outline, shadow, position) | P0 | `timeline apply` |
| X-2 | Presets Bold Outline and Cinematic Serif | P0 | — |
| X-3 | Presets Keyword Sticker, Place Card, Hook Title, Chapter Card | P1 | — |
| X-4 | Auto Captions through a replaceable `captions.transcribe` provider | P1 | `captions generate` |
| X-5 | Long-line warning, TikTok safe area | P1 | `review run` |
| X-6 | Text animation: pop, word-by-word, typewriter, highlight, counter | P2 | `setProperties` |
| X-7 | `.srt` export | P1 | — |

## Audio and voice

| # | Feature | Priority | Agent |
|---|---|---|---|
| A-1 | Clip/track volume, fades, mute/solo | P0 | `setProperties` |
| A-2 | Waveforms | P0 | — |
| A-3 | Music/SFX library with BPM, loudness, license badges | P1 | `media list` |
| A-4 | Automatic music ducking under speech | P1 | `setProperties` |
| A-5 | −14 LUFS normalization through an `audio.loudness` provider | P1 | — |
| A-6 | Voice tab: choose a `voice.synthesize` provider, generate 3 takes, score them, insert into Voiceover | P1 | `voice speak` |
| A-7 | Clone New Voice wizard | P1 | `voice enroll` |
| A-8 | Warning when the voiceover overlaps real speech (< 0.3 s) | P1 | `review run` |
| A-9 | Voice/background separation (Demucs) | P2 | `audio separate` |
| A-10 | Record voiceover directly | P2 | — |

## Effects and color

| # | Feature | Priority | Agent |
|---|---|---|---|
| F-1 | Transitions: dissolve, whip, blink, zoom | P1 | `addTransition` |
| F-2 | Transitions: spin, shutter, wipe | P2 | `addTransition` |
| F-3 | Clip effects: zoom punch, shake, flash, glitch, film look | P2 | `setProperties` |
| F-4 | Overlays: banner, callout, place card, REC frame, progress bar, stickers | P2 | `timeline apply` |
| F-5 | Effect library by genre/moment from `recipes.json` | P2 | — (skill `nolan-effects`) |
| C-1 | `.cube` LUTs (`quinn-matte`, `quinn-am`, `quinn-ky-uc`, import) | P1 | `setProperties` |
| C-2 | Basic adjustments: exposure, contrast, saturation, temperature, tint | P1 | `setProperties` |
| C-3 | Before/after split in the viewer | P1 | — |

## Plugins and providers

| # | Feature | Priority | Agent |
|---|---|---|---|
| PL-1 | Discover validated `bashcut.plugin/1` bundles from project, user and bundled catalogs | P1 | — |
| PL-2 | Capability/provider resolution with undoable project preferences and healthy-priority fallback | P1 | `setProviderPreference` |
| PL-3 | Plugins UI: local-folder install, exact dependency-plan approval, health checks and diagnostics | P1 | — |
| PL-4 | Isolated one-request process RPC with time/output bounds, filtered environment and confined generated files | P1 | — |
| PL-5 | Store plugin/provider/version provenance while keeping generated media usable after uninstall | P1 | `project get` |
| PL-6 | Signed remote catalog and explicit credential/permission declarations | P2 | — |

## Agent

| # | Feature | Priority |
|---|---|---|
| G-1 | Dock: Claude / Codex / Shell terminal tabs, show/hide, detach | P0 |
| G-2 | Automation socket + `bashcut-mcp` + `bashcut` CLI (read, ui, edit) | P0 |
| G-3 | ⌘K popover and context chip | P0 |
| G-4 | Attach the current frame to ⌘K | P1 |
| G-5 | Quick actions (prompt templates) | P1 |
| G-6 | Per-project session resume, Claude ↔ Codex handoff | P1 |
| G-7 | Privileged commands with confirmation sheet, audit log | P1 |
| G-8 | Structured chat mode (headless) | P2 |

## Review, export, system

| # | Feature | Priority | Agent |
|---|---|---|---|
| R-1 | Review against the playbook, jump to issue, Ask Agent to Fix | P1 | `review run` |
| E-1 | Export H.264 1080×1920 / 1920×1080, background queue | P0 | `export start` |
| E-2 | Presets: TikTok, YouTube 1080p/4K, Quick Draft 720p, ProRes | P1 | `export start` |
| E-3 | Post-export numbers (duration, cuts, LUFS, speech coverage), compare with previous | P1 | `export status` |
| E-4 | OTIO export | P2 | `export otio` |
| E-5 | **Apply to DaVinci Resolve** through the workspace bridge | **Reserved** | `resolve plan` / `resolve apply` |
| D-1 | Doctor: workspace validity, `claude`, `codex`, optional tools, plugin catalog diagnostics and provider dependency health | P0 | — |
| D-2 | Fix hints per missing item; button to run `scripts/setup.sh` (with confirmation) | P0 (hints) / P1 (button) | — |
| S-1 | Settings: workspace, default agent, agent edit permission, export presets, language (English / Tiếng Việt) | P0 | — |

## Stays on the agent side (not in the UI)

These need the network, judgment or research. The agent does them through skills, and the
results show up in the app's library:

- `nolan-tiktok-music`, `nolan-sfx`: download music and SFX (copyright, so ask first).
- `nolan-stock-illus`: Pexels images and clips labeled as illustrations.
- `nolan-channel-study`: learn a channel's style and write it back into skills or presets.
- Script writing: `tools/llm/viet_loi.py`, content breakdown.
- `nolan-self-learn`: write lessons back into the skills.
