# Writing plugins

Plugins give BashCut optional, replaceable implementations of capabilities such as voice synthesis,
transcription, beat detection and loudness analysis. Since plugin API 2 they can also add actions to the editor
(menus, toolbar, context menus, panel buttons), listen to editor events through hooks and declare options the
app renders natively. A plugin is a separate executable that BashCut starts for
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
| `name` | Yes | Display name, up to 80 characters; [localized text](#localized-text) |
| `version` | Yes | Semantic version, such as `1.2.0` or `1.2.0-beta.1` |
| `apiVersion` | Yes | `1` or `2`; see [API versions](#api-versions) |
| `minApiVersion` / `maxApiVersion` | No | The host API window the plugin works with; `minApiVersion` defaults to `apiVersion` |
| `entrypoint` | Yes | Relative path inside the bundle to an executable file; no leading `/` and no `..` |
| `capabilities` | Yes | List of unique capability IDs (lowercase, segments separated by `.` or `-`); may be empty only when `contributes` is not |
| `providers` | No | Implementations the app can choose; each needs a unique `id`, a `capability` from `capabilities`, a `name`, an optional `priority` (default 0) and an optional `timeoutSeconds` (10–3600, default 120; see [Limits](#limits)) |
| `dependencies` | No | External tools or models the plugin needs; see [Dependencies and health](#dependencies-and-health) |
| `transport` | No | `oneshot` (default) or `session`; see [Session transport](#session-transport). API 2 |
| `options` | No | Up to 64 settings; see [Options](#options). API 2 |
| `contributes` | No | `actions` and `hooks`; see [Actions](#actions) and [Hooks](#hooks). API 2 |

BashCut resolves features by capability and provider ID, never by vendor SDK. A plugin is only chosen for a
capability when it declares a provider for it.

### Localized text

Text people see (`name`, option `title` and `help`, action `title` and `confirm`) is either a string, which is
English, or a map from language code to text:

```json
"title": {"en": "Set clip opacity…", "vi": "Đặt độ mờ clip…"}
```

Keys are language codes such as `en`, `vi` or `pt-BR`; a map with more than one language must include `en`. BashCut
shows the interface language, then the base language (`pt-BR` → `pt`), then English. Values are nonempty. Provider
and dependency names stay plain strings.

## API versions

The host serves every plugin API version from `PluginAPI.minimum` (1) to `PluginAPI.current` (3); changes are
additive, so older manifests keep working. Version 2 adds `options`, `contributes` and the `session` transport.
Version 3 adds option `choiceLabels` and the `file` option type, the `BASHCUT_PLUGIN_DATA`/`BASHCUT_PLUGIN_CACHE`
folders and `::progress` lines from install recipes. A manifest that uses a feature with an older `apiVersion` is
invalid; set `minApiVersion` so older BashCut builds list the plugin as outdated instead of failing.

A plugin is **outdated** (listed, never run) when `minApiVersion` (or `apiVersion`) is newer than the host
("Update BashCut") or `maxApiVersion` is older than `PluginAPI.minimum` ("Update the plugin"). Requests carry
the lower of the plugin's `apiVersion` and the host's current version.

## Trust and availability

A plugin runs only after the user trusts its exact files. Trusting pins the SHA-256 of `plugin.json`, of the
entrypoint and of every other file in the plugin folder (path, executable bit and contents; hidden files,
`__pycache__` and `.pyc` are skipped) in `~/Library/Application Support/BashCut/plugin-trust.json` (mode `0600`),
together with the user's on/off switches. Changing any file, such as a script the entrypoint runs, asks for Trust
again. Grants made before folder digests existed are upgraded once while the manifest and entrypoint still match.
In development builds a plugin folder that is a symbolic link (`scripts/dev-link.sh` in `bashcut-plugins`) is
checked on its manifest and entrypoint only, so it can change while it is written. Each plugin is in one state:

| State | Meaning |
|---|---|
| `ready` | Trusted (or bundled), unchanged, turned on and API-compatible |
| `disabled` | Turned off in the Plugins sheet or with `plugins set --enabled off` |
| `untrusted` | Never approved, such as a plugin that came with a project |
| `changed` | Its manifest or entrypoint changed since approval; choose **Trust** again |
| `outdated` | Its API window does not include this BashCut |

- Plugins in the app bundle are trusted without a pin; they can still be turned off.
- Installing a plugin from the Plugins sheet pins the installed files.
- **Trust**, **Revoke Trust** and turning a plugin or its hooks **on** are user-only (Plugins sheet). Agents can
  only turn them off with `plugins set`.
- Only `ready` plugins provide capabilities, show actions or receive hooks. Turning a plugin off also stops its
  session process.

## Plugin registry

BashCut can install plugins from a remote catalog. There is no server: the catalog is a static
[`registry.json`](https://github.com/dongnguyenvie/bashcut-plugins/blob/main/registry.json) in the
[`bashcut-plugins`](https://github.com/dongnguyenvie/bashcut-plugins) repo, and archives are that repo's GitHub
Release assets. Publishing, the archive layout and the registry format are described in that repo's README.

- **Browse** in the Plugins sheet lists registry plugins with their summary, publisher, size and status
  (Install, Update, Installed, or why this Mac or BashCut cannot use it). **Updates** lists installed plugins with
  a newer compatible version. Panels without a provider (Text, Audio, Voice, Export loudness) show
  **Find a plugin…**, which opens Browse filtered to that capability.
- **Fetching:** `registry.json` is cached in `~/Library/Application Support/BashCut/Registry/` for 5 minutes and
  revalidated with its ETag. When the network fails, Browse shows the saved copy with the error. An unknown
  `schemaVersion` asks to update BashCut. `defaults write app.bashcut pluginRegistryURL <url>` points BashCut at
  another registry.
- **Choosing a version:** the newest version whose `platforms` include this Mac (`macos-arm64`, `macos-x86_64` or
  `macos-universal`), whose API window includes this BashCut and whose `minAppVersion` is not newer than the app.
  Development builds without a version accept any `minAppVersion`.
- **Installing:** BashCut downloads the archive over HTTPS from GitHub hosts, checks its size and the registry
  SHA-256, unpacks it with `ditto` into a staging folder, and requires exactly one plugin folder, no links leaving
  it, a valid manifest and the registry's id and version. Then it shows the install approval with the source URL,
  checksum and dependency plan. Only after the user approves does it run dependency recipes, move the plugin into
  `~/Library/Application Support/BashCut/Plugins/<id>/` and pin it. Nothing from the archive runs before that.
- **Updating** uses the same steps and replaces the installed copy; the previous copy is kept in `.previous/` until
  the move succeeds. A running session is stopped first. Option values and the on/off switches carry over.
- **Removing** (Installed › Remove, `plugins remove`) deletes a plugin from the user or project plugin folder with
  its trust pin and user-scope options; projects keep their `pluginOptions` and `pluginData`. Plugins inside the app
  can only be turned off.
- **Signatures:** `signature` is `ed25519:BASE64` over the 32 raw bytes of the archive's SHA-256. BashCut checks it
  before downloading: a signature from the BashCut key compiled into the app is shown as *Signed by BashCut*; one
  from a key the registry lists under the plugin's `publisher` as *Signed by <publisher>*; no signature as
  *Not signed* with a warning. A signature that matches no key is refused. The registry cannot add BashCut keys
  (keys listed for `bashcut` are ignored), so only an app release can change what counts as first party.
  `plugins search` reports `signature: first-party | verified-publisher | unsigned`.
- **Yanked versions:** a registry version with `"yanked": "<reason>"` is never offered or installed. If the
  installed version is yanked, Browse and Installed say so and Updates offers the newest good version, even an
  older one.
- **Update check:** when a project opens, BashCut fetches the registry at most once a day (Settings › *Check for
  plugin updates daily*) and shows the count on the Plugins button and in the Plugins menu. It never installs on
  its own.
- **App Store channel:** a sandboxed build (the Mac App Store and TestFlight build, or one compiled with
  `BASHCUT_APP_STORE`) only runs plugins inside the app: no Browse or Updates, no Install Plugin…, and the user and
  project plugin folders are not searched (App Store Review Guideline 2.5.2; the sandbox would block most
  downloaded tools anyway). Developer ID and `scripts/run.sh` builds have every source. `BASHCUT_PLUGIN_CHANNEL=
  app-store` simulates it in a development build.

## Discovery and precedence

BashCut looks for plugin folders (each containing `plugin.json`) in three places, in this order:

1. The project: `<project>/.bashcut/plugins/`
2. The user: `~/Library/Application Support/BashCut/Plugins/`
3. The app bundle's `Contents/Resources/Plugins` folder (core plugins)

When two plugins share an `id`, the first one found wins, so project plugins override user plugins, which
override bundled ones — except that a copy found earlier replaces a bundled plugin only when its version is
higher, so an old download never hides the newer copy an app update brought. Invalid manifests, duplicates and entrypoints that are missing or not executable are
skipped and reported as catalog diagnostics in the Plugins panel and in `bashcut plugins list`.

### Provider resolution

For each request, BashCut finds every plugin that declares a provider for the capability, keeps the ones whose
[availability](#trust-and-availability) is `ready` and probes their dependencies. Only providers of plugins whose
health is `ready` are candidates. BashCut then picks:

1. the provider named for this request (`--provider` on automation commands), or else the project's
   preference (set with the `setProviderPreference` operation), if it is a candidate;
2. otherwise the candidate with the highest `priority`, with ties broken by provider ID.

If no plugin declares the capability, the request fails with "Install a plugin that provides …"; if none may run,
it fails with "No enabled provider for …" and each plugin's reason; if none is healthy, it fails with
"No healthy provider is available for …".

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
| Call timeout | 120 seconds, or the provider's `timeoutSeconds`. With the session transport this is the longest a request may go **without a progress line**; every `progress` message restarts it, up to 4 hours in total |
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
- `BASHCUT_PLUGIN_DATA`: `~/Library/Application Support/BashCut/PluginData/<id>/`, for state that is costly to
  rebuild (environments, settings); kept across updates.
- `BASHCUT_PLUGIN_CACHE`: `~/Library/Caches/BashCut/PluginData/<id>/`, for downloads that can be fetched again
  (models).

BashCut creates both folders, shows their size when the plugin is removed and offers to delete them. `PATH`
gains `/opt/homebrew/bin` and `/usr/local/bin`, since an app opened from Finder starts with only
`/usr/bin:/bin:/usr/sbin:/sbin`. Probes and install recipes get the same environment. They never receive other app environment variables, credentials, the automation socket or a session token.
Provider credentials will need an explicit permission and credential contract rather than ambient
environment access.

## Capabilities

The app wires four capabilities. Each is a `CapabilityAdapter` in `BashCut/Core/Plugins/Capabilities/` that
builds the request parameters and validates the result.

| Capability | Used by | Params | Result |
|---|---|---|---|
| `voice.synthesize` | Voice panel, `voice speak` | `text`, `language`, `outputDirectory`, `takeCount`, `takeOffset` | `takes`: 1–8 `{audioPath, score?}` objects, or a single `audioPath` |
| `captions.transcribe` | Text panel, `captions generate` | `mediaPath`, `language`, `outputDirectory` | `srtPath`, optional `wordsPath` |
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

Return `srtPath` pointing to a UTF-8 SubRip file of at most 4 MiB, timed in the media's own seconds. BashCut
validates it like `bashcut captions import`, then places each cue through every clip where the media is heard
(audio clips, including sound linked to video, and video clips without linked sound; not muted clips, muted layers
or freeze frames), through the clip's trim, position, speed and speed ramp. Cues outside the clips are dropped and
a cue across a cut is split. Media that is not on the timeline keeps the cue times as timeline times. Captions
carry `captionMedia`, so generating again with `replace` swaps only that media's captions.

Optionally also return `wordsPath`: a JSON file in the output folder, `[{"text", "start", "end"}]` with each word's
time in the media's seconds (at most 8 MiB). BashCut stores the words that fall inside each placed caption as its
`words` (frames from the caption's start), which word-by-word captions (`wordStyle`, `captions words`) follow.
Without it, word timings are estimated from word length.

### Core plugins

`bashcut.audio-analysis` comes inside the app (`Contents/Resources/Plugins/`, source in `Plugins/audio-analysis/`) and needs
no setup. It is an ordinary out-of-process plugin built from Swift with AVFoundation and vDSP:

- `audio.loudness`: ITU-R BS.1770-4 integrated loudness, EBU Tech 3342 loudness range and 4× oversampled true
  peak of the first audio track (stereo or mono; more channels are mixed to stereo).
- `audio.beats`: spectral-flux onsets, tempo from their autocorrelation (60–200 BPM, weighted toward 120) and
  dynamic-programming beat tracking.

Both providers have priority 0, so an installed provider with a higher priority, or one chosen for the project,
takes over. Core plugins can be turned off but not removed; a registry copy with a higher version replaces one.

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

## Options

`options` declares settings. The app draws them natively in the Plugins sheet (**Options…**) and sends the current
values with every action and hook request, and with every capability request to the plugin's providers (for
example the voice a `voice.synthesize` provider should use), as `options`.

```json
"options": [
  {"id": "sectionPrefix", "title": {"en": "Section prefix", "vi": "Tiền tố mốc"}, "type": "string",
   "default": "Mark", "scope": "project"},
  {"id": "strength", "title": "Strength", "type": "number", "minimum": 0, "maximum": 1, "default": 0.5},
  {"id": "voice", "title": "Voice", "type": "enum", "choices": ["Mai Anh", "Hải Đăng"], "default": "Mai Anh",
   "choiceLabels": {"Mai Anh": {"en": "Mai Anh — female · North", "vi": "Mai Anh — Nữ · Bắc"}}},
  {"id": "reference", "title": "Clone voice from", "type": "file", "fileTypes": ["wav", "m4a"], "scope": "project"}
]
```

- `choiceLabels` (API 3) gives `enum` choices display text; the value stays the choice.
- `file` (API 3) shows **Choose…** with a file panel (through `ModalCenter`, so agents answer it with
  `ui respond --path`); `fileTypes` limits the extensions. Project-scope files inside the project are stored
  relative to it, and plugins always receive absolute paths.
- Panels that use a capability (Voice, Text, Audio) show the options of the selected provider's plugin under the
  provider picker, so the voice is chosen where the voiceover is made.

| Field | Rules |
|---|---|
| `id` | A key: a letter, then up to 63 letters, digits, `_` or `-`; unique in the plugin |
| `title` | Label; [localized text](#localized-text) such as `{"en": "Opacity", "vi": "Độ mờ"}` |
| `help` | Optional caption under the field; localized text |
| `type` | `string`, `enum`, `number`, `integer` or `bool` |
| `default` | Must fit the type; without it: empty string, the first choice, `minimum` (or 0) or `false` |
| `choices` | Required for `enum`: 1–100 unique strings |
| `minimum`, `maximum` | Bounds for `number` and `integer` |
| `maxLength` | For `string`: 1–100,000 (default limit 10,000) |
| `scope` | `user` (default): saved for this Mac in `plugin-trust.json`. `project`: stored in the project under `pluginOptions.<plugin id>` as an undoable edit |

A stored value that no longer fits the option falls back to its default. Agents read options with
`plugins options` and set them with `plugins option`.

## Actions

`contributes.actions` adds commands to the editor. The app draws each one where the plugin asks, decides when it
is available, collects its parameters and turns the result into a validated, undoable edit. Plugins never ship UI
code.

```json
"contributes": {
  "actions": [
    {
      "id": "example.toolkit.set-opacity",
      "title": {"en": "Set clip opacity…", "vi": "Đặt độ mờ clip…"},
      "icon": "circle.lefthalf.filled",
      "placements": ["menu.plugins", "clip.context", "inspector.video"],
      "when": "selection.kind == video",
      "params": [{"id": "opacity", "title": "Opacity", "type": "number", "minimum": 0, "maximum": 1, "default": 0.5}]
    }
  ]
}
```

| Field | Rules |
|---|---|
| `id` | Starts with the plugin ID and a dot (`example.toolkit.grade`); unique; at most 64 actions |
| `title` | Up to 80 characters; a string (English) or a language map like `{"en": …, "vi": …}` |
| `icon` | Optional SF Symbol name |
| `placements` | One or more of the placements below |
| `when` | Optional [condition](#when-conditions); without it the action is available whenever a saved project is open |
| `params` | Up to 32 [options](#options) (their `scope` is ignored); shown in a native sheet before the action runs |
| `shortcut` | Optional, written like `cmd+shift+g`; ignored (and reported in diagnostics) when a built-in or earlier plugin action uses it |
| `context` | Extra read-only data: `timeline` (all tracks), `media` (all media with absolute paths), `project` (the whole document) |
| `confirm` | A question shown before the action runs from the UI; localized text |

### Placements

| Placement | Where it appears |
|---|---|
| `menu.plugins` | The main-menu **Plugins** menu, grouped by plugin |
| `toolbar` | Buttons in the editor toolbar |
| `clip.context` | The timeline clip context menu |
| `track.context` | The layer header context menu and the clip context menu |
| `timeline.context` | The timeline gap and empty-area context menu |
| `media.context` | The Media panel item context menu; the clicked media is the action's `media` |
| `panel.<panel>` | A **Plugins** section in a library panel: `panel.media`, `panel.audio`, `panel.text`, `panel.stickers`, `panel.effects`, `panel.transitions`, `panel.filters`, `panel.voice` |
| `inspector.<tab>` | The bottom of an inspector tab: `inspector.video`, `audio`, `text`, `color`, `speed` |

### When conditions

Clauses joined by `&&`. Each clause is `key`, `!key`, `key == value` or `key != value`; a value may list
alternatives with `|`. A missing key is false. The app evaluates the condition; no plugin code runs for it.

| Key | True or set when |
|---|---|
| `project` | A saved project is open |
| `timeline` | The timeline is not empty |
| `playing` | The viewer is playing |
| `source` | The source viewer shows media |
| `selection`, `selection.kind`, `selection.role` | An item is selected; its layer kind (`video`, `audio`, `text`, `adjustment`) and role |
| `track`, `track.kind`, `track.role` | A layer is selected; its kind and role |
| `media`, `media.kind` | The selected item (or the context-menu media) has media; its kind |

Example: `selection && selection.kind == video|audio && !playing`. Actions are also unavailable while the editor
is busy, the project has a file conflict or the same action is already running.

### Running an action

An action runs as a background job (`jobs status`, `jobs cancel`) and calls the plugin with method
`plugin.action`:

```json
{
  "action": "example.toolkit.set-opacity",
  "params": {"opacity": 0.3},
  "options": {"sectionPrefix": "Mark", "announce": true},
  "context": { "...": "see Context" },
  "outputDirectory": "/path/to/project/generated/plugins/example.toolkit/<uuid>"
}
```

`provider` is absent: an action belongs to its plugin. `outputDirectory` is a fresh `0700` folder; it is removed
when the call fails or the plugin wrote nothing.

### Results

Actions and hooks return the same object; every field is optional.

| Field | Meaning |
|---|---|
| `message` | Status text (up to 2,000 characters), shown as `<plugin name>: <message>` |
| `label` | Undo label (up to 120 characters); defaults to `<plugin name>: <action title>` or `<plugin name>: <event>` |
| `operations` | Up to 1,000 **proposed** operations in the `timeline apply` codec (`{"op": "split", …}`); internal operations (`group`, `restore`) are rejected |
| `baseRev` | The revision the operations were computed against (`context.project.rev`); a newer project rejects them as stale |
| `pluginData` | New value for this plugin's own entry in the project's `pluginData` object (`null` removes it), applied in the same edit; other plugins' entries are never touched (at most 256 KiB) |
| `files` | Up to 100 paths the plugin wrote; each must resolve inside `outputDirectory` |
| `ui` | Action results only: `select` (item ID), `selectTrack`, `seek` (frame), `reveal` (frame), `panel` (library panel name), `inspector` (tab) |
| `data` | Any JSON returned to `plugins run` callers as `data` |

BashCut validates the operations like an agent edit (revision check, layer rules, locked layers) and commits them
with `pluginData` as **one undoable edit by author `plugin`**: it gets the agent change markers and Undo notice,
and is audited as `plugin.action.<action id>` or `plugin.hook.<event>`. An `addMedia` path that is absolute and
inside the project folder is stored relative to the project, so files written to `outputDirectory` can be added
directly.

## Hooks

`contributes.hooks` subscribes to editor events. An entry is an event name or an object:

```json
"hooks": [
  "media.imported",
  {"event": "export.finished", "edits": true},
  {"event": "edit.committed", "debounceMs": 1000, "context": ["timeline"]}
]
```

| Field | Rules |
|---|---|
| `event` | One of the events below; each at most once |
| `debounceMs` | 0–60,000; waits this long after the last event and delivers only the latest payload. Default 400 for frequent events, 0 otherwise |
| `edits` | `true` lets the hook return `operations` or `pluginData`; without it they are ignored and logged |
| `context` | Extra context parts, as for actions |

Hooks call the plugin with method `plugin.hook` and params `event`, `payload`, `options`, `context` and
`outputDirectory`. Every payload also has `event` and `at` (ISO 8601).

| Event | Payload | Frequent |
|---|---|---|
| `app.launched` | — | |
| `project.created` | `path`, `name` | |
| `project.opened` | `path`, `name`, `rev` | |
| `project.saved` | `path`, `rev` | |
| `project.closed` | `path`, `name` (sent when another project replaces it) | |
| `edit.committed` | `label`, `author`, `rev`, `previousRev`, `changedItems` (up to 200 IDs), `changedCount` | Yes |
| `edit.undone`, `edit.redone` | Same as `edit.committed` | Yes |
| `selection.changed` | `item`, `track` | Yes |
| `playback.stopped` | `playhead` | Yes |
| `media.imported` | `author`, `media` (the new media objects) | |
| `captions.generated` | `media`, `provider` (provenance), `rev` | |
| `beats.detected` | `media`, `bpm`, `beats` | |
| `voice.generated` | `item`, `media`, `path` | |
| `export.started` | `job`, `output`, `preset`, `author` | |
| `export.finished` | `output`, `preset`, `rev` | |
| `export.failed` | `output`, `preset`, `error` | |
| `job.finished` | The job as in `jobs status` (completed `plugins.run` jobs are not sent) | |
| `plugin.action.finished` | `action`, `plugin`, `rev` | |

Frequent events need `"transport": "session"`; the manifest is invalid otherwise.

Delivery rules:

- Hooks are **notify-only**: the event has already happened and the plugin cannot block or change it.
- Each (plugin, event) pair is debounced and coalesced; a plugin handles one hook at a time and later events wait
  in its queue.
- At most 60 deliveries per plugin per minute; extra events are dropped and logged.
- An edit a plugin made never triggers that plugin's own hooks.
- Failures go to the hook log (Plugins › **Hook Activity**, `plugins hooks`) and the debug log, never to the
  editor's status bar. A plain `message` is shown in the status bar.
- Edits proposed after the project changed are ignored.
- Settings › **Run plugin hooks** (on by default) stops all hooks; each plugin also has a **Hooks** switch.
- Settings › **Apply plugin hook edits without review** (off by default, user-only) applies hook edits at once.
  Otherwise they wait: the toolbar shows **N plugin edits**, the review sheet (dialog `plugin-proposals`) offers
  Apply or Discard, and agents use `plugins proposal <id> --decision apply|discard`. Up to 20 proposals are kept.

## Context

Actions and hooks receive a read-only snapshot:

| Field | Content |
|---|---|
| `app` | `apiVersion`, `language` (interface language), `version` |
| `author` | Who triggered it (`user`, an agent, or `plugin` for hooks) |
| `project` | `path`, `root`, `name`, `rev`, `fps`, `width`, `height`, `duration`, `contentLanguage` |
| `playhead` | Timeline frame |
| `selection` | The selected item's fields plus `track`, when an item is selected |
| `selectedTrack` | `id`, `kind`, `role`, `name`, when a layer is selected |
| `media` | The context-menu media, or the selected item's media, with `absolutePath` |
| `pluginData` | This plugin's own `pluginData` entry, or `null` |
| `tracks`, `allMedia`, `document` | Only with the `timeline`, `media` or `project` context part |

## Session transport

With `"transport": "session"` BashCut starts `entrypoint session` once per plugin and exchanges
newline-delimited JSON over stdin/stdout. Requests may overlap; replies are matched by `id`.

| Direction | Message |
|---|---|
| App → plugin | `{"type":"hello","apiVersion":2,"host":"BashCut","pluginId":…}` |
| Plugin → app | `{"type":"hello","apiVersion":2}` within 10 seconds |
| App → plugin | `{"type":"request","id","apiVersion","method","provider"?,"params"}` |
| Plugin → app | Any number of `{"type":"progress","id","progress"?,"message"?}` (`progress` 0–1; shown on the job) |
| Plugin → app | `{"id","result"}` or `{"id","error":{"code","message"}}` |
| App → plugin | `{"type":"cancel","id"}` when the caller cancels or the request times out (120 s without progress, or the provider's `timeoutSeconds`; 4 h in total) |
| App → plugin | `{"type":"shutdown"}` after 90 s idle, then `SIGTERM` and `SIGKILL` to the process group |

- Lines are at most 8 MiB and requests at most 1 MiB; invalid JSON or an oversized line ends the session.
- When the process exits, pending requests fail with the last 4,000 bytes of its stderr; the next request starts a
  new process. After 3 crashes in a minute the plugin is refused for a minute.
- Long jobs (transcribing an hour of audio, a model download) should send a `progress` line at least every
  minute, even without a new fraction, to keep the request alive. A provider whose steps stay silent for longer
  sets `timeoutSeconds`.
- Health probes still use one-shot processes. The environment is the same filtered one as for `rpc`.
- `PluginRouter` picks the one-shot or session transport from the manifest, so capabilities work over either.

A worked example covering options, three actions, three hooks and both transports is
`Fixtures/plugins/example.toolkit` (Python standard library only).

## Commands

Everything above is available to agents through the CLI and MCP (`bashcut_plugins_*` tools):

| Command | Mode | UI equivalent |
|---|---|---|
| `plugins list` | read | Plugins sheet: availability, transport, actions, hooks, options |
| `plugins health [plugin]` | read | Check Health |
| `plugins actions` | read | Every contributed action with placements, `when`, shortcut, a JSON Schema for its params and whether it is enabled now |
| `plugins run <action> [--params '{…}']` | edit, job | Clicking the action and filling its sheet |
| `plugins hooks` | read | Hook Activity: subscriptions, recent runs, waiting proposals |
| `plugins proposal <id> --decision apply\|discard` | edit | The review sheet |
| `plugins options <plugin>` | read | Options… |
| `plugins option <plugin> --option <id> [--value <text>]` | edit | Editing an option; no value resets it |
| `plugins set <plugin> [--enabled off] [--hooks off]` | edit | The Enabled and Hooks switches (agents can only turn them off) |
| `plugins search [query] [--capability <id>] [--refresh]` | read | Browse |
| `plugins updates` | read | Updates |
| `plugins install <plugin> [--version <v>]` | edit, job | Install or Update in Browse: downloads and verifies, then shows the approval (only the user can approve) |
| `plugins remove <plugin> [--data]` | edit | Installed › Remove; `--data` also deletes the plugin's data and cache folders |
| `plugins setup <plugin>` | edit | Install Dependencies… (opens the approval; only the user approves) |

`ui actions` lists plugin actions next to built-in ones and `ui action <id or shortcut>` runs them. An action with
parameters or `confirm` opens its sheet (dialog `plugin-action`); answer it with `ui respond run|cancel`, or use
`plugins run --params` instead. `ui open plugin-proposals` opens the review sheet.

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

Commands are an executable plus an argument array (`arguments` may be left out), never shell strings:

- A path containing `/` must be relative and stay inside the plugin folder.
- A bare name (`python3`) is resolved through `/usr/bin/env` with the filtered `PATH`.
- Absolute paths, `..` and NUL bytes are rejected.

The Plugins panel runs the probes on demand, and BashCut runs them before each request to pick a provider. A
probe that exits with status 0 marks the dependency available. A failed probe shows as **missing** when the
dependency has an install recipe, or **failed** when it does not. A plugin is `ready` when every dependency is
available, otherwise `degraded`.

Install recipes are reviewable argv arrays that only run after the user approves them in the Plugins panel.
Agents can open that panel but can never approve an install or run a recipe.

- **Running:** recipes run as a job (`plugins.install` or `plugins.setup` in `jobs status`) in the plugin's own
  process group and filtered environment, with the working directory set to the plugin folder. The Plugins sheet
  shows the current step, a progress bar and the output, and **Cancel** (or `jobs cancel`) stops the whole group.
  A cancelled or failed install leaves the installed copy, if any, untouched.
- **Progress:** a recipe line `::progress <0…1> [message]` sets the bar and the step; other lines are shown as
  output, and the last 4,000 characters become the error when the recipe fails.
- **Preflight:** before the approval, BashCut runs the probes on the unpacked plugin and labels each dependency
  *Available on this Mac*, *Installed during setup* (missing, with a recipe) or *Not available on this Mac* (missing,
  no recipe). A plugin with an unavailable dependency cannot be installed: the sheet says so in plain words.
- **Space:** the approval shows the archive plus the `estimatedBytes` of dependencies that are still missing and the free space, and refuses
  to start when less than 1.2 × that is free.
- **Repair:** when a probe reports a dependency with a recipe as missing (for example after a cancelled setup),
  Installed shows **Install Dependencies…**, which asks for approval and runs the recipes again
  (`plugins setup <plugin>` opens the same approval).
- Recipes should not depend on the Mac's own tools beyond `/usr/bin`: macOS ships Python 3.9 and no Homebrew.
  `bashcut.vieneu-tts` downloads `uv` and a private Python into `BASHCUT_PLUGIN_DATA`, for example.

## Adding a capability to the app

A new capability is one file conforming to `CapabilityAdapter` plus a test. The adapter declares the capability
ID, an optional `outputRoot` for request folders, request validation, the `params` it sends and how it turns
the result into a typed output. `CapabilityService.run` handles the rest: provider resolution, the request
folder, the transport call and provenance. Native panels, automation commands and export all go through
`CapabilityService`; none of them talk to plugin processes directly.

The transport is the `PluginTransport` protocol. `PluginProcessRunner` starts one process per request,
`PluginSessionTransport` keeps one process per plugin, and `PluginRouter` (the service's default) picks between
them from the manifest, so `CapabilityService` and the adapters do not depend on the transport. Actions and hooks
are two more adapters, `PluginActionCapability` and `PluginHookCapability`, run on a named plugin with
`CapabilityService.runContribution`.

## Current boundary

- The runtime, discovery, provider resolution, health checks, trust pins, the API window, options, actions,
  hooks and the session transport are implemented.
- Voice, Text, Audio and Export use `voice.synthesize`, `captions.transcribe`, `audio.beats` and
  `audio.loudness`. Other analysis and interchange panels are not connected yet.
- Plugins cannot own panels or windows; contributions use the fixed placements above.
- The plugin registry (browse, install, update, remove, signatures, yanked versions, daily update check) is
  implemented.
- A credential contract and detailed capability permissions are future work.
