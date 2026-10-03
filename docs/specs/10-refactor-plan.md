# 10 — Refactor plan

Written on 2026-10-02 after a structural audit of the whole repository (core package, document and UI layers,
engine, automation and agents). The goal was to make BashCut easy to scale, easy to contribute to and open to
many providers before the export queue, scrub performance work, bundled providers and more commands landed.

**Status: complete.** Rounds R0–R6 are done. The one-file recipes that came out of it are in
[CONTRIBUTING.md](../../CONTRIBUTING.md).

## Principles

1. **Every extension point is an interface.** Agent CLIs, automation commands, plugin capabilities
   and transports, interchange formats, media sources and export jobs are protocols with a registry. Adding a
   provider or a command means adding one file that conforms to a protocol, plus a test.
2. **The core contract stays closed.** `EditOperation` keeps one exhaustive `switch` so the compiler finds every
   place a new operation must be handled. Extensibility comes from a single codec and a single commit path, not
   from protocol-per-operation dispatch.
3. **One definition, many consumers.** A command, an operation or a target is declared once; CLI, MCP, agent
   instructions and the Xcode project are derived from it or checked against it by tests.
4. **One choke point per invariant.** Every edit goes through one `commit`; every plugin call goes through
   `CapabilityService`; every long-running job goes through one job center.
5. **Testable by default.** Integration code lives in library targets, not in the app executable.

## Audit findings

The state of the code at the time of the audit, before R0.

| Area | Finding | Evidence |
|---|---|---|
| Plugins | Cancelling a plugin call had no effect: the runner polled inside `Task.detached`, blocked a cooperative thread with `Thread.sleep` and killed only the direct child | `PluginProcessRunner.swift` `execute` |
| Automation | The socket accept loop handled one client at a time on a cooperative thread; one slow client stalled all agents | `UnixSocket.swift` accept loop |
| UI | Inspector sliders and text fields created one undo entry and one player rebuild per tick or keystroke | `InspectorView.swift` |
| Document | Nine code paths wrote history, each with its own conflict, busy and agent-diff handling | `ProjectDocument*.swift`, `AgentDockModel+API.swift` |
| Automation | One command was declared in five places (mode, instructions, handler, CLI, MCP schema); handlers had to be synchronous | `Wire.swift`, `BashCutCLI.swift`, `BashCutMCP.swift` |
| Agents | Agent CLIs and model APIs were closed enums with `if provider == .claude` branches; Codex inherited the whole app environment | `AgentLaunch.swift`, `AgentSessionStore.swift` |
| Model | Fixed track IDs (`a2`, `t1`, `v1`, `a3`, `a4`) in about 15 places despite dynamic schema-v2 tracks | `ProjectDocument+*.swift`, `LibraryView.swift` |
| Model | Unbounded full-snapshot undo, written to disk twice per save; the journal relied on synthesized `Codable` | `EditOperation.swift`, `ProjectStorage.swift` |
| Document | `ProjectDocument` had 56 stored properties and about nine responsibilities, inside the untestable app target | `ProjectDocument.swift` |
| Build | `Package.swift` and `project.yml` declared targets separately and had drifted; static core products embedded in several frameworks once left Xcode compiling against a stale `BashCutProject` module until DerivedData was cleared | `project.yml`, `Package.swift` |

## Rounds

Each round is one commit (or a short series) that passes `scripts/verify.sh test`, `lint`, the Xcode build and
`git diff --check` before the next round starts.

| Round | Scope | Size | Status |
|---|---|---|---|
| R0 | Live bugs: cancellable, non-blocking plugin runner that kills the whole process group; concurrent socket clients off the cooperative pool; coalesced Inspector edits | S | Done |
| R1 | Single `commit` choke point; `Project.track(role:)` helpers replacing fixed track IDs; capped history with explicit `before`; `"op"`-keyed `EditOperation` codec in core shared by the wire and the journal; hide `Deque` | M | Done (fixed-ID examples in agent instructions removed in R2) |
| R2 | `CommandSpec` registry: each command declared once (name, mode, parameters, sync or job); async handlers; CLI, MCP tools and agent instructions generated from specs; consistency test | M | Done |
| R3 | `AgentProvider` protocol (launch, MCP config, session discovery, environment allowlist) with a registry (the `ModelAdapter` registry went with the model-API tab, 2026-10-04); bookmarks keyed by provider ID | M | Done |
| R4a | `BashCutDocument` library: `JobCenter` shared by capability jobs and exports; `ExportRequest`, `ExportPipeline` and `ExportQueue`; E-1 background export queue built on them | M | Done |
| R4b | Split `ProjectDocument` into `EditorUIState`, `PreviewController`, `ExportController`, `FileSyncController`, `SettingsModel` and `AutomationController` behind an `AppServices` composition root, all in `BashCutDocument`; the document keeps history, `commit` and command handlers | L | Done (64 → 28 stored properties) |
| R5 | `CapabilityAdapter` and `PluginTransport` protocols (R5a); `MediaSource` (original or proxy) and a persistent asset cache for the engine (R5b); `TimelineExporter`/`TimelineImporter` protocols and `TimelineFormats` (R5c) | M–L | Done. Only the one-shot transport exists; a session transport waits for a plugin that needs it. Proxy generation (M-5) has since shipped on `MediaSource` |
| R6 | `Package.swift` as the single target source with `project.yml` linking its products; `verify.sh xcode`; tests split per module with `BashCutTestSupport`, `BashCutProjectFixtures` and apply→undo→redo round trips; `CONTRIBUTING.md` with one-file templates for agent providers, model adapters, commands, capabilities and timeline formats | M | Done |

## Lower priority

Done opportunistically, outside the rounds:

| Item | Status |
|---|---|
| Edit menu (Cut, Copy, Paste, Select All) | Done |
| Split `EditorView`, `LibraryView`, `InspectorView` and `TimelineView` | Open |
| Localize app-layer errors and history labels | Open |
| Replace exporter busy-polling with `requestMediaDataWhenReady` | Open |
| Typed schema layer (`TrackKind`, `TrackRole`, typed item fields with an `extra` bag) on top of the R1 helpers | Open (`TrackRole` exists) |

## Keep as is

- `JSONValue` with unknown-field preservation.
- Pure `applying` with revision checks.
- The snapshot-based `RenderEngine`, and one compositor for preview and export.
- `CommandRegistry` token, mode and audit checks.
- The one-shot plugin RPC contract with a filtered environment and confined outputs.
- `ProjectDiff`.
- The privileged approval flow.
- Session-ID guards on background work.
