# BashCut specs

The design specs describe what BashCut is meant to be and why: product goals, UI, file format, architecture,
agent integration and the roadmap. For what is built today, see [implementation status](../status/implementation.md);
for how-to guides, see the [docs index](../README.md).

**BashCut** is a native macOS video editor with a CapCut-style layout and a docked Claude Code / Codex terminal.

- Everything can be done by hand in the UI.
- An agent can do the same things through MCP or the `bashcut` CLI.
- The app renders video itself, with one engine for preview and export.
- English is the default UI language, with Vietnamese included.

## Documents

| # | Spec | Covers |
|---|---|---|
| 00 | [Overview](00-overview.md) | Goals, non-goals, key decisions, principles |
| 01 | [UI/UX](01-ui-ux.md) | Windows, timeline, library tabs, agent dock, Review, Export, shortcuts |
| 02 | [Project format](02-project-format.md) | `project.bashcut.json`, project folder, `edl.json` import, Resolve-ready data rules |
| 03 | [Architecture](03-architecture.md) | Render engine, `EditOperation`, plugins, automation server, interchange |
| 04 | [Dependencies](04-dependencies.md) | Base-app packages, optional plugin dependencies, external tools |
| 05 | [Agent integration](05-agent-integration.md) | Claude/Codex terminals, commands that mirror the UI, context, permissions |
| 06 | [Features](06-features.md) | Feature list with priorities and matching agent commands |
| 07 | [Folder structure](07-folder-structure.md) | Folders, targets, plugin bundle layout |
| 08 | [Conventions](08-conventions.md) | Language, Swift style, project-model rules, tests, verification, git |
| 09 | [Roadmap](09-roadmap.md) | Milestones M0–M6, reserved Resolve work, risks, open questions |
| 10 | [Refactor plan](10-refactor-plan.md) | Audit findings and refactor rounds R0–R6 |

## Status markers

| Marker | Meaning |
|---|---|
| **Implemented** | Built and covered by tests; see [implementation status](../status/implementation.md) |
| **Planned** | Agreed design, not built yet |
| **Reserved** | Not planned for now; the data model keeps room for it |
| **(to verify)** | A CLI flag or library behavior not yet tested on a real machine; check before relying on it |

Feature priorities (**P0**, **P1**, **P2**) are defined in [06 — Features](06-features.md).

## Inputs and mockup

- `~/Desktop/nolan-video-workspace/`: the current editing workflow, the 13 `nolan-*` skills, the style playbook
  and measured lessons.
- An interactive UI mockup: [`mockups/bashcut-ui.html`](../../mockups/bashcut-ui.html) (local only; open it in a
  browser).

## Revision history

| Version | Date | Change |
|---|---|---|
| v0.1 | 2026-10-01 | BashCut as a "cockpit" over the existing Resolve pipeline |
| v0.2 | 2026-10-02 | A full editor with manual controls (new project, voice/cloning, captions…) and its own render engine |
| v0.3 | 2026-10-02 | Specs in English; English default UI; dependency recommendations; Resolve becomes an optional, reserved exporter with a Resolve-ready data model |
| v0.3.1 | 2026-10-02 | Fonts, Vision, AVAudioEngine and `contentLanguage`. Locked: AVFoundation engine, macOS 14, Codex on par from M2, separate `bash-cut/` repo |
| v0.3.2 | 2026-10-02 | The implemented `bashcut.plugin/1` process boundary, capability/provider resolution, plugin discovery, reviewed dependency installation |
| v0.3.3 | 2026-10-02 | Specs aligned with the refactor (R0–R6), proxies, M0 acceptance; docs reorganized into guides, reference, status and specs |
