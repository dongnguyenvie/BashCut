# 00 — Overview

What BashCut is, why it exists, and the decisions and principles every other spec builds on. Read this first,
whether you are working on the app or deciding what it should do.

## In one sentence

**BashCut is a native macOS video editor in the style of CapCut desktop, with a docked Claude Code / Codex
terminal.** Anything you can do with a button, the agent can do through a command, and the reverse. BashCut renders
video with its own engine; DaVinci Resolve is optional.

## Where we are today (`nolan-video-workspace`)

Each video is built today from three ingredients.

**A hand-written Python pipeline per video:**

1. `edl.py` writes `edl.json`.
2. Pillow draws the subtitles.
3. A ProRes overlay is rendered.
4. numpy and ffmpeg produce four audio stems.
5. DaVinci Resolve 21.0.3 Free builds and renders the timeline through `resolve_bridge`.

**Thirteen `nolan-*` skills:** footage survey, beat cutting, audio mix, subtitles, voice cloning (VieNeu-TTS), SFX,
TikTok music, stock images, effects, LUT grading, channel study and self-learn.

**Measured lessons:**

- `memos/vlog-style-playbook.md`:
  - speech covers at least 90 % of the runtime;
  - the hook lasts 3–7 s;
  - no unintended silence longer than 0.8 s;
  - voiceover never overlaps real speech;
  - loudness is about −14 LUFS.
- A list of DaVinci Resolve Free traps.

**The problems with this setup:**

- Everything happens in a terminal and in code. Changing one cut means asking the agent to edit `edl.py`.
- There is no way to drag, trim or listen yourself.
- Most of the effort goes into working around Resolve Free. It cannot script clip volume, subtitle styling,
  transitions or keyframes, so everything is pre-rendered; on top of that come path-based media caching, Studio
  modals and wrong-project builds.

An app with its own engine removes those limits.

## Goals

1. **Edit a complete vlog in the app without a terminal.** Create the project, import footage, survey it, cut, add
   captions, record a voiceover in the cloned voice, add music and SFX, add effects, grade, review and export.
2. **Make the agent a co-pilot.**
   - It sees the same timeline and selection.
   - It edits through undoable operations that show up in the UI immediately.
   - It takes on heavy or repetitive work: writing narration, surveying footage, suggesting effects, reviewing the
     cut.
3. **Turn measured lessons into tools:** style presets (food review, cinematic "Quinn"), a Review panel based on the
   playbook, −14 LUFS normalization, and copyright warnings for music ripped from TikTok.
4. **Preview equals render.** One engine drives both, so what plays is what gets exported.
5. **Bring old projects in** by importing the `edl.json` of videos already cut.
6. **Keep a path to Resolve open.** Resolve is not used now, but the project data is organized so a later "Apply to
   Resolve" can rebuild the timeline there ([02 — Project format](02-project-format.md) §5).

How far each goal has got is tracked in [implementation status](../status/implementation.md).

## Non-goals

- **Not a professional NLE replacement.** No multicam, color nodes, Fusion-style compositing or keyframe graph
  editor.
- **No cloud, accounts or sync.**
- **No bundled ML models.** Optional plugins may wrap workspace Python venvs, native model runtimes or remote
  providers. Their models and libraries are installed only after the user picks that plugin and approves its
  dependency plan.
- **No downloads without asking.** Music, SFX and stock images are never fetched without confirmation, which keeps
  the skills' "ask first" rule.
- **Nothing under `tools/vendor/`.** The workspace's vendor folder is never read or modified.

## Key decisions

| Decision | Choice | Details |
|---|---|---|
| App type | Native macOS NLE, laid out like CapCut desktop | Nolan edits for TikTok, the reference videos were made in CapCut, and `nolan-effects` already triggers on "make it like CapCut" |
| UI language | **English by default**, Vietnamese localization included | [08 — Conventions](08-conventions.md) |
| UI stack | AppKit lifecycle + SwiftUI; timeline and viewer in AppKit/Metal | [03 — Architecture](03-architecture.md) |
| Render | **AVFoundation + Core Image/Metal** for both preview and export. ffmpeg is an optional helper, only for formats AVFoundation cannot read | [03 — Architecture](03-architecture.md) §2 |
| Data | `project.bashcut.json` inside the workspace's `projects/<video-name>/` | [02 — Project format](02-project-format.md) |
| Agent | Embedded terminal running `claude` or `codex` in the workspace. The app exposes the same commands through MCP and the `bashcut` CLI | [05 — Agent integration](05-agent-integration.md) |
| Dependencies | Apple frameworks first, plus a short list of MIT/Apache packages | [04 — Dependencies](04-dependencies.md) |
| Optional features | Versioned out-of-process plugins, selected by capability and provider. The project stays editable when a plugin is missing | [03 — Architecture](03-architecture.md) §5 |
| DaVinci Resolve | **Reserved.** The data model is designed so "Apply to Resolve" (through the workspace bridge) can be added later; OTIO export is already implemented | [02 — Project format](02-project-format.md) §5, [03 — Architecture](03-architecture.md) §7 |

## Principles

| Principle | Meaning |
|---|---|
| **One action, two callers** | Every UI action has a matching agent command (MCP/CLI), and every agent change shows up in the UI and can be undone |
| Manual first | Every feature works fully by hand. The agent makes you faster; it is never the only path |
| Non-destructive | Footage is read-only, reached through a symlink as today. All edits live in the project. Undo is meant to be unlimited within a session (the current build caps it at 200 steps), with autosave |
| Verify with numbers | After export, show duration, cut count, LUFS, speech coverage and silences, following the workspace's "verify with numbers" rule |
| Edits are data, not pixels | Effects, captions and transitions are stored as parameters, never baked in. This keeps undo, agent edits and future exporters (Resolve, OTIO) possible |
| Native | No web views. AVFoundation, Core Image, Metal, Core Text |
| Replaceable providers | Voice, captions and analysis store stable capability and provider IDs plus provenance, never vendor-specific timeline data |
