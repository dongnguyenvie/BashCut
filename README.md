# BashCut

Native macOS video editor with a shared AVFoundation preview/export engine. This repository contains a working M0 foundation and partial M1/M2 editor and agent features. The complete editor in [the specs](docs/specs/README.md) is still under development.

## Related repositories

Two other repositories are part of BashCut. Contributions are welcome in each:

| Repository | What it holds | Contribute there |
|---|---|---|
| [bashcut-plugins](https://github.com/dongnguyenvie/bashcut-plugins) | The plugin registry (`registry.json`) and its plugins, such as Silence Markers and VieNeu TTS | New plugins and fixes to existing ones. See [Writing plugins](docs/guides/plugins.md) |
| [bashcut-agent-kit](https://github.com/dongnguyenvie/bashcut-agent-kit) | Editing skills for Claude Code and Codex (footage survey, beat cuts, audio mix, captions, colour, effects, voiceover…). BashCut ships them and loads them in its agent tabs | Editing know-how that agents should follow. See its README › Writing skills |

Changes to the editor itself, its commands and the plugin API belong in this repository.

## Run

Requires macOS 14+, Xcode with Swift 6, and network access for the first package resolution.

```sh
scripts/run.sh
```

This builds with SwiftPM, packages a local `build/BashCut.app`, signs it with the first Apple Development identity in your keychain (or `BASHCUT_SIGN_IDENTITY`) so macOS keeps folder-access grants across rebuilds, and opens it. New creates a project JSON at the chosen location. Import footage appends original-media references to Main without copying or modifying the footage. Select a clip in the timeline, seek, split/trim/delete, adjust zoom, or add/edit a caption. Save and export are explicit. Autosave stores a recoverable copy every 30 seconds and when the app loses focus; undo/redo history is restored on reopen. External edits reload when clean or show conflict controls when dirty. Export writes a new H.264 MP4 with source audio and burned-in captions; existing files are never overwritten.

The native layout follows `mockups/bashcut-ui.html`: eight library tabs, viewer/source viewer, Inspector, a scrollable timeline and the agent dock. Click a media thumbnail to preview it, set In/Out, then Insert or Overwrite at the timeline playhead. Text presets, color controls, volume/fades, source-aligned waveforms, basic review and history are functional; tabs explicitly identify advanced features still in development.

The dock launches real Claude, Codex or Shell terminals (with your CLI login; Codex also takes `OPENAI_API_KEY`). See [automation](docs/guides/automation.md). The app executable is `BashCutApp` and the bundled CLI is `bashcut`, avoiding a name collision on case-insensitive disks.

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

See [implementation status](docs/status/implementation.md) for acceptance results and remaining work. See the [docs index](docs/README.md) for guides, reference and design specs, and [CONTRIBUTING.md](CONTRIBUTING.md) for the build layout and one-file templates (agent providers, model adapters, commands, capabilities, timeline formats).
