# 03 — Architecture

## 1. Big picture

```
┌────────────────────────────────────── BashCut.app ───────────────────────────────────────┐
│ Views (SwiftUI hosted in AppKit; timeline + viewer = AppKit/Metal)                        │
│   └─► ViewModels (@MainActor @Observable)                                                 │
│         └─► ProjectDocument ──apply(EditOperation)──► Project (value type) + UndoLog      │
│                 │                       ▲                                                 │
│                 ▼                       │ same operation API                              │
│   Engine: CompositionBuilder ──► AVPlayer (preview)      Automation server                │
│           BashCutCompositor (Core Image + Metal)           (Unix socket, JSON-RPC)        │
│           Exporter (AVAssetWriter + VideoToolbox)            ▲            ▲               │
│   Media: thumbnails, waveforms, probe, proxies               │            │               │
│   Plugins: capability resolver ──bounded process RPC────────►│ optional provider processes │
│            voice · captions · beats · loudness               │ models / venvs / APIs       │
│   Interchange: TimelineExporter (OTIO now-ish, Resolve later)│            │               │
│   Agent: PTY tabs (SwiftTerm) ──spawn──► claude / codex      │            │               │
│   Review · Doctor · Process · Storage                        │            │               │
└──────────────────────────────────────────────────────────────┼────────────┼───────────────┘
                                                               │            │
                              bashcut CLI (Bash in agent tab) ─┘            └─ bashcut-mcp (stdio MCP server
                                                                               spawned by claude/codex)
```

**Core idea:** every change to a project is an `EditOperation` that goes through
`ProjectDocument.apply`. Operations from the UI, from the agent (MCP or CLI), and from undo/redo
all take the same path. This is how "one action, two callers" is guaranteed.

## 2. Render engine: AVFoundation, not ffmpeg

### Comparison

| Criterion | AVFoundation + Core Image/Metal | ffmpeg (filter_complex) |
|---|---|---|
| **Preview matches export** | ✅ The same `AVComposition` + `AVVideoComposition` drives `AVPlayer` and the exporter | ❌ ffmpeg cannot play in real time with scrubbing, so preview would need a second engine and the two would drift |
| Feedback while editing | ✅ Update the composition and play immediately; no pre-render | ❌ Re-render a segment after every edit |
| Hardware encode | ✅ VideoToolbox (H.264/HEVC/ProRes) | ✅ `h264_videotoolbox` |
| Text / captions | ✅ Core Text: any font, outline, emoji, Vietnamese diacritics | ⚠️ Needs libass/freetype. The Homebrew build on Nolan's machine **lacks them** (measured in the workspace) |
| LUTs, color | ✅ `CIColorCube` reads `.cube` files | ✅ `lut3d` |
| Shipping the app | ✅ Built into macOS | ⚠️ Bundle a binary (signing, notarization, LGPL/GPL depending on the build), or depend on Homebrew |
| Exotic formats (MKV, WebM, old codecs) | ❌ | ✅ |
| Loudness (EBU R128) | ❌ not built in | ✅ `ebur128` filter |

### Decision

- **Preview and export use AVFoundation.**
  - Video is composited by a custom `AVVideoCompositing` compositor written with Core Image +
    Metal.
  - Audio goes through `AVMutableAudioMix` plus offline processing.
- **Loudness is measured by an optional `audio.loudness` provider.** A libebur128 wrapper is a
  suitable implementation, but its library is not linked into the base app.
- **ffmpeg is optional.** It is detected by Doctor and used only to probe or transcode media that
  AVFoundation can't open; the transcode goes to ProRes Proxy on import.
- **`RenderEngine` is a protocol.** A second implementation (for example a headless ffmpeg batch
  exporter) can be added later without touching the UI.

### Engine components

| Component | Responsibility |
|---|---|
| `CompositionBuilder` | `Project` → `AVMutableComposition` (video/audio tracks, `insertTimeRange`, `scaleTimeRange` for speed) + `AVMutableVideoComposition` (per-segment instructions) + `AVMutableAudioMix`. Rebuilds ~50 ms after an edit (debounced) |
| `BashCutCompositor` | `AVVideoCompositing`. For each frame, in order: <br>1. source frame <br>2. transform (reframe, crop) <br>3. color (LUT + basic adjustments) <br>4. transition (whip/blink/zoom/dissolve… as Metal shaders or CI kernels) <br>5. Overlay items <br>6. text layers <br>7. output `CVPixelBuffer` |
| `TextRenderer` | Renders text with Core Text from `textStyles` (outline, shadow, Quinn serif, keyword sticker). Images are cached by `(text, style, size)`. Text animations (pop, word-by-word, typewriter) are evaluated from time |
| `AudioGraph` | Volume, fades, ducking. Speech regions (Speech clips + voiceover) become an envelope, which becomes volume ramps on the Music track. Stem separation uses Demucs output prepared ahead of time |
| `Loudness` | Optional two-pass export: <br>1. render a temporary mix <br>2. resolve and call `audio.loudness` <br>3. apply true-peak-safe master gain <br>4. export and verify through the same provider |
| `Exporter` | `AVAssetWriter` + VideoToolbox. Presets are listed in `01-ui-ux.md` §6. The queue is an `actor` that supports cancellation and reports progress |
| `ProxyManager` | Heavy footage (4K, HEVC 10-bit) gets a proxy (ProRes Proxy or H.264 540p) in `.bashcut/proxies/`. Preview uses the proxy; export uses the original |

**Biggest risk:** compositor and timeline performance. It is measured first, in M0
(`09-roadmap.md`). The targets are:

- smooth 1080×1920 playback at 29.97 fps from original footage;
- scrub latency under 100 ms.

## 3. Code layers

Code is organized by layer first, then by domain.

| Layer | Contains | Rules |
|---|---|---|
| `Packages/BashCutCore` | `BashCutProject` (model, `EditOperation`, validation, history and review), `BashCutPlugin` (manifest, discovery, provider resolution and process RPC), `BashCutImport` and `BashCutInterchange` | Pure logic. No AppKit or AVFoundation. Tested with `swift test` |
| `BashCut/Core/` | Document, Engine, Storage, Agent and Automation | MainActor integration stays in Document; replaceable engines and transports sit behind protocols |
| `BashCut/Models/` | App-only types: UI state, selection, playhead | `Sendable` |
| `BashCut/ViewModels/` | `@MainActor @Observable final class` | Split large ones into `Name+Feature.swift` |
| `BashCut/Views/` | SwiftUI + AppKit (timeline, viewer) | Never call services directly |

Dependency injection goes through one composition root: `AppServices.live` bundles the services and view models
receive them.

BashCut targets **macOS 14+** in order to use `@Observable` instead of
`ObservableObject`.

### Timeline UI

The timeline can hold hundreds of items plus waveforms and thumbnails, so it is **not built from
SwiftUI views**. It is a custom layer-backed `NSView` (or `MTKView`):

- only the visible range is drawn;
- thumbnails and waveforms are cached per zoom level;
- hit-testing is custom.

SwiftUI is used only for track headers, the toolbar and popovers.

## 4. `EditOperation`

```swift
enum EditOperation: Codable, Sendable {
    case insert(track: TrackID, item: Item)                  // E / Q, agent insert
    case delete(item: ItemID, ripple: Bool)
    case split(item: ItemID, atFrame: Int)
    case trim(item: ItemID, edge: Edge, toFrame: Int, ripple: Bool)
    case move(item: ItemID, toTrack: TrackID, atFrame: Int)
    case setProperties(item: ItemID, patch: JSONValue)       // transform, speed, volume, color, text, style…
    case addTransition(Transition), removeTransition(TransitionID)
    case setMarkers([Marker]), setBeatGrid(BeatGrid?)
    case group(label: String, author: Author, ops: [EditOperation])   // one undo step
}

enum Author: String, Codable, Sendable { case user, claude, codex, external }
```

How it behaves:

- **`apply` is a pure function** in the package. It returns the new `Project` together with the
  inverse operation (for undo).
- **It can also fail with a reason:** unknown item, trim past the end of the source, or overlap on
  a track that doesn't allow it.
- **Each successful `apply` increments `rev`.**
- **Agent requests carry a `baseRev`.** If it doesn't match the current `rev`, the request is
  rejected with `staleRevision`. The agent then re-reads the timeline and retries.

## 5. Tools

### Optional plugin boundary

BashCut uses plugins for optional features with large or fast-moving dependencies. The timeline,
project schema, history, compositor contract and normal export stay in the app so every project
can always be opened and edited. Transcription, stem separation, beat analysis, voice providers,
stock-media sources and additional interchange exporters run as child processes.

Each plugin is a folder with a `bashcut.plugin/1` `plugin.json`, an executable entrypoint, stable
capability IDs and dependency records. Dependency probes and install recipes are argv arrays, not
shell strings. Project plugins override user plugins, which override bundled plugins. Duplicate or
malformed manifests are isolated and reported without preventing the editor from launching.

The Plugins UI shows capabilities, dependency names, estimated downloads and exact commands before
installation. Copying a plugin and running its dependency recipes requires explicit approval. No
third-party Swift bundle is loaded into the app process. A crash therefore takes down only the
provider process. Native feature panels use this resolver now; matching CLI/MCP commands must reuse
the same capability contract as they are added.

Feature code resolves a capability such as `voice.synthesize`; it never imports or names a vendor
SDK. A plugin can declare several provider IDs for a capability. Resolution uses the project
preference, then an optional user default, then the highest-priority healthy provider. The current
feature panels persist the project preference; a Settings UI for user-wide provider defaults is
still pending. Project preferences are ordinary undoable data. Generated media stores the provider
ID and version as provenance, but remains usable if that provider is later removed. Replacing a
voice, transcription, beat or loudness provider therefore does not migrate the timeline.

The implemented process protocol starts one child for one request as `entrypoint rpc`, writes one
bounded JSON request to stdin and accepts one bounded JSON response on stdout. Calls default to a
120-second timeout and support task cancellation. Runtime children receive only a filtered
environment (`HOME`, `PATH`, `TMPDIR`, locale values and `BASHCUT_PLUGIN_*` metadata); automation
tokens, model credentials and arbitrary `.env` values are not inherited. Returned media paths are
confined to the per-request output directory and validated before insertion. See
[`../plugin-api.md`](../plugin-api.md) for the manifest and wire contract.

| Capability | Implemented consumer and validated result | Provider examples |
|---|---|---|
| `voice.synthesize` | Voice panel requests 1–8 takes, validates audio, scores missing provider scores by pacing and inserts one take with provenance | VieNeu-TTS wrapper, local native voice model, remote voice API |
| `captions.transcribe` | Text panel accepts confined UTF-8 SRT up to 4 MiB and imports it as one undoable edit | WhisperKit wrapper, workspace whisper venv, remote transcription API |
| `audio.beats` | Audio panel validates BPM and increasing source seconds, then maps them through trim/speed to integer timeline frames | workspace beat script, future vDSP detector |
| `audio.loudness` | Export validates LUFS/true peak/LRA, performs target-LUFS gain with a −1 dBTP ceiling and verifies the final file | libebur128 wrapper, compatible analyzer |

Direct voice recording, thumbnails, media metadata, waveforms, project editing, composition and
normal export stay native because they are core editor behavior or already covered well by Apple
frameworks. Stem separation, voice enrollment, stock sources, richer analysis and extra
interchange providers can adopt the same process boundary later.

Plugins are discovered in this order, with earlier entries winning duplicate IDs:

1. `<project>/.bashcut/plugins/`;
2. `~/Library/Application Support/BashCut/Plugins/`;
3. the app bundle's built-in PlugIns directory.

A malformed plugin or failed dependency probe becomes a diagnostic/degraded provider; it does not
prevent the project from opening. Dependency probes and install recipes are structured executable
plus argument arrays. The installer stages and validates a selected folder, displays every recipe,
runs it only after approval, then publishes the plugin atomically into the user catalog. Signed
remote catalogs and detailed per-capability permissions are not implemented yet.

## 6. Automation server

The app listens on a **Unix domain socket** at
`~/Library/Application Support/BashCut/automation.sock`, with permissions `0600`. The protocol is
newline-delimited JSON-RPC 2.0, with types in `BashCutWire`.

**Why a socket instead of HTTP:**

- no port is opened;
- filesystem permissions already restrict access to the user;
- no HTTP server dependency is needed.

**Two thin clients connect to it:**

| Client | Built with | Used by |
|---|---|---|
| `bashcut` CLI | swift-argument-parser | Bash inside agent tabs, scripts, the user. Installed as a `/usr/local/bin/bashcut` shim pointing into the bundle |
| `bashcut-mcp` | official MCP Swift SDK (stdio server transport) | `claude` / `codex` spawn it as an MCP server and forward each tool call to the socket |

**Command registry.** Both clients go through one `CommandRegistry` in the app. Each command
declares:

- an input schema;
- a mode: `read`, `ui`, `edit` or `privileged`;
- a `@MainActor` handler.

**Session tokens.** Each agent tab gets its own token in the env (`BASHCUT_SESSION_TOKEN`). The
token identifies the author (claude / codex / which tab) and is revoked when the tab closes.

The full command list is in `05-agent-integration.md`.

## 7. Interchange: exporters beyond video

```swift
protocol TimelineExporter: Sendable {
    var id: String { get }                                   // "otio", "resolve"
    func plan(_ project: Project) throws -> ExportPlan       // pure: what will be created, what needs pre-rendering
    func run(_ plan: ExportPlan, progress: ProgressSink) async throws -> ExportReceipt
}
```

| Exporter | Status | How |
|---|---|---|
| Video (`RenderEngine`) | v0.1 | §2 |
| `.srt` captions | v0.1 | from the Captions track |
| OTIO | later (P2) | write the OTIO JSON directly (no library). Media references the originals |
| **Resolve** | **later, reserved** | see below |

### How "Apply to Resolve" will work (not built in v1)

1. **`plan`** classifies every property.
   - *Native in Resolve Free:* cut, transform, opacity, LUT, markers, clip color.
   - *Rendered by BashCut:* captions and animated overlays → one ProRes 4444 alpha overlay;
     transitions and speed changes → pre-rendered clips; volume and ducking → four premixed
     stems.
   - The UI shows the plan before anything runs.
2. **BashCut renders the needed artifacts** into `projects/<video>/resolve-media/b<HHMMSS>/`.
3. **BashCut writes a task file** and runs it through the workspace bridge:
   `tools/.venvs/resolve-mcp/bin/python tools/editor-skills/nolan-resolve-bridge/bridge_run.py <task> <out.json> --project <name>`.
   - The task uses `AppendToTimeline` with `trackIndex` + `recordFrame`.
   - Exit codes 2/3/4 are mapped to GUI instructions: start `resolve_bridge`, click **Not Yet**,
     or switch project.
4. **The receipt** stores Resolve IDs in each item's `interop.resolve`, along with verification
   numbers: clips per track, offline count, V1 gaps, duration.

No dependency is needed for this. It reuses the workspace bridge, and the data rules in
`02-project-format.md` §5 keep it possible.

## 8. Concurrency and security

**Concurrency:**

- Swift 6 language mode.
- `@MainActor` for UI and `ProjectDocument`.
- `actor`s for the export queue, tools, automation server, PTY sessions, proxies, the FSEvents
  watcher and exporters.
- Log and progress streams use `AsyncThrowingStream`; cancellation uses
  `withTaskCancellationHandler`.
- The compositor runs on AVFoundation's own queue. It only reads an immutable `Project` snapshot
  (a value type) and never touches `@MainActor`.

**Security:**

- The app is not sandboxed but uses hardened runtime. It has to spawn CLIs and read the
  workspace.
- The automation socket is `0600`, and per-session tokens are required for `edit` and
  `privileged` commands.
- Logs use `privacy: .private` by default. `.env` contents and keys are never logged.
