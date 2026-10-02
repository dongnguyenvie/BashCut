# 04 — Dependencies

The dependency policy, the Apple frameworks and Swift packages BashCut builds on, optional plugin dependencies,
external tools, and the options that were rejected. Exact versions and licenses of resolved packages are in
[Third-party dependencies](../reference/third-party.md).

## Policy

- **Apple frameworks first.** A third-party package needs a reason that a system framework cannot cover in a
  reasonable amount of code.
- **Permissive licenses only** in anything linked or shipped: MIT, Apache-2.0, BSD. No GPL code in the bundle.
- **Pin versions.** `Package.swift` uses `from:` ranges (the MCP SDK is pinned exactly) and both `Package.resolved`
  files are committed. `project.yml` mirrors the same requirements. Upgrade on purpose, one package per commit,
  with a CHANGELOG entry.
- **Keep a list.** Every dependency appears in [Third-party dependencies](../reference/third-party.md) with its
  license. **Planned:** the same list in the About window.
- **Plugin dependencies are optional.** Models, Python venvs, command-line analyzers and remote provider SDKs
  belong behind `bashcut.plugin/1`. They are probed at runtime and installed only after the user reviews the exact
  commands. Missing providers never prevent normal editing.
- **Tools are not linked dependencies.** Anything spawned as a process (`ffmpeg`, plugin entrypoints, `claude`,
  `codex`) is detected at runtime, and the app degrades gracefully without it.

## Apple frameworks (no package needed)

| Framework | Used for | Status |
|---|---|---|
| AppKit, SwiftUI, Observation | App lifecycle, windows, panels, the custom timeline view, `@Observable` models | **Implemented** |
| AVFoundation, AVKit | Composition, playback, export (`AVAssetReader` + `AVAssetWriter`), PCM reading, thumbnails, proxies | **Implemented** |
| Core Image | Compositor: transforms, color, LUTs (`CIColorCube`), transitions | **Implemented** |
| Core Text, Core Graphics | Captions and text overlays | **Implemented** |
| VideoToolbox (through AVFoundation) | Hardware H.264/HEVC/ProRes encode and decode | **Implemented** |
| AVFAudio | Direct voiceover recording with an input level meter | **Implemented** |
| Security, CryptoKit | Keychain storage for model API keys; hashing for cache keys | **Implemented** |
| Dispatch file-system sources | Watching the project folder for outside edits | **Implemented** |
| UniformTypeIdentifiers | Drag and drop, open and import panels | **Implemented** |
| OSLog | Unified-log mirror of the debug log | **Implemented** |
| Swift Testing | Unit and integration tests | **Implemented** |
| Metal, MetalKit | Custom transition kernels beyond Core Image's built-in filters | **Planned** |
| Accelerate (vDSP, vImage) | Native beat and loudness helpers (plugin platform step 2), frame differencing for static-clip detection | **Planned** |
| Vision | Face rectangles so stickers and captions avoid faces, and face-aware reframing. The workspace already does this with `graphics/tools/faces.swift` (`VNDetectFaceRectanglesRequest`) | **Planned** |
| AVFAudio (`AVAudioEngine`) | Live audio meters during playback | **Planned** |

## Adopted packages

| Package | Purpose | License | Linked into | Needed from |
|---|---|---|---|---|
| [swift-collections](https://github.com/apple/swift-collections) | `Deque` for the bounded undo/redo stacks (only `DequeModule` is linked). Stable JSON key order comes from sorted-key encoding, not `OrderedDictionary` | Apache-2.0 | `BashCutProject` | M0 |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | Golden-frame tests for the compositor. **Planned:** snapshot tests for the timeline text form and the OTIO/Resolve plans | MIT | Tests only | M0 |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulator + PTY (`LocalProcessTerminalView`) for the agent dock | MIT | `BashCut` | M2 |
| [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) (official) | stdio MCP server inside `bashcut-mcp`, so Claude and Codex can call BashCut tools | MIT, moving to Apache-2.0 | `bashcut-mcp` | M2 |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | The `bashcut` CLI | Apache-2.0 | `bashcut` | M2 |

The base app therefore links four runtime Swift packages; snapshot testing is test-only. WhisperKit, libebur128
and other provider-specific libraries are not linked into the base app.

## Optional plugin dependencies

| Candidate | Capability | Packaging rule |
|---|---|---|
| WhisperKit or a workspace Whisper implementation | `captions.transcribe` | Ship or install it inside a transcription plugin. Download its model only after the user chooses that provider |
| libebur128 or another EBU R128 analyzer | `audio.loudness` | Wrap it in an executable plugin that returns bounded LUFS, true peak and optional LRA values |
| VieNeu-TTS or another voice engine | `voice.synthesize` | The plugin owns its venv, model or API dependency and returns confined WAV takes |
| Existing beat scripts or a native helper executable | `audio.beats` | The plugin returns BPM and increasing source-time beat positions |
| Demucs | `audio.separate` (**Planned**) | Keep the model and Python environment outside the app; publish stems into a confined request folder |

The plugin manifest declares each dependency's kind (`executable`, `python`, `model` or `systemLibrary`), a health
probe, an optional reviewed install recipe and an optional estimated download size. Recipes are argv arrays, not
shell strings. Plugin processes receive a filtered environment. **Planned:** an explicit credential contract for
provider credentials; they must never depend on ambient `.env` variables.

## Later or optional

| Package | When | Why |
|---|---|---|
| [Sparkle](https://github.com/sparkle-project/Sparkle) (MIT) | Only if BashCut is distributed (M6) | Auto-update with an EdDSA-signed appcast |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT) | P2 | User-customizable shortcuts |
| [swift-async-algorithms](https://github.com/apple/swift-async-algorithms) (Apache-2.0) | Only if stream composition becomes clearer than the current tasks | Debounce and throttle progress without hand-written coordination |
| [FlyingFox](https://github.com/swhitty/FlyingFox) | Only if an HTTP transport is ever needed (for example remote control from another machine) | Lightweight async HTTP server. License **(to verify)** before adoption |
| [swift-markdown](https://github.com/swiftlang/swift-markdown) (Apache-2.0) | Only if an in-app viewer for memos and `SKILL.md` returns | Parsing; for display, the built-in `AttributedString(markdown:)` comes first |

## Fonts

Caption presets need fonts with full Vietnamese coverage (ă â đ ê ô ơ ư and all tone marks).

| Option | Use | License |
|---|---|---|
| **System fonts (default in v1):** Arial Bold for Bold Outline, Times New Roman for Cinematic Serif, Apple Color Emoji | Same look as the workspace's `make_overlay.py` / `render_overlay.py`. Referenced through Core Text, **never bundled** | Ships with macOS; not redistributable, which does not matter while they are not bundled |
| **Bundled OFL fonts (only if BashCut is distributed):** for example Be Vietnam Pro (sans, designed for Vietnamese) and a Vietnamese-capable serif such as Lora or Playfair Display | Consistent look on any Mac | SIL Open Font License 1.1: bundling allowed; license file shipped in `Resources/Fonts/` |

Users can pick any installed font in the Inspector. A preset stores the font's PostScript name; if that font is
missing, the app falls back to the default and shows a warning.

## External tools (spawned, never linked)

| Tool | Required? | Used for | If missing |
|---|---|---|---|
| `claude` (Claude Code CLI) | For the agent dock | Claude tabs | Tab disabled, install hint |
| `codex` (Codex CLI) | For the agent dock | Codex tabs | Tab disabled, install hint |
| `ffmpeg` / `ffprobe` (Homebrew) | Optional | **Planned:** probing and transcoding formats AVFoundation cannot read. Doctor already reports it | Those files are marked unsupported |
| Installed `bashcut.plugin/1` entrypoints | Optional | Voice, captions, beats, loudness and future capabilities | The feature disables itself; Plugins shows health and the install plan |
| Workspace `tools/.venvs/vieneu` (VieNeu-TTS) | Optional plugin dependency | A voice provider may wrap it | Provider is degraded until its reviewed recipe succeeds |
| Workspace `tools/.venvs/demucs` | Future plugin dependency | Stem separation | Capability unavailable |
| Workspace `beatgrid.py` (+ python3 with numpy) | Optional plugin dependency | A beat provider may wrap it | Capability unavailable |
| XcodeGen, SwiftLint | Development only | Project generation, lint (`--strict` is the lint authority) | `scripts/verify.sh` reports the tool as missing, never as a pass |

BashCut never bundles an ffmpeg binary. If one is ever needed, it would be an LGPL-only dynamic build, signed, with
the license shipped next to it. That is a separate decision.

## Considered and rejected

| Option | Reason |
|---|---|
| ffmpeg as the render engine (CLI or libav* bindings) | Preview and export would come from different engines; the Homebrew build lacks libass/freetype; bundling and licensing burden. See [03 — Architecture](03-architecture.md) §2 |
| Vapor, Hummingbird or any HTTP framework | Automation is a local Unix socket; an HTTP stack is unnecessary weight |
| A hand-rolled MCP protocol | The official Swift SDK covers the stdio server; less code to maintain |
| Any transcription engine linked into the base app | Models and fast-moving runtimes belong in replaceable transcription plugins |
| aubio for beat detection | GPL |
| Core Data, GRDB or Realm | A project is one JSON document; no database is needed |
| OpenTimelineIO C++ or Swift bindings | OTIO is JSON; writing it directly is simpler than a C++ dependency |
| Electron or web views for any panel | Violates the native-only principle |
| Third-party video engines or GPUImage-style frameworks | AVFoundation and Core Image cover the needs |

## Open checks

- **WhisperKit (to verify):** Vietnamese accuracy compared with `mlx-whisper large-v3-turbo` on Nolan's footage
  (noisy street-food scenes), model size and first-run download time.
- **MCP Swift SDK (to verify):** that tool-call cancellation propagates from the agent through `bashcut-mcp` to the
  running command at the pinned 0.12.1.
- **SwiftTerm (to verify):** that `LocalProcessTerminalView` handles the Claude and Codex TUIs fully (alternate
  screen, mouse reporting, bracketed paste for the context block).
- **FlyingFox license (to verify),** only if it is ever adopted.
- **Fonts (to verify):** before bundling, confirm the chosen OFL fonts render every Vietnamese tone mark correctly
  with outline and shadow in Core Text. Golden tests cover this.
