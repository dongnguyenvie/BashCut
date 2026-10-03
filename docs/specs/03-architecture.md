# 03 — Architecture

How BashCut is put together: the render engine, the code layers, `EditOperation`, the plugin boundary, the
automation server, interchange formats, and the concurrency and security rules. What is built today is tracked
in [implementation status](../status/implementation.md).

## 1. Big picture

```text
┌─────────────────────────────────────── BashCut.app ────────────────────────────────────────┐
│ Views (SwiftUI hosted in AppKit; the timeline is a custom NSView)                          │
│   └─► ViewModels (@MainActor @Observable)                                                  │
│         └─► ProjectDocument ──commit(EditOperation)──► ProjectHistory (Project + undo)     │
│               │ per-project controllers built from AppServices                             │
│               ▼                                                                            │
│   Services   PreviewController · ExportController + ExportQueue · ProxyQueue · JobCenter   │
│              FileSyncController · SettingsModel · AutomationController                     │
│   Engine     RenderEngine ─► CompositionBuilder ─► AVPlayer (preview) / Exporter           │
│              BashCutCompositor (Core Image) · TextRenderer · MediaSource + ProxyManager    │
│   Plugins    CapabilityService ─► CapabilityAdapter ─► PluginTransport ──────────┐         │
│   Formats    TimelineExporter / TimelineImporter (OTIO, SRT, edl.json)           │         │
│   Agent      PTY tabs (SwiftTerm) ──spawn──► claude · codex · shell              │         │
│   Automation CommandRegistry (CommandSpec) ◄── Unix socket, JSON-RPC ◄──┐        │         │
└─────────────────────────────────────────────────────────────────────────┼────────┼─────────┘
                                                                          │        │
           bashcut CLI, bashcut-mcp (stdio MCP server spawned by agents) ─┘        ▼
                                                                           plugin processes
                                                                         (models, venvs, APIs)
```

**Core idea:** every change to a project is an `EditOperation` that goes through `ProjectDocument.commit`.
Operations from the UI, from agents (CLI, MCP or model APIs), from generated plugin results and from undo/redo all
take that one path. This is how "one action, two callers" is guaranteed.

### Extension boundaries

A small, stable core stays inside the app; everything heavyweight or fast-moving sits behind a replaceable
interface.

| Area | Rule |
|---|---|
| Stable core | The project model, integer frame timing, `EditOperation` validation, undo/redo and the timeline stay in the app and in `Packages/BashCutCore`, so every project can always be opened and edited |
| Rendering | Preview and export share one render graph. `RenderEngine` is a `Sendable` protocol; `AVFoundationRenderEngine` is the default implementation |
| Providers | Optional features resolve a capability (`voice.synthesize`, `captions.transcribe`, …) to a provider from project, user or bundled plugin folders (§5) |
| Presets | Export presets, text presets, reframing presets and transitions are data, not plugins |
| Plugins | Plugins run out of process over a versioned JSON protocol. The app never loads third-party Swift bundles or dynamic libraries |

Agent terminals (`AgentProvider`), model APIs (`ModelAdapter`), commands (`CommandSpec`), plugin capabilities
(`CapabilityAdapter`) and timeline formats (`TimelineExporter`/`TimelineImporter`) are each one conforming type
plus a registry entry. [CONTRIBUTING.md](../../CONTRIBUTING.md) has a template for each.

## 2. Render engine: AVFoundation, not ffmpeg

### Comparison

| Criterion | AVFoundation + Core Image | ffmpeg (`filter_complex`) |
|---|---|---|
| **Preview matches export** | ✅ The same `AVComposition` + `AVVideoComposition` drives `AVPlayer` and the exporter | ❌ ffmpeg cannot play in real time with scrubbing, so preview would need a second engine and the two would drift |
| Feedback while editing | ✅ Update the composition and play immediately; no pre-render | ❌ Re-render a segment after every edit |
| Hardware encode | ✅ VideoToolbox (H.264/HEVC/ProRes) | ✅ `h264_videotoolbox` |
| Text and captions | ✅ Core Text: any font, outline, emoji, Vietnamese diacritics | ⚠️ Needs libass/freetype. The Homebrew build on Nolan's machine **lacks them** (measured in the workspace) |
| LUTs, color | ✅ `CIColorCube` reads `.cube` files | ✅ `lut3d` |
| Shipping the app | ✅ Built into macOS | ⚠️ Bundle a binary (signing, notarization, LGPL/GPL depending on the build), or depend on Homebrew |
| Exotic formats (MKV, WebM, old codecs) | ❌ | ✅ |
| Loudness (EBU R128) | ❌ Not built in | ✅ `ebur128` filter |

### Decision

- **Preview and export use AVFoundation.** Video is composited by a custom `AVVideoCompositing` compositor
  written with Core Image; audio goes through `AVMutableAudioMix`.
- **`RenderEngine` is a protocol.** `build(_:root:workspace:purpose:)` returns a composition snapshot and
  `export(_:to:settings:progress:)` renders it. A second implementation (for example a headless batch exporter)
  can be added without touching the UI.
- **Loudness is measured by an optional `audio.loudness` provider.** A libebur128 wrapper is a suitable
  implementation, but its library is not linked into the base app.
- **ffmpeg is optional.** Doctor detects it. **Planned:** use it only to probe or transcode media that
  AVFoundation cannot open, transcoding to ProRes Proxy on import (the `media.transcode` capability in §5).

### Engine components

| Component | Responsibility |
|---|---|
| `CompositionBuilder` | An `actor`: `Project` → `AVMutableComposition` (tracks, `insertTimeRange`, `scaleTimeRange` for speed), per-frame video instructions and `AVMutableAudioMix`. Keeps up to 64 opened assets across builds. `PreviewController` rebuilds about 50 ms after an edit (debounced) |
| `BashCutCompositor` | `AVVideoCompositing`. For each frame, in track order: source frame → transform (reframe, crop) → color (adjustments + LUT) → transition → overlay items → text layers → output `CVPixelBuffer` |
| `TextRenderer` | Renders text with Core Text from the item's `textPreset` and `textStyle` overrides: Bold Outline, Cinematic Serif, Keyword Sticker, Place Card, Hook Title and Chapter Card. Images are cached. **Planned:** text animations (pop, word-by-word, typewriter) evaluated from time |
| `AudioGainPlanner` | Volume, fades, mix gain and ducking as one frame-based envelope. Speech regions (tagged speech clips and all voiceover) become volume ramps on Music tracks. **Planned:** stem separation from `audio.separate` output |
| `ExportPipeline` | Optional two-pass loudness: render a temporary mix, measure it through `audio.loudness`, apply true-peak-safe master gain, export and verify through the same provider. Also writes the companion SRT |
| `Exporter` | An `actor`: `AVAssetReader` + `AVAssetWriter` with hardware encoding. Presets are listed in [01 — UI/UX](01-ui-ux.md) §6. `ExportQueue` runs one export at a time on the shared `JobCenter`, with progress and cancellation |
| `MediaSource`, `ProxyManager` | The engine reads media through a `MediaSource`. `ProxyMediaSource` (the default) uses `.bashcut/proxies/<media id>.mov` for preview when it exists and always the original for export. `ProxyManager` flags HEVC, larger-than-1920 px or high-bit-rate footage and writes H.264 proxies (≤ 960 px, keyframe every 10 frames, original frame times); `ProxyQueue` makes them one at a time |

**Performance** was the biggest risk and was measured first, in M0. The targets were smooth 1080×1920 playback at
29.97 fps from original footage and scrub latency under 100 ms. On 20 real HEVC clips, playback drops no frames
and scrubbing reaches p95 19.6 ms (8.9 ms with proxies); figures and the reproduction command are in
[implementation status](../status/implementation.md).

## 3. Code layers

Code is organized by layer first, then by domain. `Package.swift` is the single source of targets.

| Layer | Contains | Rules |
|---|---|---|
| `Packages/BashCutCore` | `BashCutProject` (model, `EditOperation` and its codec, validation, layer rules, history, review, SRT, timeline format protocols), `BashCutPlugin` (manifest, catalog, provider resolution, `PluginTransport` and the process runner), `BashCutImport` (legacy `edl.json`) and `BashCutInterchange` (OTIO) | Pure logic. No AppKit or AVFoundation. Tested with `swift test` |
| `BashCut/Core/` | `Engine`, `Storage`, `Agent`, `Automation`, `Plugins` (`BashCutPlugins`: `CapabilityService` and adapters), `Services` and `Document` | `Services` is the testable `BashCutDocument` library: `EditorUIState`, `PreviewController`, `ExportController` (with `ExportQueue` and `JobCenter`), `ProxyQueue`, `FileSyncController`, `SettingsModel`, `AutomationController`, `ModalCenter` and `AppServices`. `ProjectDocument` (app target) owns history and the single `commit`, and wires the controllers together. Replaceable engines and transports sit behind protocols |
| `BashCut/Models/` | App-only value types | `Sendable` |
| `BashCut/ViewModels/` | `@MainActor @Observable final class` | Split large ones into `Name+Feature.swift` |
| `BashCut/Views/` | SwiftUI + AppKit (timeline, viewer) | Never call services directly |

Dependency injection goes through one composition root. `AppServices.live()` bundles the app-wide services
(render engine, settings, automation endpoint), and `ProjectDocument(services:)` builds its per-project
controllers from them. Tests pass their own engine, `UserDefaults` suite and socket paths.

BashCut targets **macOS 14+** in order to use `@Observable` instead of `ObservableObject`.

### Timeline UI

The timeline can hold hundreds of items plus waveforms and thumbnails, so it is **not built from SwiftUI views**.
It is a custom `NSView` (`TimelineCanvas`) in a scroll view:

- only the visible range is drawn;
- thumbnails and waveforms are cached;
- hit-testing is custom.

SwiftUI is used for track headers, the toolbar and popovers.

## 4. `EditOperation`

`EditOperation` lives in `BashCutProject`. Abridged:

```swift
public indirect enum EditOperation: Codable, Sendable, Equatable {
    case insert(track: String, item: Item)
    case delete(item: String, ripple: Bool)
    case split(item: String, atFrame: Int, newID: String)
    case trim(item: String, edge: Edge, toFrame: Int, ripple: Bool)
    case move(item: String, toTrack: String, atFrame: Int)
    case reorder(item: String, before: String?)
    case slip(item: String, sourceIn: Int)
    case roll(item: String, edge: Edge, toFrame: Int)
    case setSpeed(item: String, speed: Double, keepDuration: Bool)  // clip + linked partner, ripples its layers
    case setProperties(item: String, patch: [String: JSONValue])  // transform, volume, color, text…
    case setLinkedAudio(video: String, audio: String?)
    // media, tracks, project properties, provider preferences, beat grid,
    // sections, transitions and LUT catalog operations …
    case group(label: String, author: Author, ops: [EditOperation])  // one undo step
    case restore(Project)                                            // snapshot inverse
}

public enum Author: String, Codable, Sendable { case user, claude, codex, external, model, agent }
```

How it behaves:

- **`applying` is a pure function** in the package. It validates the project before and after the edit and
  returns the new `Project` with its inverse (a `restore` snapshot).
- **It fails with a reason** such as an unknown item, a trim past the end of the source or an overlap on a track.
- **Each successful edit increments `rev`** once, including a whole `group`.
- **Agent requests carry a `baseRev`.** If it does not match the current `rev`, the request is rejected with
  `staleRevision`; the agent re-reads the timeline and retries.
- **One serialized form.** Operations are JSON objects keyed by `op` (`EditOperationCodec`), shared by agents,
  model APIs and the history journal. `group` and `restore` are accepted only from trusted sources.

The on-disk effects (layer rules, linked items, undo depth) are in the
[project format reference](../reference/project-format.md).

## 5. Plugins

### Optional plugin boundary

BashCut uses plugins for optional features with large or fast-moving dependencies. The timeline, project schema,
history, compositor contract and normal export stay in the app. Transcription, beat analysis, loudness, voice
providers and, later, stem separation, stock-media sources and extra interchange exporters run as child
processes. A crash takes down only the provider process.

Each plugin is a folder with a `bashcut.plugin/1` `plugin.json`, an executable entrypoint, stable capability IDs
and dependency records. The manifest and wire contract are in [Writing plugins](../guides/plugins.md).

**Discovery.** Plugins are discovered in this order, earlier entries winning duplicate IDs:

1. `<project>/.bashcut/plugins/`;
2. `~/Library/Application Support/BashCut/Plugins/`;
3. the app bundle's built-in `PlugIns` directory.

A malformed manifest, duplicate ID or failed dependency probe becomes a diagnostic or a degraded provider; it
never stops the editor or the project from opening.

**Installation.** Dependency probes and install recipes are argv arrays, not shell strings. The Plugins window
shows capabilities, dependency names, estimated downloads and the exact commands. The installer stages and
validates the selected folder, runs recipes only after the user approves, then publishes the plugin atomically
into the user catalog. Agents can cancel an install request but never approve it.

**One capability path.** `CapabilityService` (`BashCut/Core/Plugins`, module `BashCutPlugins`) discovers the
catalog, probes health, resolves the provider, runs the request and validates the result. Each capability is a
`CapabilityAdapter` (request parameters, validation and result parsing in one file), and every call goes through
a `PluginTransport`; `PluginProcessRunner` is the one-shot transport. Native panels, the automation commands
(`captions.generate`, `beats.detect`, `voice.speak`) and normalized export all call the service; no view model
or command talks to a plugin process directly. The document turns the validated result into one undoable
`EditOperation` attributed to its author, so UI and agent requests produce identical edits.

**Provider resolution.** Feature code resolves a capability such as `voice.synthesize`; it never imports or names
a vendor SDK. A plugin can declare several provider IDs for one capability. Resolution uses the project
preference, then an optional user default, then the highest-priority healthy provider. Feature panels persist
the project preference as ordinary undoable data. Generated media stores the provider ID and version as
provenance and stays usable if that provider is removed, so replacing a provider never migrates the timeline.

- **Planned:** a Settings UI for user-wide provider defaults.

**Process protocol.** Each request starts one child as `entrypoint rpc`, writes one bounded JSON request to stdin
and reads one bounded JSON response from stdout. Calls time out after 120 seconds by default and support task
cancellation; the child runs in its own process group, which is terminated as a whole on cancellation or
timeout. Children receive a filtered environment (`HOME`, `PATH`, `TMPDIR`, locale values and
`BASHCUT_PLUGIN_*` metadata); automation tokens, model credentials and `.env` values are not inherited. Returned
files must lie inside the per-request output folder and are validated before insertion.

| Capability | Consumer and validated result | Provider examples |
|---|---|---|
| `voice.synthesize` | Voice panel and `voice.speak` request 1–8 takes, validate the audio, score takes by pacing when the provider gives no score, and insert one take with provenance | VieNeu-TTS wrapper, local voice model, remote voice API |
| `captions.transcribe` | Text panel and `captions.generate` accept confined UTF-8 SRT up to 4 MiB and import it as one undoable edit | WhisperKit wrapper, workspace Whisper venv, remote transcription API |
| `audio.beats` | Audio panel and `beats.detect` validate BPM and increasing source seconds, then map them through trim and speed to integer timeline frames | Workspace beat script, future vDSP detector |
| `audio.loudness` | Export validates LUFS, true peak and LRA, applies target-LUFS gain with a −1 dBTP ceiling and verifies the final file | libebur128 wrapper, compatible analyzer |

Direct voice recording, thumbnails, media metadata, waveforms, project editing, composition, normal export, model
API adapters, SRT and OTIO stay native: they are core editor behavior, small and dependency free, or already well
covered by Apple frameworks.

### Plugin platform roadmap

Plugins stay out of process. Providers (Python venvs, ML runtimes, remote SDKs) can crash or hang, and a crash in
process would take down the editor. The platform grows in these steps (contract details in
[Writing plugins](../guides/plugins.md)):

| Step | Pattern | BashCut design | Status |
|---|---|---|---|
| 1 | Factory + adapter between feature and plugin | `CapabilityService` with `CapabilityAdapter` and `PluginTransport`, shared by panels, CLI/MCP and export; provider-backed automation runs as background jobs | **Implemented** |
| 2 | Common providers bundled with the app | Native Swift helper executables in `Contents/PlugIns/` for `audio.loudness` (EBU R128 with vDSP) and `audio.beats` (vDSP onset/tempo); VieNeu and Whisper wrappers stay user or project plugins. Shipped as `bashcut.audio-analysis` (`Plugins/audio-analysis/`) | **Implemented** |
| 3 | Long-lived helper with handshake, request IDs and cancel | `PluginSessionTransport` for manifests with `"transport": "session"`: `hello` handshake, NDJSON requests matched by ID, `progress` lines reported on the job, `cancel`, `shutdown` after 90 s idle, restart after a crash and a one-minute refusal after 3 crashes. `PluginRouter` picks it or the one-shot runner per plugin; one request per process stays the default | **Implemented** |
| 4 | API version window and availability reasons | Host API 1…2 with additive changes; `minApiVersion`/`maxApiVersion`; availability `ready`, `disabled`, `untrusted`, `changed`, `outdated` plus dependency health; a user enable/disable list (and a hooks switch) per plugin. The remote registry (row 8) offers providers to install from panels. Not done: `notInstalled`/`failedToLoad` states (catalog diagnostics remain) | **Implemented** |
| 5 | Code-signature trust gate | `PluginTrustStore` pins SHA-256 of `plugin.json` and the entrypoint when the user installs or trusts a plugin; a change marks it `changed` until trusted again; bundled plugins are trusted. Trusting and turning plugins on are user-only. Registry archives carry ed25519 signatures checked against the key compiled into the app | **Implemented** |
| 6 | Plugin-supplied settings | Manifest `options` (string, enum, number, integer, bool) rendered natively in the Plugins sheet, stored per user (`plugin-trust.json`) or per project (`pluginOptions`, undoable) and sent with each request | **Implemented** |
| 7 | Contributions and hooks | `contributes.actions` in fixed placements (Plugins menu, toolbar, clip/track/timeline/media context menus, library panels, inspector tabs) with app-evaluated `when` conditions and native parameter sheets; `contributes.hooks` for editor events (notify-only, debounced, rate-limited). Results propose operations and a per-plugin `pluginData` entry that the document validates and commits as one undoable `plugin` edit; hook edits wait for review unless Settings applies them. Every action and setting has a `plugins …` command | **Implemented** |
| 8 | Remote registry | Static `registry.json` in `dongnguyenvie/bashcut-plugins` plus GitHub Release archives (no server); `PluginRegistryClient` (5-minute cache, ETag, offline copy), `PluginArchiveInstaller` (HTTPS from GitHub hosts, SHA-256, staging, manifest and id/version checks), Browse/Updates/Remove in Plugins, `plugins search/updates/install/remove`. ed25519 archive signatures are reserved | **Implemented** |

Candidate capabilities after these steps are `media.analyze` (measured silence and speech coverage),
`audio.separate` (Demucs), `voice.enroll`, `media.transcode` (optional ffmpeg) and `interchange.export` (FCPXML,
Resolve plans). A signed remote catalog, per-capability permissions and plugin-owned panels wait until BashCut is
distributed.

## 6. Automation server

The app listens on a **Unix domain socket** at `~/Library/Application Support/BashCut/automation.sock` with
permissions `0600` (overridable with `BASHCUT_SOCKET`). The protocol is newline-delimited JSON-RPC 2.0; the wire
types are in `BashCutAutomation`. Clients are served concurrently, so a slow client never stalls another.

**Why a socket instead of HTTP:**

- no port is opened;
- filesystem permissions already restrict access to the user;
- no HTTP server dependency is needed.

**Two thin clients connect to it:**

| Client | Built with | Used by |
|---|---|---|
| `bashcut` CLI | swift-argument-parser | Bash inside agent tabs, scripts, the user. Embedded in the app bundle; agent tabs get its folder on `PATH` |
| `bashcut-mcp` | Official MCP Swift SDK (stdio server transport) | `claude` and `codex` spawn it as an MCP server; it forwards each tool call to the socket |

**Command specs.** Every command is declared once as a `CommandSpec` in `CommandCatalog.specs`: name, mode
(`read`, `ui`, `edit` or `privileged`), parameters, CLI binding and execution (`immediate`, `job` or `approval`).
`CommandRegistry` validates each request against its spec (types, ranges, choices, defaults, unknown parameters)
before the `@MainActor` handler runs. The CLI parser, the MCP tools (`bashcut_<name>`), `bashcut help` and the
agent instructions are generated from the same specs, and a test keeps them consistent. Every toolbar button,
menu item and shortcut is also a `UIAction` that `ui action` runs through the same code.

**Session tokens and authors.** Each agent tab gets its own token in `BASHCUT_SESSION_TOKEN`. The token identifies
the author (Claude, Codex or which tab) and is revoked when the tab closes or when agent edits are turned off in
Settings. Agents outside the app read a `0600` token file next to the socket and edit as `agent`; a Settings
switch turns it off or rotates it. `edit` and `privileged` commands need a live token, and privileged commands
such as exports also need the user's approval in the app unless Settings allows them to run without confirmation.

The full command list is in [Automation](../guides/automation.md) and
[05 — Agent integration](05-agent-integration.md).

## 7. Interchange: formats beyond video

Timeline formats are registered in `TimelineFormats`; adding a format means one conforming type and one registry
entry.

```swift
public protocol TimelineExporter: Sendable {
    var id: String { get }                 // "otio", "srt"
    var title: String { get }
    var fileExtension: String { get }
    func data(for project: Project) throws -> Data
}

public protocol TimelineImporter: Sendable {
    var id: String { get }
    var title: String { get }
    var fileExtensions: [String] { get }
    func importTimeline(_ data: Data, name: String, destinationDirectory: URL) throws -> TimelineImport
}
```

| Format | Direction | Status | How |
|---|---|---|---|
| Video (`RenderEngine`) | Export | **Implemented** | §2 |
| `.srt` captions | Export, import | **Implemented** | `SubRipExporter` writes the caption tracks; SRT import goes through the Text library and `captions` commands |
| OTIO | Export | **Implemented** | Writes OTIO JSON directly (no library); media references the originals |
| Legacy `edl.json` | Import | **Implemented** | [02 — Project format](02-project-format.md) §4 |
| **Resolve** | Export | **Reserved** | See below |

### How "Apply to Resolve" will work

**Reserved; not built in v1.** Resolve needs more than a file: a pure planning step and a long-running apply with
progress, so its exporter extends the format interface with `plan(_ project:) -> ExportPlan` and
`run(_ plan:, progress:) async throws -> ExportReceipt`.

1. **`plan`** classifies every property.
   - *Native in Resolve Free:* cut, transform, opacity, LUT, markers, clip color.
   - *Rendered by BashCut:* captions and animated overlays → one ProRes 4444 alpha overlay; transitions and speed
     changes → pre-rendered clips; volume and ducking → four premixed stems.
   - The UI shows the plan before anything runs.
2. **BashCut renders the needed artifacts** into `projects/<video>/resolve-media/b<HHMMSS>/`.
3. **BashCut writes a task file** and runs it through the workspace bridge:
   `tools/.venvs/resolve-mcp/bin/python tools/editor-skills/nolan-resolve-bridge/bridge_run.py <task> <out.json> --project <name>`.
   - The task uses `AppendToTimeline` with `trackIndex` + `recordFrame`.
   - Exit codes 2, 3 and 4 map to GUI instructions: start `resolve_bridge`, click **Not Yet**, or switch project.
4. **The receipt** stores Resolve IDs in each item's `interop.resolve`, with verification numbers: clips per
   track, offline count, V1 gaps, duration.

No dependency is needed. It reuses the workspace bridge, and the data rules in
[02 — Project format](02-project-format.md) §5 keep it possible.

## 8. Concurrency and security

**Concurrency:**

- Swift 6 language mode.
- `@MainActor` for UI, `ProjectDocument`, the `BashCutDocument` controllers, `JobCenter` and `CommandRegistry`.
- `actor`s for composition building, export rendering, waveform analysis, project storage, the automation socket
  server, the audit log and the credential store.
- Long work reports progress through `@Sendable` callbacks into `JobCenter` and stops on task cancellation.
  Plugin processes are terminated as a process group.
- The compositor runs on AVFoundation's own queue. It reads only an immutable `Project` snapshot (a value type)
  and never touches `@MainActor`.

**Security:**

- The app is not sandboxed: it has to spawn CLIs and read the workspace. **Planned:** hardened runtime and
  signing when BashCut is distributed.
- The automation socket and token file are `0600`; `edit` and `privileged` commands require a live token, and
  privileged commands require in-app approval by default.
- Agent terminals and plugin processes receive allowlisted environments, never the app's full environment.
- Model API keys live in the Keychain. `.env` contents and keys are never logged; the debug log
  (`~/Library/Logs/BashCut/debug.log`) records actions and decisions, not credentials.
