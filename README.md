# BashCut

Native macOS video editor with a shared AVFoundation preview/export engine. This repository contains a working M0 foundation and partial M1/M2 editor and agent features. The complete editor in [the specs](docs/specs/README.md) is still under development.

## Run

Requires macOS 14+, Xcode with Swift 6, and network access for the first package resolution.

```sh
scripts/run.sh
```

This builds with SwiftPM, packages a local `build/BashCut.app`, signs it with the first Apple Development identity in your keychain (or `BASHCUT_SIGN_IDENTITY`) so macOS keeps folder-access grants across rebuilds, and opens it. New creates a project JSON at the chosen location. Import footage appends original-media references to Main without copying or modifying the footage. Select a clip in the timeline, seek, split/trim/delete, adjust zoom, or add/edit a caption. Save and export are explicit. Autosave stores a recoverable copy every 30 seconds and when the app loses focus; undo/redo history is restored on reopen. External edits reload when clean or show conflict controls when dirty. Export writes a new H.264 MP4 with source audio and burned-in captions; existing files are never overwritten.

The native layout follows `mockups/bashcut-ui.html`: eight library tabs, viewer/source viewer, Inspector, a scrollable timeline and the agent dock. Click a media thumbnail to preview it, set In/Out, then Insert or Overwrite at the timeline playhead. Text presets, color controls, volume/fades, source-aligned waveforms, basic review and history are functional; tabs explicitly identify advanced features still in development.

The dock launches real Claude, Codex or Shell terminals. It also accepts model APIs to generate editable Python/Shell scripts or undoable timeline proposals. See [automation and API setup](docs/automation.md). The app executable is `BashCutApp` and the bundled CLI is `bashcut`, avoiding a name collision on case-insensitive disks.

For Xcode, install XcodeGen >= 2.46, then run `scripts/generate-project.sh` and open `BashCut.xcodeproj`. Xcode builds the string catalog; the SwiftPM launcher copies equivalent `.strings` resources. Localization follows the system language in this milestone.

## Verify

```sh
Fixtures/make-media.sh       # requires ffmpeg; generated media is ignored
scripts/verify.sh build
scripts/verify.sh test
scripts/verify.sh perf       # 20 synthetic clips, ~30 seconds, 1080×1920
scripts/verify.sh lint       # requires SwiftLint
scripts/verify.sh xcode test # regenerates and tests the Xcode project (requires XcodeGen)
```

Pure model tests also run independently with `cd Packages/BashCutCore && swift test`. Tests never use the real video workspace or agent CLIs. Package downloads happen at dependency resolution, not in tests.

See [implementation status](docs/implementation-status.md) for acceptance results and remaining work. See [extension boundaries](docs/extension-boundaries.md) for the modular design and [CONTRIBUTING.md](CONTRIBUTING.md) for the build layout and one-file templates (agent providers, model adapters, commands, capabilities, timeline formats).
