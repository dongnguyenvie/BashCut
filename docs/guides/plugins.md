# Writing plugins

Plugins give BashCut optional, replaceable implementations of capabilities such as voice synthesis,
transcription, beat detection and loudness analysis. A plugin is a separate executable that BashCut starts for
each request; no third-party code is loaded into the app process. Project data, timeline validation, undo
history and rendering stay in the app, so a missing plugin never prevents a project from opening. The design
behind this boundary is in [03 — Architecture](../specs/03-architecture.md#optional-plugin-boundary).

## Quick start

A plugin is a folder with a `plugin.json` manifest and an executable entrypoint:

```text
example.voice.plugin/
├── plugin.json
└── bin/provider
```

```json
{
  "schema": "bashcut.plugin/1",
  "id": "example.voice",
  "name": "Example Voice",
  "version": "1.0.0",
  "apiVersion": 1,
  "entrypoint": "bin/provider",
  "capabilities": ["voice.synthesize"],
  "providers": [
    {"id": "example.voice.local", "capability": "voice.synthesize", "name": "Example local voice", "priority": 10}
  ],
  "dependencies": [
    {
      "id": "python",
      "name": "Python 3",
      "kind": "executable",
      "probe": {"executable": "python3", "arguments": ["--version"]}
    }
  ]
}
```

BashCut runs `bin/provider rpc`, writes one JSON request to its standard input, and reads one JSON response
from its standard output. Put the folder in one of the [plugin folders](#discovery-and-precedence), open
**Plugins** in the app, and run **Check Health**.

## Manifest

| Field | Required | Rules |
|---|---|---|
| `schema` | Yes | Exactly `bashcut.plugin/1` |
| `id` | Yes | Reverse-domain style: lowercase letters and digits in at least two parts separated by `.` or `-` (`example.voice`) |
| `name` | Yes | Nonempty display name |
| `version` | Yes | Semantic version, such as `1.2.0` or `1.2.0-beta.1` |
| `apiVersion` | Yes | `1` |
| `entrypoint` | Yes | Relative path inside the bundle to an executable file; no leading `/` and no `..` |
| `capabilities` | Yes | Nonempty list of unique capability IDs (lowercase, segments separated by `.` or `-`) |
| `providers` | No | Implementations the app can choose; each needs a unique `id`, a `capability` from `capabilities`, a `name` and an optional `priority` (default 0) |
| `dependencies` | No | External tools or models the plugin needs; see [Dependencies and health](#dependencies-and-health) |

BashCut resolves features by capability and provider ID, never by vendor SDK. A plugin is only chosen for a
capability when it declares a provider for it.

## Discovery and precedence

BashCut looks for plugin folders (each containing `plugin.json`) in three places, in this order:

1. The project: `<project>/.bashcut/plugins/`
2. The user: `~/Library/Application Support/BashCut/Plugins/`
3. The app bundle's `PlugIns` folder

When two plugins share an `id`, the first one found wins, so project plugins override user plugins, which
override bundled ones. Invalid manifests, duplicates and entrypoints that are missing or not executable are
skipped and reported as catalog diagnostics in the Plugins panel and in `bashcut plugins list`.

### Provider resolution

For each request, BashCut finds every plugin that declares a provider for the capability and probes their
dependencies. Only providers of plugins whose health is `ready` are candidates. BashCut then picks:

1. the provider named for this request (`--provider` on automation commands), or else the project's
   preference (set with the `setProviderPreference` operation), if it is a candidate;
2. otherwise the candidate with the highest `priority`, with ties broken by provider ID.

If no plugin declares the capability, the request fails with "Install a plugin that provides …"; if none is
healthy, it fails with "No healthy provider is available for …".

## Request lifecycle

Each request starts one new process in the plugin folder:

```sh
bin/provider rpc
```

BashCut writes one JSON request followed by a newline to standard input:

```json
{
  "id": "D0B15F12-9FC0-4E69-9FB2-D99B3124AA44",
  "apiVersion": 1,
  "method": "voice.synthesize",
  "provider": "example.voice.local",
  "params": {
    "text": "Xin chào",
    "language": "vi",
    "outputDirectory": "/absolute/path/to/request-folder",
    "takeCount": 3,
    "takeOffset": 0
  }
}
```

The method is the capability ID. The process writes exactly one JSON response to standard output and exits
with status 0. A successful response carries the same `id` and any JSON value in `result`:

```json
{
  "id": "D0B15F12-9FC0-4E69-9FB2-D99B3124AA44",
  "result": {"takes": [{"audioPath": "take-1.wav", "score": 0.82}]}
}
```

A failed response carries a stable, machine-readable `code` and a human-readable `message`:

```json
{
  "id": "D0B15F12-9FC0-4E69-9FB2-D99B3124AA44",
  "error": {"code": "model_missing", "message": "Install the Vietnamese voice model"}
}
```

Write diagnostics to standard error. When the process exits with a nonzero status, the last 4,000 bytes of
standard error become the error shown to the user.

### Limits

| Limit | Value |
|---|---|
| Request size | 1 MiB |
| Response size | 8 MiB |
| Call timeout | 120 seconds |
| Health probe timeout | 15 seconds, 256 KiB of output |

BashCut rejects malformed JSON, a mismatched response `id`, a response with neither `result` nor `error`,
oversized output, a nonzero exit and timeouts. The plugin runs in its own process group: on timeout,
cancellation or oversized output, BashCut sends `SIGTERM` to the whole group, then `SIGKILL` after a short
grace period. Helper processes the plugin started are killed with it, including after a normal exit.

### Process environment

Plugin processes receive only `HOME`, `PATH`, `TMPDIR`, `LANG` and `LC_ALL` (when set), plus:

- `BASHCUT_PLUGIN_ID`
- `BASHCUT_PLUGIN_DIR`
- `BASHCUT_PLUGIN_API_VERSION`

They never receive other app environment variables, credentials, the automation socket or a session token.
Provider credentials will need an explicit permission and credential contract rather than ambient
environment access.

## Capabilities

The app wires four capabilities. Each is a `CapabilityAdapter` in `BashCut/Core/Plugins/Capabilities/` that
builds the request parameters and validates the result.

| Capability | Used by | Params | Result |
|---|---|---|---|
| `voice.synthesize` | Voice panel, `voice speak` | `text`, `language`, `outputDirectory`, `takeCount`, `takeOffset` | `takes`: 1–8 `{audioPath, score?}` objects, or a single `audioPath` |
| `captions.transcribe` | Text panel, `captions generate` | `mediaPath`, `language`, `outputDirectory` | `srtPath` |
| `audio.beats` | Audio panel, `beats detect` | `mediaPath` | `bpm`, `beatsSeconds` |
| `audio.loudness` | Normalized export | `mediaPath` | `integratedLUFS`, `truePeakDbTP`, optional `loudnessRangeLU` |

### Output files

Capabilities that produce files (`voice.synthesize`, `captions.transcribe`) get a fresh `0700` request folder
as `outputDirectory`. Returned paths may be absolute or relative to it, but must resolve inside it after
symlinks are followed, and the file must exist. If the call fails, BashCut deletes the folder.

### `voice.synthesize`

- `text` is trimmed and nonempty; `takeCount` is 1–8.
- Return `takes` with one to `takeCount` entries, each with a unique `audioPath` and an optional `score` from 0
  through 1. A provider that only makes one file can return `{"audioPath": …}` instead.
- When the provider returns fewer takes than requested, BashCut calls it again with a higher `takeOffset` until
  the count is filled. If any call fails, the takes made so far are discarded.
- Each file must be valid audio with a positive duration. Without a `score`, BashCut scores the take by pace:
  1 at about 2.5 words per second, falling toward 0 as it drifts from that.
- The highest-scoring take wins; ties go to the earlier take.

### `captions.transcribe`

Return `srtPath` pointing to a UTF-8 SubRip file of at most 4 MiB. BashCut imports it with the same validation
as `bashcut captions import`.

### `audio.beats`

Return `bpm` (20–400) and `beatsSeconds`, a nonempty, strictly increasing array of up to 100,000 finite,
nonnegative times in source seconds. BashCut maps them through each timeline item's trim and speed into integer
project frames.

### `audio.loudness`

`mediaPath` is a rendered mix. Return `integratedLUFS` (−100 to 10), `truePeakDbTP` (−100 to 20) and optional
`loudnessRangeLU` (0 to 100), all finite.

During a normalized export, BashCut renders a temporary mix and asks the provider to measure it. It applies
gain toward the project target while keeping the true peak at or below −1 dBTP, exports again, and measures the
final file. The chosen mix gain and the measurement's provenance are stored as an undoable project edit.
Providers can wrap libebur128, FFmpeg filters or anything else without linking that dependency into the app.

### Provenance

Every result is tagged with the plugin ID, plugin version and provider ID that produced it. BashCut stores
this as provenance (for example on beat grids and loudness measurements), never as a live dependency.

## Dependencies and health

Each dependency declares an `id`, a `name`, a `kind` (`executable`, `python`, `model` or `systemLibrary`), a
`probe` command, an optional `install` recipe and an optional `estimatedBytes` download size:

```json
{
  "id": "whisper-model",
  "name": "Whisper base model",
  "kind": "model",
  "probe": {"executable": "bin/check-model", "arguments": ["base"]},
  "install": {
    "summary": "Download the base model (140 MB)",
    "command": {"executable": "bin/install-model", "arguments": ["base"]}
  },
  "estimatedBytes": 147000000
}
```

Commands are an executable plus an argument array, never shell strings:

- A path containing `/` must be relative and stay inside the plugin folder.
- A bare name (`python3`) is resolved through `/usr/bin/env` with the filtered `PATH`.
- Absolute paths, `..` and NUL bytes are rejected.

The Plugins panel runs the probes on demand, and BashCut runs them before each request to pick a provider. A
probe that exits with status 0 marks the dependency available. A failed probe shows as **missing** when the
dependency has an install recipe, or **failed** when it does not. A plugin is `ready` when every dependency is
available, otherwise `degraded`.

Install recipes are reviewable argv arrays that only run after the user approves them in the Plugins panel.
Agents can open that panel but can never approve an install or run a recipe.

## Adding a capability to the app

A new capability is one file conforming to `CapabilityAdapter` plus a test. The adapter declares the capability
ID, an optional `outputRoot` for request folders, request validation, the `params` it sends and how it turns
the result into a typed output. `CapabilityService.run` handles the rest: provider resolution, the request
folder, the transport call and provenance. Native panels, automation commands and export all go through
`CapabilityService`; none of them talk to plugin processes directly.

The transport is the `PluginTransport` protocol. Today's implementation, `PluginProcessRunner`, starts one
process per request. A session transport (one long-lived process answering many requests) can conform to the
same protocol without changing `CapabilityService` or the adapters.

## Current boundary

- The runtime, discovery, provider resolution and health checks are implemented.
- Voice, Text, Audio and Export use `voice.synthesize`, `captions.transcribe`, `audio.beats` and
  `audio.loudness`. Other analysis and interchange panels are not connected yet.
- Signed remote catalogs, a credential contract and detailed capability permissions are future work.
