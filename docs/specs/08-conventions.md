# 08 — Conventions

BashCut is a single-user app, so its conventions stay small. This spec lists the rules every change keeps.
Step-by-step recipes for adding an agent provider, model adapter, command, UI action, plugin capability or
timeline format live in [CONTRIBUTING.md](../../CONTRIBUTING.md) and are not repeated here.

## Language

- **English everywhere in the repo:** code, identifiers, comments, commit messages, `AGENTS.md` and `docs/`.
- **UI:** English is the development language; Vietnamese ships as a localization. Strings live in
  `BashCut/Resources/Localizable.xcstrings` and both `Localizable.strings` files. The language follows the
  system or the choice in Settings.
- **Strings:** use `String(localized:)` without interpolation. When a value is needed, use
  `String(format: String(localized: "…%@"), value)`. Add a translator comment where the context is not obvious.
- **User content is never translated:** captions, voiceover text, section names and file names.
- **Agent instructions** are written in English. The agent replies in the language the user writes in.
- **Files inside the video workspace** follow the workspace convention: lowercase, no diacritics,
  hyphen-separated.

## Swift

- Swift 6 language mode with `SWIFT_APPROACHABLE_CONCURRENCY=YES` (`Configs/Base.xcconfig`); macOS 14.0.
- `@MainActor` for UI and `ProjectDocument`; `actor` for I/O.
- **The engine never touches `@MainActor` state.** The compositor reads immutable snapshots only.
- `@Observable` models. No Combine unless a system API requires it.
- `guard` for early exits. No force unwraps or force casts.
- Explicit access control, declared on extensions.
- Split large types into `TypeName+Area.swift`.
- Log with `Logger(subsystem: "app.bashcut", category: …)`, never `print`. Paths and user content are logged
  with `privacy: .private`.
- Comments say **why**, not **what**. Write known traps down, for example:
  `// 29.97 fps: keep integer frames; float seconds drift by a frame every ~33 s`.
- Formatting: `.editorconfig` (4 spaces, LF, UTF-8, final newline). SwiftLint with `.swiftlint.yml` is the lint
  authority and runs with `--strict` (line length 150, function body 100 lines, type body 350 lines, file 500
  lines).

## Project model

**Every change to `Project` goes through `EditOperation` and `Project.applying`.** UI, agents, model APIs, undo
and import all use this path, and the document commits through one `commit` choke point.

A new `EditOperation` case also gets a codec sample in `EditOperationCodecTests.samples` and an
apply→undo→redo round trip in `UndoRedoRoundTripTests`; a test fails until it has both.

**Changing the `project.bashcut.json` schema** (currently `bashcut.project/3`) requires:

1. A schema version bump.
2. A migration from the previous version, with a test.
3. Updates to [project-format.md](../reference/project-format.md) and the agent instructions.

**Keep the Resolve-ready rules** from [02-project-format.md](02-project-format.md) §5:

- original media references;
- source frames separate from timeline frames;
- role-based tracks;
- parameters, never baked results;
- stable IDs and the `interop` field.

A change that breaks one of these rules needs a note in the commit or PR explaining how "Apply to Resolve" stays
possible.

## Commands and UI actions

Every UI action and dialog is reachable from the CLI and MCP. A command is declared once as a `CommandSpec`
(name, mode, parameters, CLI form, sync or job), which drives validation, the CLI parser, the MCP tool and the
agent instructions. A new command also needs:

1. A handler that shares the UI's code path (`handle` for reads, `handleAuthored` for edits).
2. Coverage in `CommandSpecTests` (plus a parsing case for unusual parameters).
3. An entry in [automation.md](../guides/automation.md) and the command table in
   [05-agent-integration.md](05-agent-integration.md).

Buttons, menu items and shortcuts are `UIAction` cases; dialogs go through `ModalCenter` or
`ProjectDocument.openSheets()`. See
[CONTRIBUTING.md](../../CONTRIBUTING.md#add-a-command-cli-mcp-and-agent-instructions).

## Plugin capabilities

Adding or changing a plugin capability requires:

1. Stable, vendor-neutral capability and provider IDs.
2. Validation of every manifest field, dependency command, request and response at the boundary.
3. Returned files confined to the request folder before they are imported.
4. Results converted into normal validated `EditOperation` values; plugins never write the project file.
5. Plugin, provider and version provenance stored without making old media depend on the installed provider.
6. Catalog, process, health and adapter tests that never invoke a network, a real model or a user venv.
7. Updates to [plugins.md](../guides/plugins.md), [03-architecture.md](03-architecture.md) and the matching
   feature table.

Simple presets, deterministic transforms, timeline rules and normal rendering stay native and data-driven. Use a
plugin for large, optional, fast-moving or vendor-specific dependencies, not for every helper.

## Dependencies

- Follow [04-dependencies.md](04-dependencies.md): Apple frameworks first, permissive licenses only.
- A new package needs a note covering the reason, the license, the system-framework alternative and the size,
  and an entry in [third-party.md](../reference/third-party.md).
- Commit resolved versions (`Package.resolved` in the root and in `Packages/BashCutCore`).

## Tests

**Framework:** Swift Testing (`@Test("one-sentence behavior")`) for every test target. XCTest is reserved for
future UI and performance targets, which do not exist yet.

**Layout:**

- One test target per module: `Tests/BashCut<Module>Tests` for app libraries and
  `Packages/BashCutCore/Tests/BashCut<Module>Tests` for core modules.
- Shared fixtures:
  - `Tests/BashCutTestSupport`: `TestFixtures.mediaRoot`, `requireVideo()`, `temporaryDirectory()`,
    `writeTone()`.
  - `Packages/BashCutCore/Tests/BashCutProjectFixtures`: `ProjectFixtures.twoClips()`, `linkedPair()`,
    `undoRedo(_:on:)`.
- Fakes implement protocols directly (for example `PluginTransport` or the render engine) and live next to the
  tests that use them.

**Required coverage:**

- apply and inverse of every `EditOperation`, and the codec round trip;
- `edl.json` import, using trimmed fixtures from at least three real projects;
- review rules and layer rules;
- OpenTimelineIO export;
- frame ↔ `CMTime` mapping at 29.97 fps;
- command specs (schemas, defaults, CLI parsing, agent instructions).

**Engine golden tests:** render fixed frames from a fixture project and compare them with reference images within
a tolerance (swift-snapshot-testing, `Tests/BashCutEngineTests/__Snapshots__`). Captions in golden images use
Vietnamese diacritics (ă, ơ, ư, ỹ…). Test media comes from `Fixtures/make-media.sh` and is not committed.

**Tests never touch** the real workspace, the real `claude` or `codex`, real ML venvs or the network:

- Plugin tests use temporary executable fixtures and JSON responses through a fake or temporary
  `PluginTransport`; they never run an installed provider or dependency recipe.
- Model API tests check request bodies and recorded responses without network calls.
- App Support and `UserDefaults` are redirected to temporary locations.

## Build and verify

```bash
scripts/verify.sh build              # swift build
scripts/verify.sh test [args]        # app module tests, then Packages/BashCutCore tests
scripts/verify.sh lint [files…]      # swiftlint lint --strict; fails if SwiftLint is missing
scripts/verify.sh xcode [build|test] # regenerate BashCut.xcodeproj (XcodeGen) and build or test it
scripts/verify.sh perf               # engine tests at full size (BASHCUT_PERF=1)
scripts/run.sh                       # build, sign and open build/BashCut.app
Fixtures/make-media.sh               # once: generate Fixtures/media/test.mp4 for engine tests
```

`verify.sh` writes the full log to `build/logs/` and prints one `PASS` or `FAIL` line with the log path, plus the
first errors on failure. A missing tool is a failure, never a pass. Raw `xcodebuild` calls pass
`-skipPackagePluginValidation`. `verify.sh uitest` is reserved and exits with an error until UI tests exist.

`perf` uses synthetic media. Real-footage acceptance comes from `bashcut-bench` (see
[implementation.md](../status/implementation.md#m0-engine-acceptance-on-real-dji-footage-2026-10-02)).

## Git

- `bash-cut/` is its own repository.
- [Conventional Commits](https://www.conventionalcommits.org/), subject at most 72 characters, scope naming the
  area, for example `engine`, `timeline`, `media`, `text`, `audio`, `voice`, `color`, `agent`, `automation`,
  `plugins`, `document`, `storage`, `review`, `export`, `interchange`, `import`, `ui`, `deps`, `build`, `docs`.
- Every meaningful change adds a line under `[Unreleased]` in [CHANGELOG.md](../../CHANGELOG.md).
- Never commit `BashCut.xcodeproj`, `Configs/Secrets.xcconfig`, `.env` files, `build/`, `.build/`, generated test
  media or secrets.

## Two sets of agent instructions

Developing the app and editing videos use different instructions. Do not mix them.

| | Developing the app | Editing videos |
|---|---|---|
| Folder | `bash-cut/` | `nolan-video-workspace/` |
| Instructions | `bash-cut/AGENTS.md` | workspace `CLAUDE.md` (+ `AGENTS.md` for Codex) and `nolan-*` skills |
| What the agent does | edits Swift, runs `scripts/verify.sh` | runs `bashcut` commands, skills and Python scripts |
