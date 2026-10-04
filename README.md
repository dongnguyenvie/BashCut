<p align="center">
  <img src=".github/assets/logo.png" width="128" height="128" alt="BashCut">
</p>

<h1 align="center">BashCut</h1>

<p align="center">
  A native macOS video editor that coding agents can drive.<br>
  Everything the UI does, Claude Code and Codex can do through the <code>bashcut</code> CLI or MCP.
</p>

<p align="center">
  <a href="https://github.com/dongnguyenvie/BashCut/releases/latest">Download</a> ·
  <a href="https://testflight.apple.com/join/XwsNZxre">TestFlight beta</a> ·
  <a href="docs/README.md">Docs</a> ·
  <a href="docs/guides/automation.md">Automation</a> ·
  <a href="docs/guides/plugins.md">Plugins</a> ·
  <a href="https://github.com/dongnguyenvie/bashcut-agent-kit">Agent kit</a> ·
  <a href="https://github.com/dongnguyenvie/BashCut/issues">Issues</a>
</p>

<p align="center">
  <a href="README.vi.md">Tiếng Việt</a>
</p>

---

<p align="center">
  <img alt="BashCut editing the sample project: media library, viewer with picture in picture and a caption, Inspector, layered timeline and the agent dock" src=".github/assets/app.png" width="800">
</p>

## About

BashCut is a native macOS video editor built on AVFoundation, with a Claude Code / Codex terminal docked beside the
timeline. Preview and export share one composition engine, so what you see is what you export. Projects are
plain JSON next to your footage: agents and scripts read and edit them through the same atomic, undoable edit
operations the UI uses.

BashCut is under active development: the M0 foundation is accepted on real footage and most of the editor and
agent features (M1–M3, M5) are in place. See [implementation status](docs/status/implementation.md) for what is
verified and what is left.

## What's inside

- Layered timeline: linked audio, sections, snapping, beat grid, split/trim/move, gaps, freeze frames, constant
  speed and ramps, keyframes, transitions
- Viewer and source viewer with In/Out, Insert/Overwrite, safe area and compare
- Captions and text with presets, SRT import, Vietnamese and English
- Color: LUTs, exposure, contrast, saturation and adjustment layers
- Audio: volume, fades, ducking under speech, loudness, voiceover recording, source-aligned waveforms
- Review checks, history, autosave with recovery, external-change reload and conflict handling
- H.264 export queue with burned-in captions; OTIO export
- Agent dock with real Claude, Codex and Shell terminals, plus the
  [agent kit](https://github.com/dongnguyenvie/bashcut-agent-kit) of editing skills
- `bashcut` CLI and MCP server: every UI action and dialog, with dry runs and revision checks
- Out-of-process plugins for transcription, voice, beats and loudness, from the
  [plugin registry](https://github.com/dongnguyenvie/bashcut-plugins)

## Install

Requires macOS 14 or later.

### Homebrew

```sh
brew install --cask dongnguyenvie/tap/bashcut
```

This installs `BashCut.app` into `/Applications` and links the `bashcut` CLI and `bashcut-mcp` server into
Homebrew's `bin`, so agents in any terminal can drive the app. Update with `brew upgrade --cask bashcut`; remove
with `brew uninstall --cask bashcut` (add `--zap` to also delete settings and caches).

### Download a release

Download `BashCut-<version>.dmg` (or `.zip`) from the [latest release](https://github.com/dongnguyenvie/BashCut/releases/latest),
open it and drag BashCut to Applications. Builds are signed with Developer ID and notarized by Apple; check a download
against the release's `SHA256SUMS` with `shasum -a 256 -c --ignore-missing SHA256SUMS`. To use the CLI from a terminal, link it yourself:

```sh
sudo ln -s /Applications/BashCut.app/Contents/MacOS/bashcut /usr/local/bin/bashcut
sudo ln -s /Applications/BashCut.app/Contents/MacOS/bashcut-mcp /usr/local/bin/bashcut-mcp
```

### TestFlight

Join the public beta on [TestFlight](https://testflight.apple.com/join/XwsNZxre) (needs the TestFlight app). The
TestFlight build is the sandboxed Mac App Store build: it runs only the plugins bundled with the app, and its
bundled CLI cannot run from a regular terminal.

Or build BashCut from source, below.

## How to Build

Requires macOS 14+, Xcode with Swift 6, and network access for the first package resolution.

```sh
scripts/run.sh
```

This builds with SwiftPM, packages `build/BashCut.app`, signs it with the first Apple Development identity in
your keychain (or `BASHCUT_SIGN_IDENTITY`) so macOS keeps folder-access grants across rebuilds, and opens it. The
app executable is `BashCutApp` and the bundled CLI is `bashcut`, avoiding a name collision on case-insensitive
disks.

To try a change against every timeline case, generate the [sample project](docs/guides/sample-project.md) shown
above (needs `ffmpeg`):

```sh
scripts/sample-project.py
```

For Xcode, install XcodeGen >= 2.46, then run `scripts/generate-project.sh` and open `BashCut.xcodeproj`
(generated from `project.yml`). Xcode builds the string catalog; the SwiftPM launcher copies equivalent `.strings`
resources. The UI follows the system language.

## Verify

```sh
scripts/verify.sh build
scripts/verify.sh test
scripts/verify.sh perf       # 20 synthetic clips, ~30 seconds, 1080×1920
scripts/verify.sh lint       # requires SwiftLint
scripts/verify.sh xcode test # regenerates and tests the Xcode project (requires XcodeGen)
```

Pure model tests also run on their own with `cd Packages/BashCutCore && swift test`. Tests never use the real
video workspace or agent CLIs, and package downloads happen at dependency resolution, not in tests.

## Related repositories

Two other repositories are part of BashCut. Contributions are welcome in each:

| Repository | What it holds | Contribute there |
|---|---|---|
| [bashcut-plugins](https://github.com/dongnguyenvie/bashcut-plugins) | The plugin registry (`registry.json`) and its plugins, such as Silence Markers and VieNeu TTS | New plugins and fixes to existing ones. See [Writing plugins](docs/guides/plugins.md) |
| [bashcut-agent-kit](https://github.com/dongnguyenvie/bashcut-agent-kit) | Editing skills for Claude Code and Codex (footage survey, beat cuts, audio mix, captions, colour, effects, voiceover…). BashCut ships them and loads them in its agent tabs | Editing know-how that agents should follow. See its README › Writing skills |

Changes to the editor itself, its commands and the plugin API belong in this repository.

## Documentation

- [Documentation index](docs/README.md): guides, reference and design specs
- [Automation: CLI and MCP](docs/guides/automation.md) and the generated
  [command reference](docs/reference/commands.md)
- [Project format](docs/reference/project-format.md)
- [Implementation status](docs/status/implementation.md)
- [CONTRIBUTING.md](CONTRIBUTING.md): build layout and one-file templates (agent providers, model adapters,
  commands, capabilities, timeline formats)
- [CHANGELOG.md](CHANGELOG.md)

## License

MIT. See [LICENSE](LICENSE).
