# 10 — Refactor plan (foundations before deeper features)

Written 2026-10-02 after a structural audit of the whole repository (core package, document/UI
layers, engine/automation/agent). Goal: before the export queue, scrub performance, bundled
providers and more commands land, make BashCut easy to scale and easy to contribute to, and let it
support many providers.

## Principles

1. **Every extension point is an interface.** Agent CLIs, model APIs, automation commands, plugin
   capabilities and transports, interchange formats, media sources and export jobs are protocols
   with a registry. Adding a provider or a command means adding one file that conforms to a
   protocol, plus a test.
2. **The core contract stays closed.** `EditOperation` keeps one exhaustive `switch` so the compiler
   finds every place a new operation must be handled. Extensibility comes from a single codec and a
   single commit path, not from protocol-per-operation dispatch.
3. **One definition, many consumers.** A command, an operation or a target is declared once; CLI,
   MCP, agent instructions and the Xcode project are derived from it or checked against it by tests.
4. **One choke point per invariant.** Every edit goes through one `commit`; every plugin call goes
   through `CapabilityService`; every long-running job goes through one job center.
5. **Testable by default.** Integration code lives in library targets, not in the app executable.

## Audit findings that drive the plan

| Area | Finding | Evidence |
|---|---|---|
| Plugins | Cancelling a plugin call has no effect: the runner polls inside `Task.detached`, blocks a cooperative thread with `Thread.sleep`, and kills only the direct child | `PluginProcessRunner.swift` `execute` |
| Automation | The socket accept loop handles one client at a time on a cooperative thread; one slow client stalls all agents | `UnixSocket.swift` accept loop |
| UI | Inspector sliders and text fields create one undo entry and one player rebuild per tick or keystroke | `InspectorView.swift` |
| Document | Nine code paths write history, each with its own conflict/busy/agent-diff handling | `ProjectDocument*.swift`, `AgentDockModel+API.swift` |
| Automation | One command is declared in five places (mode, instructions, handler, CLI, MCP schema); handlers must be synchronous | `Wire.swift`, `BashCutCLI.swift`, `BashCutMCP.swift` |
| Agents | Agent CLIs and model APIs are closed enums with `if provider == .claude` branches; Codex inherits the whole app environment | `AgentLaunch.swift`, `ModelClient.swift`, `AgentSessionStore.swift` |
| Model | Fixed track IDs (`a2`, `t1`, `v1`, `a3`, `a4`) in about 15 places despite dynamic schema-v2 tracks | `ProjectDocument+*.swift`, `LibraryView.swift` |
| Model | Unbounded full-snapshot undo, written to disk twice per save; journal relies on synthesized `Codable` | `EditOperation.swift`, `ProjectStorage.swift` |
| Document | `ProjectDocument` has 56 stored properties and about nine responsibilities, inside the untestable app target | `ProjectDocument.swift` |
| Build | `Package.swift` and `project.yml` declare targets separately and have drifted; static core products embedded in several frameworks once left Xcode compiling against a stale `BashCutProject` module until DerivedData was cleared | `project.yml`, `Package.swift` |

## Rounds

Each round is one commit (or a short series) that passes `scripts/verify.sh test`, `lint`, the
Xcode build and `git diff --check` before the next round starts.

| Round | Scope | Size | Status |
|---|---|---|---|
| **R0** | Live bugs: cancellable, non-blocking plugin runner that kills the whole process group; concurrent socket clients off the cooperative pool; coalesced Inspector edits | S | Done |
| **R1** | Single `commit` choke point; `Project.track(role:)` helpers replacing fixed track IDs; capped history with explicit `before`; `"op"`-keyed `EditOperation` codec in core shared by the wire and the journal; hide `Deque` | M | Done (fixed-ID examples in agent instructions removed in R2) |
| **R2** | `CommandSpec` registry: each command declared once (name, mode, parameters, sync or job); async handlers; CLI, MCP tools and agent instructions generated from specs; consistency test | M | Done |
| **R3** | `AgentProvider` protocol (launch, MCP config, session discovery, environment allowlist) and `ModelAdapter` protocol with registries; bookmarks keyed by provider ID | M | Done |
| **R4a** | `BashCutDocument` library: `JobCenter` shared by capability jobs and exports; `ExportRequest` + `ExportPipeline` + `ExportQueue`; E-1 background export queue | M | Done |
| **R4** | Split `ProjectDocument` into `PreviewController`, `ExportController`, `AutomationController`, `FileSyncController`, `EditorUIState` and `SettingsModel` behind an `AppServices` composition root; move them into a testable `BashCutDocument` library; `ExportRequest` + `ExportPipeline` + `ExportQueue` actor sharing one job center with capability jobs; then build E-1 on it | L | In progress (R4b: `EditorUIState`, `PreviewController`, `ExportController`, `FileSyncController`, `SettingsModel`, `AutomationController` done) |
| **R5** | `CapabilityAdapter` and `PluginTransport` (one-shot, session) protocols; `MediaSource` (original/proxy) and a persistent asset cache for the engine; `TimelineExporter`/`TimelineImporter` protocols | M–L | Planned |
| **R6** | `Package.swift` as the single target source (project.yml consumes products); Xcode build mode in `verify.sh`; tests split per module with shared fixtures and apply→undo→redo round trips; `CONTRIBUTING.md` with one-file templates for agent providers, model adapters, commands, capabilities and exporters | M | Planned |

Lower priority, done opportunistically: split `EditorView`, `LibraryView`, `InspectorView` and
`TimelineView`; localize app-layer errors and history labels; add an Edit menu; replace exporter
busy-polling with `requestMediaDataWhenReady`; typed schema layer (`TrackKind`, `TrackRole`, typed
item fields with an `extra` bag) once R1 helpers exist.

## Keep as is

`JSONValue` with unknown-field preservation; pure `applying` with revision checks; the
snapshot-based `RenderEngine`; one compositor for preview and export; `CommandRegistry` token, mode
and audit checks; the one-shot plugin RPC contract with filtered environment and confined outputs;
`ProjectDiff`; the privileged approval flow; session-ID guards on background work.
