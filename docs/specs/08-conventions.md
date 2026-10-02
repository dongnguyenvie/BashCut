# 08 — Conventions

These conventions are kept small for a single-user app.

## Language

**English is the default for everything in the repo:** code, identifiers, comments, commits,
`AGENTS.md` and `docs/`.

**UI:**

- English is the development language. Vietnamese ships as a localization in
  `Localizable.xcstrings`.
- The language can be switched in Settings, or follows the system setting.

**Strings:**

- Use `String(localized:)` with no interpolation.
- When a value is needed, use `String(format: String(localized: "…%@"), x)`.
- Add a translator comment wherever the context is not obvious.

**User content is never translated:** captions, voiceover text, section names, file names.

**Agent prompt templates** live in `Resources/Prompts/` and are written in English. The agent
replies in the language the user writes in.

**Files inside the video workspace** follow the workspace convention: lowercase, no diacritics,
hyphen-separated.

## Swift

- Swift 6 language mode, `SWIFT_APPROACHABLE_CONCURRENCY=YES`.
- `@MainActor` for UI and `ProjectDocument`; `actor` for I/O.
- **The engine never touches `@MainActor`.** The compositor reads immutable snapshots only.
- `@Observable` view models. No Combine unless a system API requires it.
- `guard` for early exits.
- No force unwraps or casts.
- Explicit access control, declared on extensions.
- Split large types into `TypeName+Category.swift`.
- Log with `Logger(subsystem: "app.bashcut", category: …)`, never `print`. Paths and user content
  are logged with `privacy: .private`.
- Comments say **why**, not **what**. Write known traps down, for example:
  `// 29.97 fps: keep integer frames; float seconds drift by a frame every ~33 s`.
- SwiftLint `--strict` is the authority. `.editorconfig`: 4 spaces, lf.

## Project model

**Every change to `Project` goes through `EditOperation` + `apply`. No shortcuts.** UI, agent,
undo and import all use this path.

**Changing the `project.bashcut.json` schema** requires all of the following:

1. Bump `schema` (`bashcut.project/2`, …).
2. Write a migration and a test for it.
3. Update `docs/project-format.md` and the agent text form.

**Keep the Resolve-ready rules** from `02-project-format.md` §5:

- original media references;
- source frames versus timeline frames;
- role-based tracks;
- parameters, never baked results;
- stable IDs and the `interop` field.

A change that breaks one of these rules needs a note in the PR explaining how "Apply to Resolve"
still remains possible.

**Adding a command to `CommandRegistry`** requires all of the following:

1. Declare its mode (read, ui, edit, privileged).
2. Write a test.
3. Update `docs/automation.md`.
4. Update the system prompt if agents need to know about it.

## Dependencies

- Follow `04-dependencies.md`.
- A new package needs a PR note covering: the reason, the license, the alternative using system
  frameworks, and the size.
- Also add it to `docs/THIRD_PARTY.md`.

**Adding or changing a plugin capability** requires all of the following:

1. Keep the capability and provider IDs stable and vendor neutral.
2. Validate every manifest field, dependency command, request and response at the boundary.
3. Confine returned files to the request directory before importing them.
4. Convert the result into normal validated `EditOperation` values; plugins never mutate the
   project file themselves.
5. Store plugin/provider/version provenance without making old media depend on the installed
   provider.
6. Add catalog, process, health and feature-adapter tests without invoking a network, real model or
   user venv.
7. Update `docs/plugin-api.md`, `03-architecture.md` and the relevant feature table.

Simple presets, deterministic transforms, timeline rules and normal rendering stay native/data
driven. Use a plugin for large, optional, fast-moving or vendor-specific dependencies rather than
for every helper function.

## Tests

**Frameworks:**

- **Swift Testing** for unit tests: `@MainActor struct FooTests { @Test("one-sentence behavior") func … }`.
- XCTest only for UI and performance tests.

**Layout:**

- One test target per module (`Tests/<Module>Tests`, `Packages/BashCutCore/Tests/<Module>Tests`).
- Shared fixtures live in `Tests/BashCutTestSupport` (media, scratch folders, audio) and
  `Packages/BashCutCore/Tests/BashCutProjectFixtures` (projects, apply→undo→redo helper).
- Fakes implement protocols directly and live next to the tests that use them.

**Required test coverage:**

- `apply` and the inverse of every `EditOperation`;
- `edl.json` import, using trimmed fixtures from at least 3 real projects;
- review rules;
- the text form;
- the OTIO writer and Resolve plan builder (snapshot tests);
- frame ↔ `CMTime` mapping at 29.97 fps.

**Engine golden tests:**

- Render a few fixed frames from a fixture project and compare them with reference images within
  a tolerance, using swift-snapshot-testing.
- Captions in the golden images use Vietnamese diacritics (ă, ơ, ư, ỹ…).
- Test media is generated by `Fixtures/make-media.sh` and not committed.

**Tests never touch:**

- the real workspace;
- the real `claude` / `codex`;
- real ML venvs;
- the network.

How this is enforced:

- Plugin tests use temporary executable fixtures and JSON responses through
  `PluginProcessRunner`; they never invoke an installed provider or dependency recipe.
- Provider-specific engines are represented only by manifest/capability contracts in base-app
  tests.
- App Support and UserDefaults are redirected to a temporary directory.

## Build and verify

```bash
scripts/generate-project.sh
scripts/verify.sh build
scripts/verify.sh test [Suite]
scripts/verify.sh lint [files…]
scripts/verify.sh uitest
scripts/verify.sh perf            # BashCutPerfTests against thresholds
(cd Packages/BashCutCore && swift test)
```

`verify.sh` writes the full log to `build/logs/` and prints only `PASS`/`FAIL`, the log path and
the first few errors. Raw `xcodebuild` calls always pass `-skipPackagePluginValidation`.

## Git

- Separate repo for `bash-cut/`.
- Conventional Commits, at most 72 characters. Scopes:
  `engine`, `timeline`, `viewer`, `library`, `inspector`, `text`, `audio`, `voice`, `effects`,
  `color`, `agent`, `automation`, `review`, `export`, `interchange`, `import`, `doctor`, `ui`,
  `deps`, `build`, `docs`.
- Every meaningful change adds a line under `[Unreleased]` in `CHANGELOG.md`.
- Never commit:
  - `BashCut.xcodeproj` (except `Package.resolved`);
  - `Configs/Secrets.xcconfig`;
  - `build/`;
  - generated test media.

## Two sets of agent instructions: don't mix them

| | Developing the app | Editing videos |
|---|---|---|
| Folder | `bash-cut/` | `nolan-video-workspace/` |
| Instructions | `bash-cut/AGENTS.md` | workspace `CLAUDE.md` (+ `AGENTS.md` for Codex) + `nolan-*` skills |
| What the agent does | edits Swift, runs `verify.sh` | runs `bashcut` commands, skills, Python scripts |
