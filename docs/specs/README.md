# BashCut — specs (proposal v0.3)

**BashCut** is a native macOS video editor with a CapCut-style layout and a docked Claude Code /
Codex terminal.

- Everything can be done by hand in the UI.
- The agent can do the same things through MCP or the `bashcut` CLI.
- The app renders video itself.
- English is the default UI language, with Vietnamese included.

## Revision history

| Version | Date | Change |
|---|---|---|
| v0.1 | 2026-10-01 | BashCut as a "cockpit" over the existing Resolve pipeline |
| v0.2 | 2026-10-02 | Changed to a full editor with manual controls (new project, voice/cloning, captions…) and its own render engine |
| v0.3 | 2026-10-02 | Specs rewritten in English; English becomes the default UI language; dependency recommendations added; DaVinci Resolve becomes an optional, reserved exporter, with the data model designed for a later "Apply to Resolve" |
| v0.3.1 | 2026-10-02 | Added fonts, Vision, AVAudioEngine and `contentLanguage`. Decisions locked: AVFoundation engine, macOS 14, Codex on par from M2, separate `bash-cut/` repo (`09-roadmap.md`) |

## Inputs

- `~/Desktop/nolan-video-workspace/`: today's editing workflow, the 13 `nolan-*` skills, the
  style playbook and the measured lessons.

## Documents

| File | Contents |
|---|---|
| [00-overview.md](00-overview.md) | Goals, non-goals, key decisions, principles |
| [01-ui-ux.md](01-ui-ux.md) | Layout, timeline, library tabs, Voice tab, agent dock, Review, Export, shortcuts |
| [02-project-format.md](02-project-format.md) | `project.bashcut.json`, project folder, `edl.json` import, Resolve-ready data rules, workspace changes |
| [03-architecture.md](03-architecture.md) | Engine (why AVFoundation, not ffmpeg), `EditOperation`, tools, automation socket, exporters (incl. future Resolve) |
| [04-dependencies.md](04-dependencies.md) | Dependency policy; Apple frameworks; packages to adopt / defer / reject; external tools |
| [05-agent-integration.md](05-agent-integration.md) | Claude/Codex terminals, commands that mirror the UI, context, permissions |
| [06-features.md](06-features.md) | Feature list with P0/P1/P2/Reserved and matching agent commands |
| [07-folder-structure.md](07-folder-structure.md) | `bash-cut/` repository layout |
| [08-conventions.md](08-conventions.md) | Language, Swift style, project-model rules, tests, verify, git |
| [09-roadmap.md](09-roadmap.md) | M0 → M6, reserved Resolve work, risks, open questions |

## Mockup

An interactive UI mockup lives at [`../../mockups/bashcut-ui.html`](../../mockups/bashcut-ui.html).
It is local only; open it in a browser.

## Status markers

Items marked **(to verify)** have not been tested on the machine yet. They are mostly CLI flags
and library behavior, and must be checked before coding.
