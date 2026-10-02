# 04 — Dependencies

## Policy

- **Apple frameworks first.** A third-party package needs a reason that a system framework can't
  cover in a reasonable amount of code.
- **Permissive licenses only** in anything linked or shipped: MIT, Apache-2.0, BSD. No GPL code
  in the bundle.
- **Pin versions.** Use `from:` ranges in `project.yml` / `Package.swift`, and commit
  `Package.resolved`. Upgrade on purpose, one package per commit, with the CHANGELOG noting it.
- **Keep a list.** Every dependency appears in `docs/THIRD_PARTY.md` and in the About window,
  with its license.
- **Tools are not dependencies.** Anything spawned as a process (ffmpeg, workspace venvs,
  `claude`, `codex`) is detected by Doctor at runtime, never linked, and the app degrades
  gracefully without it.

## Apple frameworks (no package needed)

| Framework | Used for |
|---|---|
| AppKit, SwiftUI, Observation | app lifecycle, windows, panels, `@Observable` view models |
| AVFoundation, AVKit | composition, playback, export (`AVAssetWriter`), reading PCM (`AVAssetReader`), thumbnails |
| Core Image, Metal, MetalKit | compositor: transforms, LUTs (`CIColorCube`), transitions, blur |
| Core Text, Core Graphics | captions and text overlays |
| VideoToolbox | hardware H.264/HEVC/ProRes encode |
| Accelerate (vDSP, vImage) | waveforms, audio envelopes for ducking, frame differencing for static-clip detection, later a native beat detector |
| Vision | face rectangles so stickers and captions avoid faces, and face-aware reframing. The workspace already does this with `graphics/tools/faces.swift` (`VNDetectFaceRectanglesRequest`) |
| AVFAudio (`AVAudioEngine`) | recording voiceover directly into the Voiceover track (P2); live audio meters |
| CoreServices (FSEvents) | watching `project.bashcut.json` and media folders |
| UniformTypeIdentifiers | drag & drop, import panels |
| OSLog | logging, signposts for engine performance |
| Swift Testing, XCTest | unit tests; UI and performance tests |

## Adopt

| Package | Purpose | License | Linked into | Needed from |
|---|---|---|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulator + PTY (`LocalProcessTerminalView`) for the agent dock | MIT | `BashCut` | M2 |
| [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) (official) | stdio MCP server inside `bashcut-mcp`, so Claude and Codex can call BashCut tools | MIT | `bashcut-mcp` | M2 |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | the `bashcut` CLI | Apache-2.0 | `bashcut` | M2 |
| [swift-collections](https://github.com/apple/swift-collections) | `OrderedDictionary` for stable key order while preserving unknown JSON fields; `Deque` for the undo journal | Apache-2.0 | `BashCutCore` | M0 |
| [swift-async-algorithms](https://github.com/apple/swift-async-algorithms) | `debounce` for composition rebuilds, `merge` / `throttle` for progress and log streams | Apache-2.0 | `BashCut`, `BashCutCore` | M1 |
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | on-device speech-to-text with word timestamps for Auto Captions, transcript search and take scoring. macOS 14+. It removes the need for the `mlx-whisper` Python dependency inside the app | MIT | `BashCut` | M3 |
| [libebur128](https://github.com/jiixyj/libebur128) (vendored C, SwiftPM C target `CEBUR128`) | EBU R128 loudness (integrated, true peak, LRA) for −14 LUFS normalization and post-export numbers, without ffmpeg | MIT | `BashCutCore` | M4 |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | golden-frame tests for the compositor, snapshot tests for the timeline text form and the OTIO/Resolve plans | MIT | tests only | M0 |

That makes six runtime packages and one vendored C library. The rest of the app is first-party
code.

## Later / optional

| Package | When | Why |
|---|---|---|
| [Sparkle](https://github.com/sparkle-project/Sparkle) (MIT) | only if BashCut is distributed (M6) | auto-update with EdDSA-signed appcast |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT) | P2 | user-customizable shortcuts |
| [FlyingFox](https://github.com/swhitty/FlyingFox) | only if an HTTP transport is ever needed (e.g. remote control from another machine) | lightweight async HTTP server; **license to be verified** before adoption |
| [swift-markdown](https://github.com/swiftlang/swift-markdown) (Apache-2.0) | only if an in-app viewer for memos and `SKILL.md` returns | parsing; for display, the built-in `AttributedString(markdown:)` comes first |

## Fonts

Caption presets need fonts with full Vietnamese coverage (ă â đ ê ô ơ ư + all tone marks).

| Option | Use | License |
|---|---|---|
| **System fonts (default in v1)**: Arial Bold for Bold Outline, Times New Roman for Cinematic Serif, Apple Color Emoji | Same look as the workspace's current `make_overlay.py` / `render_overlay.py`. Referenced through Core Text, **never bundled** | Ships with macOS; not redistributable, which doesn't matter while they aren't bundled |
| **Bundled OFL fonts (only if BashCut is distributed)**: e.g. Be Vietnam Pro (sans, designed for Vietnamese) and a Vietnamese-capable serif such as Lora or Playfair Display | Consistent look on any Mac | SIL Open Font License 1.1: bundling allowed; license file shipped in `Resources/Fonts/` |

Users can pick any installed font in the Inspector. A preset stores the font's PostScript name;
if that font is missing, the app falls back to the default and shows a warning.

## External tools (spawned, never linked)

| Tool | Required? | Used for | If missing |
|---|---|---|---|
| `claude` (Claude Code CLI) | for the agent dock | Claude tabs | tab disabled, install hint |
| `codex` (Codex CLI) | for the agent dock | Codex tabs | tab disabled, install hint |
| `ffmpeg` / `ffprobe` (Homebrew) | optional | probing and transcoding formats AVFoundation can't read | those files are marked unsupported |
| Workspace `tools/.venvs/vieneu` (VieNeu-TTS) | optional | Voice tab: generate, clone | Voice tab shows the install command |
| Workspace `tools/.venvs/demucs` | optional | stem separation | button disabled |
| Workspace `beatgrid.py` (+ python3 with numpy) | optional | Detect Beats | button disabled |
| XcodeGen, SwiftLint | dev only | project generation, lint | — |

BashCut never bundles an ffmpeg binary. If one is ever needed, it would be an LGPL-only dynamic
build, signed, with the license shipped next to it. That is a separate decision.

## Considered and rejected

| Option | Reason |
|---|---|
| ffmpeg as the render engine (CLI or libav* bindings) | preview and export would come from different engines; Homebrew build lacks libass/freetype; bundling and licensing burden. See `03-architecture.md` §2 |
| Vapor / Hummingbird / any HTTP framework | automation is a local Unix socket; an HTTP stack is unnecessary weight |
| Hand-rolled MCP protocol | the official Swift SDK now covers the stdio server; less code to maintain |
| mlx-whisper (Python) inside the app | WhisperKit is native and needs no venv. The workspace scripts may keep using mlx-whisper |
| aubio for beat detection | GPL |
| Core Data / GRDB / Realm | a project is one JSON document; no database needed |
| OpenTimelineIO C++ / Swift bindings | OTIO is JSON; writing it directly is simpler than a C++ dependency |
| Electron / web views for any panel | violates the native-only principle |
| Third-party video engines / GPUImage-style frameworks | AVFoundation + Core Image + Metal cover the needs |

## To verify before adopting

- **WhisperKit:** Vietnamese accuracy compared with `mlx-whisper large-v3-turbo` on Nolan's
  footage (noisy street food scenes). Also model size and first-run download time.
- **MCP Swift SDK:** the stdio server API at the pinned version, and that tool-call cancellation
  propagates.
- **SwiftTerm:** that `LocalProcessTerminalView` handles the Claude and Codex TUIs correctly
  (alternate screen, mouse reporting, bracketed paste for the context block).
- **FlyingFox license** (only if it is ever adopted).
- **Fonts:** before bundling, confirm the exact OFL fonts render every Vietnamese tone mark
  correctly with outline and shadow in Core Text. Golden tests cover this.
