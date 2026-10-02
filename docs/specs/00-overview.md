# 00 — Overview

## In one sentence

**BashCut is a native macOS video editor in the style of CapCut desktop, with a docked
Claude Code / Codex terminal.** Anything you can do with a button, the agent can do through a
command, and the reverse is also true. BashCut renders video with its own engine; DaVinci
Resolve is optional.

## Where we are today (`nolan-video-workspace`)

Each video is currently built from three ingredients.

**1. A hand-written Python pipeline for each video:**

1. `edl.py` writes `edl.json`.
2. Pillow draws the subtitles.
3. A ProRes overlay is rendered.
4. numpy/ffmpeg produce four audio stems.
5. DaVinci Resolve 21.0.3 Free builds and renders the timeline through `resolve_bridge`.

**2. Thirteen `nolan-*` skills:** footage survey, beat cutting, audio mix, subtitles, voice
cloning (VieNeu-TTS), SFX, TikTok music, stock images, effects, LUT grading, channel study, and
self-learn.

**3. Lessons that have been measured:**
- `memos/vlog-style-playbook.md`:
  - speech covers at least 90 % of the runtime;
  - the hook lasts 3–7 s;
  - no unintended silence longer than 0.8 s;
  - voiceover never overlaps real speech;
  - loudness is about −14 LUFS.
- A list of DaVinci Resolve Free traps.

**The problems with this setup:**
- Everything happens in a terminal and in code. Changing one cut means asking the agent to edit
  `edl.py`.
- There is no way to drag, trim or listen yourself.
- Most of the effort goes into working around Resolve Free:
  - No scripted clip volume, subtitle styling, transitions or keyframes, so everything is
    pre-rendered.
  - On top of that come path-based media caching, Studio modals and wrong-project builds.

An app with its own engine removes those limits.

## Goals

1. **Edit a complete vlog in the app without a terminal.** The full flow is:
   1. Create the project.
   2. Import footage.
   3. Survey it.
   4. Cut.
   5. Add captions.
   6. Record a voiceover in the cloned voice.
   7. Add music and SFX.
   8. Add effects.
   9. Grade.
   10. Review.
   11. Export.
2. **Make the agent a co-pilot.**
   - It sees the same timeline and selection.
   - It edits through undoable operations that show up in the UI immediately.
   - It takes on the heavy or repetitive work: writing narration, surveying footage, suggesting
     effects, reviewing the cut.
3. **Turn measured lessons into tools.** This means:
   - style presets (food review, cinematic "Quinn");
   - a Review panel based on the playbook;
   - −14 LUFS normalization;
   - copyright warnings for music ripped from TikTok.
4. **Preview equals render.** One engine is used for both, so what plays is what gets exported.
5. **Bring old projects in** by importing the `edl.json` of videos already cut.
6. **Keep a path to Resolve open.** Resolve is not used now, but the project data is organized so
   a later "Apply to Resolve" can rebuild the timeline there (see `02-project-format.md` §5).

## Non-goals

- **Not a professional NLE replacement.** No multicam, no color nodes, no Fusion-style
  compositing, no complex keyframe graph editor.
- **No cloud, accounts or sync.**
- **No ML models bundled.** Optional plugins may wrap workspace Python venvs, native model
  runtimes or remote providers. Their models and libraries are installed only after the user
  chooses that plugin and approves its dependency plan.
- **No downloads without asking.** Music, SFX and stock images are never fetched without
  confirmation, which keeps the skills' "ask first" rule.
- **Nothing under `tools/vendor/`.** The workspace's vendor folder is never read or modified.

## Key decisions

| Decision | Choice | Details |
|---|---|---|
| App type | Native macOS NLE, laid out like CapCut desktop | Nolan edits for TikTok; the reference videos were made in CapCut; `nolan-effects` already triggers on "make it like CapCut" |
| UI language | **English by default**, Vietnamese localization included | `08-conventions.md` |
| UI stack | AppKit lifecycle + SwiftUI; timeline and viewer in AppKit/Metal | `03-architecture.md` |
| Render | **AVFoundation + Core Image/Metal** for both preview and export. ffmpeg is an optional helper, only for formats AVFoundation can't read | `03-architecture.md` §2 |
| Data | `project.bashcut.json` inside the workspace's `projects/<video-name>/` | `02-project-format.md` |
| Agent | Embedded terminal running `claude` / `codex` in the workspace. The app exposes the same commands through MCP and a `bashcut` CLI | `05-agent-integration.md` |
| Dependencies | Apple frameworks first, plus a short list of MIT/Apache packages | `04-dependencies.md` |
| Optional features | Versioned out-of-process plugins selected by capability/provider; the project remains editable when a plugin is missing | `03-architecture.md` §5 |
| DaVinci Resolve | **Not needed now.** The data model is designed so "Apply to Resolve" (through the workspace bridge) and OTIO export can be added later | `02-project-format.md` §5, `03-architecture.md` §7 |

## Principles

| Principle | Meaning |
|---|---|
| **One action, two callers** | Every UI action has a matching agent command (MCP/CLI). Every agent change shows up in the UI and can be undone. |
| Manual first | Every feature fully works by hand. The agent makes you faster; it is never the only path. |
| Non-destructive | Footage is read-only, reached through a symlink as today. All edits live in the project. Undo is unlimited within a session, with autosave. |
| Verify with numbers | After export, show duration, cut count, LUFS, speech coverage and silences. This follows the workspace's "verify with numbers" rule. |
| Edits are data, not pixels | Effects, captions and transitions are stored as parameters, never baked. This keeps undo, agent edits and future exporters (Resolve, OTIO) possible. |
| Native | No web views. AVFoundation, Core Image, Metal, Core Text. |
| Replaceable providers | Voice, captions and analysis store stable capability/provider IDs and provenance instead of vendor-specific timeline data. |
