# 07 — Repository layout (`bash-cut/`)

The layout uses:

- XcodeGen;
- a `Core/Models/ViewModels/Views` split;
- a pure-logic package;
- tests that mirror the app;
- agent docs at the root.

BashCut adds `Engine/`, `Tools/` and `Interchange`, and drops the parts that only exist for
database drivers.

The tree below is the **target** layout. The current code is flatter: `BashCut/Core/` contains
`Agent/`, `Automation/`, `Document/`, `Engine/`, `Plugins/` and `Storage/`. `Core/Plugins`
(`CapabilityService`, catalog roots and validated result types) is implemented; the plugin install
flow and UI state remain in `BashCut/ViewModels/PluginManagerModel.swift`. Split files into the
target folders as each area grows. Do not create empty folders just to match this tree.

```
bash-cut/
├── AGENTS.md                         # instructions for Claude + Codex when DEVELOPING the app
├── CLAUDE.md                         # @AGENTS.md
├── README.md
├── CHANGELOG.md                      # Keep a Changelog, [Unreleased]
├── project.yml                       # XcodeGen; BashCut.xcodeproj is generated, not committed
├── .swiftlint.yml  .editorconfig  .gitignore
│
├── .claude/
│   ├── rules/                        # path-scoped rules (`paths:` frontmatter)
│   │   ├── engine.md                 #   Core/Engine/** — compositor never touches @MainActor; perf budgets
│   │   ├── project-model.md          #   Packages/BashCutCore/Sources/BashCutProject/** — schema, migration, stable IDs, Resolve-ready rules
│   │   ├── automation-security.md    #   Core/Automation/**, Core/Agent/** — socket perms, tokens, modes, audit
│   │   ├── process-tools.md          #   Core/Tools/**, Core/Process/** — PATH, cancellation, never install globally
│   │   ├── dependencies.md           #   project.yml, Package.swift — policy from docs/specs/04-dependencies.md
│   │   ├── ui-lifecycle.md           #   Views/**, ViewModels/**
│   │   └── tests.md
│   └── skills/
│       ├── verify/                   # verify.sh build|test|lint|uitest|perf — full log on disk, short PASS/FAIL
│       └── release/                  # (later)
├── .agents/skills -> ../.claude/skills
│
├── Configs/
│   ├── Base.xcconfig  Debug.xcconfig  Release.xcconfig
│   ├── Version.xcconfig              # MARKETING_VERSION, CURRENT_PROJECT_VERSION
│   └── Secrets.xcconfig              # gitignored: team, per-machine bundle id
│
├── BashCut/                          # app target
│   ├── main.swift  AppDelegate.swift  Info.plist  BashCut.entitlements
│   ├── Core/
│   │   ├── Document/                 # ProjectDocument (@MainActor), undo bridge, Autosave, FileWatcher
│   │   ├── Engine/
│   │   │   ├── Composition/          # CompositionBuilder, TimeMapping (frame ↔ CMTime)
│   │   │   ├── Compositor/           # BashCutCompositor (AVVideoCompositing), FrameGraph
│   │   │   ├── Shaders/              # *.metal: transitions, LUT, blur, film
│   │   │   ├── Text/                 # TextRenderer (Core Text), TextAnimation
│   │   │   ├── Audio/                # AudioGraph, Ducking
│   │   │   ├── Export/               # RenderEngine, Exporter (actor), ExportPreset, ExportQueue
│   │   │   └── Proxy/                # ProxyManager
│   │   ├── Interchange/              # TimelineExporter impls: SRTExporter, OTIOExporter (P2),
│   │   │                             # ResolveExporter (reserved: plan → render artifacts → bridge_run.py)
│   │   ├── Media/                    # MediaLibrary, Probe (AVAsset → ffprobe fallback),
│   │   │                             # ThumbnailService, WaveformService, FrameGrabber, StaticClipDetector
│   │   ├── Plugins/                  # catalog roots, provider resolver, install approval, feature adapters
│   │   ├── Tools/                    # native helpers only; optional engines stay behind Plugins/
│   │   ├── Agent/
│   │   │   ├── CLI/                  # AgentCLIDiscovery, CLIEnvironment (PATH)
│   │   │   ├── Terminal/             # PTYSession (SwiftTerm), ContextPaster, QuickActions
│   │   │   ├── Session/              # AgentSessionStore, Handoff
│   │   │   └── Providers/            # ClaudeLaunch, CodexLaunch (all CLI flags live here)
│   │   ├── Automation/
│   │   │   ├── Server/               # AutomationServer (actor, Unix socket), TokenStore
│   │   │   ├── Commands/             # CommandRegistry, Context/Timeline/Media/Voice/Export/UI commands
│   │   │   └── Approval/             # ApprovalCenter, AuditLog
│   │   ├── Review/                   # ReviewService (BashCutReview rules + audio measurements)
│   │   ├── Workspace/                # WorkspaceLocator, AssetsCatalog (music/SFX/voices/LUTs)
│   │   ├── Doctor/                   # DoctorService + one check per tool
│   │   ├── Process/                  # SupervisedProcessRunner, PipeReader, StaleProcessReaper
│   │   ├── Storage/                  # AppSupportPaths, SettingsStore, RecentProjects
│   │   ├── Services/AppServices.swift
│   │   └── Diagnostics/              # Logger categories, signposts
│   ├── Models/                       # Selection, Playhead, PanelState, LibraryTab, ExportJob…
│   ├── ViewModels/
│   │   ├── EditorViewModel.swift     # (+Selection, +Playback, +Commands)
│   │   ├── TimelineViewModel.swift   # (+Editing, +Snapping, +Zoom)
│   │   ├── LibraryViewModel.swift  InspectorViewModel.swift  VoiceViewModel.swift
│   │   ├── AgentDockViewModel.swift  ReviewViewModel.swift  ExportViewModel.swift
│   │   └── WelcomeViewModel.swift  DoctorViewModel.swift
│   ├── Views/
│   │   ├── Welcome/
│   │   ├── Editor/                   # EditorWindowController, EditorSplitViewController, Toolbar
│   │   ├── Library/                  # Media/, Audio/, Text/, Stickers/, Effects/, Transitions/, Filters/, Voice/
│   │   ├── Viewer/                   # PlayerView (AVPlayerLayer), SafeAreaOverlay, CompareSlider
│   │   ├── Inspector/                # Video/, Audio/, Text/, Color/, Speed/
│   │   ├── Timeline/                 # TimelineView (NSView/CALayer), TrackHeader, Ruler, Toolbar
│   │   ├── AgentDock/                # TerminalTab, ContextChip, QuickActionBar, AskPopover (⌘K)
│   │   ├── Review/  Export/  History/  Doctor/  Settings/
│   │   └── Components/               # NumberScrubField, IconTabBar, Toast…
│   ├── Extensions/  Theme/
│   ├── Resources/
│   │   ├── Localizable.xcstrings     # en (development language) + vi
│   │   ├── LUTs/  Fonts/  Stickers/  # bundled defaults
│   │   └── Prompts/                  # bashcut-system-prompt.md, quick-actions/*.md (English)
│   └── CLI/
│       ├── BashCutCLIMain.swift      # target `bashcut` (swift-argument-parser)
│       └── MCPBridgeMain.swift       # target `bashcut-mcp` (MCP Swift SDK, stdio)
│
├── Packages/
│   └── BashCutCore/                  # swift-tools 6.0; `swift test` runs without Xcode
│       ├── Sources/
│       │   ├── BashCutProject/       # Project, Track, Item, EditOperation, apply/inverse, validate, migrate
│       │   ├── BashCutTimelineText/  # agent text form; "0:38.12" time parsing
│       │   ├── BashCutReview/        # review rules (hook, coverage, silence, VO overlap, framing…)
│       │   ├── BashCutImport/        # edl.json → Project
│       │   ├── BashCutInterchange/   # OTIO JSON writer, Resolve plan builder (pure, testable)
│       │   └── BashCutPlugin/        # bashcut.plugin/1 manifest, discovery, process RPC, health
│       └── Tests/<Target>Tests/
│
├── BashCutTests/                     # mirrors BashCut/ (Core/Engine/…, ViewModels/…), Helpers/ (fakes)
├── BashCutUITests/                   # XCTest; UITestCase launches the app on a temp fixture workspace
├── BashCutPerfTests/                 # XCTest measure: composition build, 10 s playback, 30 s export
│
├── Fixtures/
│   ├── workspace-mini/               # fake workspace: CLAUDE.md, small assets, 2 projects, trimmed real edl.json
│   ├── projects/                     # sample project.bashcut.json (schema v1), including broken files
│   └── make-media.sh                 # generates test clips with ffmpeg (testsrc2, sine, 1–5 s); not committed
│
├── scripts/
│   ├── generate-project.sh           # checks XcodeGen version, generates .xcodeproj
│   ├── verify.sh -> ../.claude/skills/verify/scripts/verify.sh
│   ├── install-cli.sh                # /usr/local/bin/bashcut shim (asks first)
│   └── build-release.sh  create-dmg.sh   # (later)
│
└── docs/
    ├── specs/                        # these documents
    ├── project-format.md             # canonical schema reference
    ├── automation.md                 # bashcut / MCP command reference (for agents and users)
    └── THIRD_PARTY.md                # dependencies and licenses
```

## Targets (`project.yml`)

| Target | Type | Notes |
|---|---|---|
| `BashCut` | application | macOS 14.0+; depends on `BashCutCore` products and SwiftTerm; provider-specific ML/audio libraries are not linked |
| `bashcut` | tool | CLI (swift-argument-parser + `BashCutWire`); copied to `Contents/MacOS` (`copy: destination: executables`) |
| `bashcut-mcp` | tool | stdio MCP server (MCP Swift SDK + `BashCutWire`) |
| `BashCutTests` | unit test | Swift Testing + swift-snapshot-testing |
| `BashCutUITests` | UI test | XCTest |
| `BashCutPerfTests` | unit test | run separately; not part of the default CI run |

## Plugin bundle and catalog layout

```text
<project>/.bashcut/plugins/<plugin-id>/   # highest-priority project override
~/Library/Application Support/BashCut/Plugins/<plugin-id>/
BashCut.app/Contents/PlugIns/<plugin-id>/ # optional bundled providers
└── plugin.json
└── bin/provider                         # executable entrypoint; receives `rpc`
```

Generated request outputs live in project-scoped, provider-specific request directories and are
validated before becoming project media. Plugin manifests and provider IDs are stable; model files,
venvs and downloaded dependencies remain owned by the plugin rather than the timeline schema.
