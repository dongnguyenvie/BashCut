# Plugin process API

BashCut plugins provide optional, replaceable implementations for capabilities such as voice synthesis, transcription, beat analysis and interchange. Project data, timeline validation, undo history and rendering stay in the app. A missing plugin therefore does not prevent a project from opening.

## Bundle layout

A plugin is a directory containing `plugin.json` and an executable entrypoint. Its manifest uses schema `bashcut.plugin/1` and API version `1`.

```text
example.plugin/
├── plugin.json
└── bin/provider
```

The entrypoint must be relative to the bundle and executable. Project plugins override user plugins, which override bundled plugins. Capabilities and provider IDs are stable strings; feature code resolves those IDs rather than importing a vendor SDK.

## Request lifecycle

BashCut starts one child process for each call:

```text
bin/provider rpc
```

It writes one JSON request followed by a newline to standard input. The process writes exactly one JSON response to standard output and exits successfully. Diagnostic output belongs on standard error.

```json
{
  "id": "D0B15F12-9FC0-4E69-9FB2-D99B3124AA44",
  "apiVersion": 1,
  "method": "voice.synthesize",
  "provider": "example.voice.local",
  "params": {
    "text": "Xin chào",
    "language": "vi"
  }
}
```

A successful response carries the same `id` and any JSON value in `result`:

```json
{
  "id": "D0B15F12-9FC0-4E69-9FB2-D99B3124AA44",
  "result": {
    "audioPath": "/absolute/path/to/generated.wav"
  }
}
```

A failed response carries a stable machine-readable code and a message:

```json
{
  "id": "D0B15F12-9FC0-4E69-9FB2-D99B3124AA44",
  "error": {
    "code": "model_missing",
    "message": "Install the Vietnamese voice model"
  }
}
```

Methods use lower-case dot or hyphen separated identifiers. Requests are limited to 1 MiB. Responses default to an 8 MiB limit and calls default to a 120 second timeout. BashCut rejects malformed JSON, mismatched response IDs, empty responses, oversized output, nonzero exits and timeouts.

`voice.synthesize` receives `text`, `language`, `outputDirectory`, `takeCount` and `takeOffset`. A provider can return the legacy `audioPath`, or `takes` containing one to eight `{audioPath, score?}` objects. Scores use `0...1`; when absent, BashCut derives a pacing score from text length and rendered duration. A legacy single-output provider is called again until the requested take count is filled. `captions.transcribe` receives `mediaPath`, `language` and `outputDirectory`, then returns `srtPath`. Returned paths may be absolute or relative to `outputDirectory`, but must resolve inside the unique request directory. The app rejects symlink escapes, missing files, duplicate take paths, invalid audio and malformed or oversized UTF-8 SRT output. `audio.beats` receives `mediaPath` and returns `bpm` plus a strictly increasing `beatsSeconds` array. BashCut maps source seconds through each timeline item's trim and speed into integer project frames.

`audio.loudness` receives `mediaPath` for a rendered mix and returns `integratedLUFS`, `truePeakDbTP` and optional `loudnessRangeLU`. BashCut validates finite bounded values. During normalized export it renders a temporary mix, asks the provider to measure it, applies gain toward the project target while keeping true peak at or below −1 dBTP, exports again, and measures the final file. The selected mix gain and measurement provenance are stored through an undoable project edit. Providers can wrap libebur128, FFmpeg filters or another implementation without linking that dependency into the app.

## Process environment

Plugin processes receive only `HOME`, `PATH`, `TMPDIR`, `LANG` and `LC_ALL` when those values exist, plus:

- `BASHCUT_PLUGIN_ID`
- `BASHCUT_PLUGIN_DIR`
- `BASHCUT_PLUGIN_API_VERSION`

The runner does not copy arbitrary app environment variables, credentials, the automation socket or its session token. Provider-specific credentials should be supplied through an explicit future permission and credential contract instead of ambient environment access.

## Dependencies and health

Each manifest dependency declares a probe as an executable plus an argument array. A path containing `/` must be relative and stay inside the plugin bundle. A bare executable name is resolved through `/usr/bin/env` using the filtered `PATH`. Shell strings, path traversal and NUL bytes are rejected.

The Plugins panel runs these probes on demand. A successful zero exit marks a dependency available. A failed probe is shown as missing when the manifest has an install recipe, or failed when it does not. Install recipes remain reviewable argv arrays and require the existing installer approval flow.

## Current boundary

The runtime, discovery, provider resolution and health checks are implemented. Voice, Text, Audio and Export invoke `voice.synthesize`, `captions.transcribe`, `audio.beats` and `audio.loudness`. Other analysis and interchange panels are not connected yet. Signed remote catalogs and detailed capability permissions remain future work.
