# 07 — Folder structure

This is the `bash-cut/` repository as it stands at HEAD. `Package.swift` declares every target; `project.yml`
(XcodeGen) only wraps the app bundle around them. Items marked *(planned)* do not exist yet. Do not create empty
folders to match a plan; add a folder when the first file needs it.

## Repository tree

```text
bash-cut/
├── AGENTS.md                      # instructions for agents developing the app
├── CLAUDE.md                      # @AGENTS.md
├── CONTRIBUTING.md                # build layout and one-file extension templates
├── README.md
├── CHANGELOG.md                   # [Unreleased] section, one line per meaningful change
├── Package.swift                  # single source of targets (app, CLI, MCP, libraries, tests, bench)
├── Package.resolved               # committed lockfile
├── project.yml                    # XcodeGen; BashCut.xcodeproj is generated and not committed
├── .swiftlint.yml  .swift-format  .editorconfig  .gitignore
│
├── .claude/
│   ├── rules/                     # path-scoped rules (`paths:` frontmatter)
│   │   ├── engine.md              #   BashCut/Core/Engine/**
│   │   ├── project-model.md       #   Packages/BashCutCore/Sources/BashCutProject/**
│   │   └── dependencies.md        #   Package.swift, project.yml
│   └── skills/
│       └── verify/SKILL.md        # how to run scripts/verify.sh
├── .agents/skills -> ../.claude/skills
│
├── Configs/
│   ├── Base.xcconfig  Debug.xcconfig  Release.xcconfig
│   └── Version.xcconfig           # MARKETING_VERSION, CURRENT_PROJECT_VERSION
│                                  # Secrets.xcconfig is optional and gitignored
│
├── BashCut/                       # app executable (product BashCutApp)
│   ├── main.swift  AppDelegate.swift  Info.plist  BashCut.entitlements
│   ├── Core/
│   │   ├── Engine/                # library BashCutEngine: CompositionBuilder, BashCutCompositor,
│   │   │                          # RenderEngine, Exporter, ExportPreset, TextRenderer, TimeMapping,
│   │   │                          # MediaSource, ProxyManager, AudioWaveform, AudioGainPlanner, CubeLUT
│   │   ├── Storage/               # library BashCutStorage: ProjectStorage, ProjectCreation,
│   │   │                          # ProjectFileMonitor, ExportHistoryStore
│   │   ├── Automation/            # library BashCutAutomation: CommandSpec, CommandCatalog,
│   │   │                          # CommandRegistry, CommandLineParser, UIAction, UnixSocket, Wire,
│   │   │                          # AgentInstructions, MCPBridgeClient, DebugLog
│   │   ├── Agent/                 # library BashCutAgent: AgentProvider (Claude, Codex, Shell),
│   │   │                          # ModelAdapter (Responses, Chat Completions, Anthropic), AgentLaunch,
│   │   │                          # AgentEnvironment, AgentSessionStore, ModelClient, CredentialStore
│   │   ├── Plugins/               # library BashCutPlugins: CapabilityService, CapabilityAdapter,
│   │   │   └── Capabilities/      # one adapter per capability (transcription, beats, loudness, voice)
│   │   ├── Services/              # library BashCutDocument: AppServices, JobCenter, ExportQueue,
│   │   │                          # ExportPipeline, ProxyQueue, PreviewController, ExportController,
│   │   │                          # FileSyncController, AutomationController, SettingsModel,
│   │   │                          # EditorUIState, ModalCenter, TimelineFormats
│   │   └── Document/              # app target: ProjectDocument, history, `commit`, command handlers
│   │                              # (ProjectDocument+<Area>.swift)
│   ├── Models/                    # small app-only value types
│   ├── ViewModels/                # @Observable models: agent dock, knowledge, Doctor, plugins, voice…
│   ├── Views/                     # SwiftUI/AppKit views, one file per screen or panel
│   └── Resources/
│       ├── Localizable.xcstrings  # English (development language) + Vietnamese
│       └── en.lproj/  vi.lproj/   # InfoPlist.strings, Localizable.strings
│
├── CLI/BashCutCLI.swift           # executable `bashcut` (swift-argument-parser)
├── MCPBridge/BashCutMCP.swift     # executable `bashcut-mcp` (MCP Swift SDK, stdio)
├── Tools/Bench/main.swift         # executable `bashcut-bench`: engine benchmark on real footage
│
├── Packages/
│   └── BashCutCore/               # pure-logic package; `swift test` runs without Xcode
│       ├── Package.swift  Package.resolved
│       ├── Sources/
│       │   ├── BashCutProject/    # Project, tracks/items, EditOperation + codec, history, validation,
│       │   │                      # layer rules, diff, review rules, SubRip, timeline-format protocols
│       │   ├── BashCutPlugin/     # bashcut.plugin/1 manifest, catalog, provider resolver, transport,
│       │   │                      # process runner
│       │   ├── BashCutImport/     # legacy edl.json importer
│       │   └── BashCutInterchange/  # OpenTimelineIO exporter
│       └── Tests/
│           ├── BashCutProjectTests/  BashCutPluginTests/
│           ├── BashCutImportTests/   BashCutInterchangeTests/
│           └── BashCutProjectFixtures/  # shared projects and the apply→undo→redo helper
│
├── Tests/                         # one test target per app library
│   ├── BashCutEngineTests/        # includes __Snapshots__/ golden frames
│   ├── BashCutStorageTests/  BashCutAutomationTests/  BashCutAgentTests/
│   ├── BashCutPluginsTests/  BashCutDocumentTests/
│   └── BashCutTestSupport/        # shared fixtures: generated media, scratch folders, synthetic audio
│
├── Fixtures/
│   ├── make-media.sh              # generates media/test.mp4 with ffmpeg
│   └── media/                     # generated, gitignored
│
├── scripts/
│   ├── generate-project.sh        # checks for XcodeGen, generates BashCut.xcodeproj
│   ├── verify.sh                  # build | test | lint | xcode [build|test] | perf
│   └── run.sh                     # builds, signs and opens build/BashCut.app
│
├── mockups/bashcut-ui.html        # interactive UI mockup (reference only)
│
└── docs/
    ├── README.md                  # documentation index
    ├── guides/                    # automation.md (CLI/MCP commands), plugins.md (plugin API)
    ├── reference/                 # project-format.md (schema), third-party.md (dependencies, licenses)
    ├── status/                    # implementation.md, mockup-parity.md
    └── specs/                     # these documents, 00–10
```

Generated and ignored: `.build/`, `build/` (app bundle, `build/logs/`, Xcode derived data), `.swiftpm/`,
`BashCut.xcodeproj/`, `Fixtures/media/`.

### Planned

These appear in earlier drafts of this spec and are not in the repository yet:

- More path-scoped rules in `.claude/rules/` (automation security, process tools, UI lifecycle, tests) and a
  `release` skill.
- `Fixtures/workspace-mini/` (fake workspace with trimmed real `edl.json`) and `Fixtures/projects/` (sample and
  broken project files).
- A UI test target and a dedicated performance test target. Today `scripts/verify.sh perf` runs the engine tests
  with `BASHCUT_PERF=1`, and real-footage numbers come from `bashcut-bench`.
- `scripts/install-cli.sh` (a `bashcut` shim on `PATH`), `build-release.sh` and `create-dmg.sh`.
- Finer folders inside `Core/Engine` and `Views/` once those areas grow.

## Targets

`Package.swift` is the single source of targets. `project.yml` declares only what Xcode must own and links the
package's library products. `scripts/verify.sh xcode [build|test]` regenerates the project and builds or tests it.

| Target | Kind | Path | Notes |
|---|---|---|---|
| `BashCut` | executable (product `BashCutApp`) | `BashCut/` | The app; excludes `Core/*` library folders. SwiftTerm is linked here only |
| `BashCutEngine` | library | `BashCut/Core/Engine` | AVFoundation compositor, export, proxies, waveforms |
| `BashCutStorage` | library | `BashCut/Core/Storage` | Project files, creation, monitoring, export history |
| `BashCutAutomation` | library | `BashCut/Core/Automation` | Command specs, registry, socket, wire format, UI actions |
| `BashCutAgent` | library | `BashCut/Core/Agent` | Agent providers, model adapters, sessions, credentials |
| `BashCutPlugins` | library | `BashCut/Core/Plugins` | Capability service and adapters |
| `BashCutDocument` | library | `BashCut/Core/Services` | Controllers, job center, export and proxy queues |
| `BashCutCLI` | executable (`bashcut`) | `CLI/` | Embedded in the app bundle |
| `BashCutMCP` | executable (`bashcut-mcp`) | `MCPBridge/` | Embedded in the app bundle |
| `bashcut-bench` | executable | `Tools/Bench` | Not part of the app |
| `BashCutTestSupport` | library | `Tests/BashCutTestSupport` | Test-only fixtures |
| `BashCut<Module>Tests` | test | `Tests/` | One per app library |
| `BashCutProject`, `BashCutPlugin`, `BashCutImport`, `BashCutInterchange` | library | `Packages/BashCutCore/Sources` | Core package products |
| `BashCutProjectFixtures` | library | `Packages/BashCutCore/Tests` | Test-only fixtures |
| `BashCut<Module>Tests` (core) | test | `Packages/BashCutCore/Tests` | One per core module |

In `project.yml`:

| Xcode target | Type | Notes |
|---|---|---|
| `BashCut` | application | macOS 14.0+, bundle ID `app.bashcut`; embeds `bashcut` and `bashcut-mcp` in `Contents/MacOS` |
| `BashCutCLI` | tool | Product name `bashcut` |
| `BashCutMCP` | tool | Product name `bashcut-mcp` |
| `BashCutTests` | unit-test bundle | Compiles every `Tests/*Tests` folder into one bundle; SwiftPM runs them as per-module targets |

## Plugin bundle and catalog layout

Plugins are discovered in three roots, highest priority first:

```text
<project>/.bashcut/plugins/<plugin-id>/            # project override
~/Library/Application Support/BashCut/Plugins/<plugin-id>/
BashCut.app/Contents/PlugIns/<plugin-id>/          # optional bundled providers
    ├── plugin.json                                # bashcut.plugin/1 manifest
    └── <entrypoint>                               # executable named by the manifest; called with `rpc`
```

Request outputs live in project-scoped, provider-specific request folders and are validated before they become
project media. Plugin and provider IDs are stable; model files, virtual environments and downloaded dependencies
belong to the plugin, never to the timeline schema. See [plugins.md](../guides/plugins.md).
