# Contributing to BashCut

Read `AGENTS.md`, `docs/specs/README.md` and `docs/status/implementation.md` first. This file covers the
build layout and how to add the common kinds of extension. Each one is **one file plus a test**: write the
conforming type, add it to its registry, and cover it with a test that needs no network, agent CLI or real
footage.

## Build and verify

`Package.swift` is the single source of targets. `project.yml` (XcodeGen) only declares the app bundle, the
embedded `bashcut` / `bashcut-mcp` tools and one test bundle, and links the package's library products.
A new source file in an existing module needs no build change; a new module is a target (and, if the app
uses it, a library product) in `Package.swift` plus a `package: BashCut` dependency in `project.yml`.

```bash
scripts/verify.sh build          # swift build
scripts/verify.sh test           # app module tests, then Packages/BashCutCore tests
scripts/verify.sh lint           # SwiftLint --strict (the lint authority)
scripts/verify.sh xcode build    # regenerate BashCut.xcodeproj and build it (also: xcode test)
scripts/run.sh                   # build, sign and open build/BashCut.app
Fixtures/make-media.sh           # once: generates Fixtures/media/test.mp4 (ffmpeg) for engine tests
scripts/sample-project.py        # sample project with every timeline case, built and checked through the CLI
```

To try a change by hand, open the [sample project](docs/guides/sample-project.md): it has linked clips, a LUT,
freeze frame, speed, a gap, a transition, picture in picture, captions, locked/hidden/muted layers, voiceover,
music with a beat grid and ducking, SFX and sections. `scripts/sample-project.py` also runs as an end-to-end
check; when you add something the timeline shows, add it there too.

Each run writes its full log to `build/logs/` and prints one PASS/FAIL line.

| Module | Sources | Tests |
|---|---|---|
| `BashCutProject`, `BashCutPlugin`, `BashCutImport`, `BashCutInterchange` | `Packages/BashCutCore/Sources/<Module>` | `Packages/BashCutCore/Tests/<Module>Tests` |
| `BashCutEngine`, `BashCutStorage`, `BashCutAgent`, `BashCutAutomation`, `BashCutPlugins`, `BashCutDocument` | `BashCut/Core/<Folder>` | `Tests/<Module>Tests` |
| App (views, `ProjectDocument`) | `BashCut/` | via the library modules it calls |

Shared fixtures: `Tests/BashCutTestSupport` (`TestFixtures.mediaRoot`, `requireVideo()`,
`temporaryDirectory()`, `writeTone()`) and `Packages/BashCutCore/Tests/BashCutProjectFixtures`
(`ProjectFixtures.twoClips()`, `linkedPair()`, `undoRedo(_:on:)`).

Rules that every change keeps:

- Edits go through `EditOperation` and `Project.applying`; a new operation case also gets a codec sample in
  `EditOperationCodecTests.samples` and a round trip in `UndoRedoRoundTripTests` (a test fails until it has).
- Every UI action and dialog is reachable from the CLI/MCP (see "Add a command" below).
- English code and docs; user-facing strings go in `Localizable.xcstrings` and both `Localizable.strings`.
- Conventional Commits; record meaningful changes in `CHANGELOG.md`.

## Add an agent provider (terminal program)

`BashCut/Core/Agent/<Name>AgentProvider.swift`, registered in `AgentProviders.all`:

```swift
import BashCutProject
import Foundation

/// Example CLI agent; resumes with `--resume <id>`.
public struct ExampleAgentProvider: AgentProvider {
    public init() {}
    public let id: AgentProviderID = "example"
    public let title = "Example"
    public let command = "example"
    public let author = Author.agent
    public let environmentAllowlist = ["EXAMPLE_*"]
    public let sessionFolder: String? = ".example/sessions"

    public func commandLine(for request: AgentLaunchRequest) throws -> AgentCommandLine {
        var arguments = ["--mcp", request.mcpExecutable]
        if !request.resumeID.isEmpty { arguments += ["--resume", request.resumeID] }
        return AgentCommandLine(arguments: arguments)
    }
}
```

Test in `Tests/BashCutAgentTests` with `AgentLaunch.make(provider:…)`: the arguments, that only allowlisted
variables reach the environment, and the session folder.

## Add a model API adapter

`BashCut/Core/Agent/<Name>ModelAdapter.swift`, registered in `ModelAdapters.all`:

```swift
import BashCutProject
import Foundation

public struct ExampleModelAdapter: ModelAdapter {
    public init() {}
    public let kind: ModelAPIKind = "example"
    public let title = "Example API"
    public let endpointPath = "generate"

    public func body(_ request: ModelRequest) -> [String: JSONValue] {
        ["model": .string(request.model), "system": .string(request.system), "input": .string(request.prompt),
         "max_tokens": .integer(request.maxOutputTokens)]
    }

    public func authorize(_ request: inout URLRequest, key: String) {
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }

    public func text(from response: [String: JSONValue]) -> String { response["output"]?.string ?? "" }
}
```

Test in `Tests/BashCutAgentTests/ModelClientTests.swift`: request body and headers, and text extraction from a
recorded response. Never call the network.

## Add a command (CLI, MCP and agent instructions)

1. A `CommandSpec` in `BashCut/Core/Automation/CommandCatalog.swift`, in the group that matches its mode.
   The spec drives validation, the CLI parser, the MCP tool and the agent instructions:

   ```swift
   CommandSpec(
       "markers.list", .read, "List section markers with their frames.",
       parameters: [CommandParameter("from", .integer, "First frame", minimum: 0, cli: .option("from"))]),
   ```

2. A handler next to the related ones in `BashCut/Core/Document/ProjectDocument+*.swift`. Use `handle` for
   reads and `handleAuthored` for edits (it requires a session token). Share the code with the UI; never
   duplicate an edit path:

   ```swift
   handle("markers.list") { document, arguments, _ in
       let from = arguments.optionalInt("from") ?? 0
       return .array(document.project.sectionMarkers.filter { $0.at >= from }.map { .object($0.fields) })
   }
   ```

3. Tests: `Tests/BashCutAutomationTests/CommandSpecTests.swift` checks every spec has a valid schema and CLI
   form; add a parsing case if the command has unusual parameters. Debug builds assert every spec has a
   handler at launch.
4. Document it in `docs/guides/automation.md` and the command table in `docs/specs/05-agent-integration.md`.

A new button, menu item or shortcut is a `UIAction` case (ID, title, shortcuts) in
`BashCut/Core/Automation/UIAction.swift`, handled in `ProjectDocument+UIActions.swift` and bound in the view
with `.action(_:in:)`; `ui action <id>` then runs it with no extra command. A new dialog goes through
`ModalCenter` (alerts and panels) or `ProjectDocument.openSheets()` (sheets) so `ui dialog` / `ui respond`
can answer it.

## Add a plugin capability

`BashCut/Core/Plugins/Capabilities/<Name>Capability.swift`. `CapabilityService.run` resolves the provider,
creates the request folder, calls the transport and attaches provenance; the adapter only builds parameters
and validates the result:

```swift
import BashCutPlugin
import BashCutProject
import Foundation

/// `video.scenes`: cut points detected in a media file.
public struct SceneDetectionCapability: CapabilityAdapter {
    public static let capability = "video.scenes"
    public let mediaURL: URL

    public init(mediaURL: URL) { self.mediaURL = mediaURL }

    public func validate() throws {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Scene detection source is unavailable")
        }
    }

    public func params(outputDirectory: URL?) -> JSONValue { .object(["mediaPath": .string(mediaURL.path)]) }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> [Double] {
        let values = result.object["cutsSeconds"]?.array ?? []
        let cuts = values.compactMap(\.double)
        guard cuts.count == values.count, cuts.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw PluginError.invalid("Scene plugin returned invalid cutsSeconds")
        }
        return cuts
    }
}
```

Call it from the app with `try await plugins.service.run(SceneDetectionCapability(mediaURL: url),
preferredProvider: nil, projectRoot: root)` (see `ProjectDocument+Capabilities.swift`). Test in `Tests/BashCutPluginsTests/CapabilityServiceTests.swift` with a fake
`PluginTransport` (valid result, invalid result, missing input). If agents should run it, add a `.job`
command as above.

## Add a timeline format

An exporter or importer in `Packages/BashCutCore/Sources/BashCutInterchange` (or `BashCutImport`), listed in
`TimelineFormats.exporters` / `.importers` (`BashCut/Core/Services/TimelineFormats.swift`):

```swift
import BashCutProject
import Foundation

/// Section markers as a CSV chapter list.
public struct ChapterCSVExporter: TimelineExporter {
    public let id = "chapters"
    public let title = "Chapter list"
    public let fileExtension = "csv"

    public init() {}

    public func data(for project: Project) throws -> Data {
        let rows = project.sectionMarkers.map { "\(Double($0.at) / project.fps.value),\($0.label)" }
        return Data((["seconds,label"] + rows).joined(separator: "\n").utf8)
    }
}
```

An importer returns a `TimelineImport` (new project, counts of what the source had next to what was
imported, warnings); the import report sheet and `edl import`-style results come from it. Test in
`Packages/BashCutCore/Tests/BashCutInterchangeTests` with an in-memory project or a small fixture string.
