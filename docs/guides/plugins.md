# Writing plugins

Plugins give BashCut optional, replaceable implementations of capabilities such as voice synthesis,
transcription, beat detection and loudness analysis. Since plugin API 2 they can also add actions to the editor
(menus, toolbar, context menus, panel buttons), listen to editor events through hooks and declare options the
app renders natively. Since plugin API 6 they can ship library packs for any library panel and search or generate
library items (see [Library packs](#library-packs) and [Library search and generate](#library-search-and-generate)),
since API 7 agent skills that teach agents to use them ([Agent skills](#agent-skills)), and since API 8 their own
panel in the left rail, dock tabs and sheets with declarative views, and the use of other plugins
([Plugin panels and views](#plugin-panels-and-views), [Using other plugins](#using-other-plugins)), and since API 9
their own review checks ([`review.check`](#reviewcheck)). A plugin is a separate
executable that BashCut starts for
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

To start from a working plugin instead, run `scripts/new-plugin.py` in
[`bashcut-plugins`](https://github.com/dongnguyenvie/bashcut-plugins#writing-a-plugin). It generates a capability
provider, an action, hooks, options or a chat agent in Swift, shell, Node.js or Python. Each one comes with a
checked manifest, an entrypoint that already speaks the protocol and smoke tests.

## Manifest

| Field | Required | Rules |
|---|---|---|
| `schema` | Yes | Exactly `bashcut.plugin/1` |
| `id` | Yes | Reverse-domain style: lowercase letters and digits in at least two parts separated by `.` or `-` (`example.voice`) |
| `name` | Yes | Display name, up to 80 characters; [localized text](#localized-text) |
| `version` | Yes | Semantic version, such as `1.2.0` or `1.2.0-beta.1` |
| `apiVersion` | Yes | `1` to `9`; see [API versions](#api-versions) |
| `minApiVersion` / `maxApiVersion` | No | The host API window the plugin works with; `minApiVersion` defaults to `apiVersion` |
| `entrypoint` | Yes | Relative path inside the bundle to an executable file; no leading `/` and no `..` |
| `capabilities` | Yes | List of unique capability IDs (lowercase, segments separated by `.` or `-`); may be empty only when `contributes` is not |
| `providers` | No | Implementations the app can choose; each needs a unique `id`, a `capability` from `capabilities`, a `name`, an optional `priority` (default 0), an optional `timeoutSeconds` (10–3600, default 120; see [Limits](#limits)) and, for `library.search` and `library.generate` only, optional `kinds` (API 6): the library kinds it serves, every kind when left out |
| `dependencies` | No | External tools or models the plugin needs; see [Dependencies and health](#dependencies-and-health) |
| `transport` | No | `oneshot` (default) or `session`; see [Session transport](#session-transport). API 2 |
| `options` | No | Up to 64 settings; see [Options](#options). API 2 |
| `contributes` | No | `actions` and `hooks` (API 2), `library` (API 6), `skills` (API 7), `container` and `views` (API 8); see [Actions](#actions), [Hooks](#hooks), [Library packs](#library-packs), [Agent skills](#agent-skills) and [Plugin panels and views](#plugin-panels-and-views) |
| `requires` | No | Other plugins this one needs (API 8): `[{"id", "version"}]`, at most 16; see [Using other plugins](#using-other-plugins) |
| `uses` | No | Capability IDs this plugin calls with `plugins.invoke` (API 8), at most 32 |
| `features` | No | [Host features](#host-features) the plugin cannot work without (API 8), at most 32 |
| `category` | No | Where Plugins and Settings group it: `agents`, `captions`, `voice`, `audio`, `color`, `effects`, `export` or `utilities`. A registry listing's category wins; without either, BashCut guesses from the capabilities (`agent.*`, `captions.*`, `voice.*`, `audio.*`) and falls back to Utilities. Older BashCut versions ignore it |
| `author` | No | Who wrote the plugin: `{"name": "Luan Tran", "url": "https://github.com/luantran069"}`. `name` is 1–80 characters on one line; `url` is optional (`null` or left out) and must be an `http` or `https` link. Plugins (Installed and Browse) show *By <name>*, a link when there is a url; `plugins list` and `plugins search` return it. The registry's `publisher` is who signs and ships the plugin, which may differ. Metadata only, so any `apiVersion`; older BashCut versions ignore it |

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

The host serves every plugin API version from `PluginAPI.minimum` (1) to `PluginAPI.current` (9); changes are
additive, so older manifests keep working. Version 2 adds `options`, `contributes` and the `session` transport.
Version 3 adds option `choiceLabels` and the `file` option type, the `BASHCUT_PLUGIN_DATA`/`BASHCUT_PLUGIN_CACHE`
folders and `::progress` lines from install recipes. Version 4 adds the `secret` option type, the session host
channel (`event` and `call` lines) and the `agent.chat` capability. Version 5 adds the `agent.terminal` capability
and the manifest's `terminal` object. Version 6 adds `contributes.library` (library packs), the `library.search` and
`library.generate` capabilities and provider `kinds`. Version 7 adds `contributes.skills` (agent skills). Version 8 adds plugin UI and composition:
`contributes.container` and `contributes.views` (a panel in the left rail with declarative views), `requires`, `uses`
with the `plugins.invoke` host call, the host channel for views and session actions, and `features`. Version 9 adds
the `review.check` capability. From version 8
on, the API version goes up at most once per BashCut release; smaller differences between hosts are
[host features](#host-features). A manifest
that uses a feature with an older `apiVersion` is
invalid; set `minApiVersion` so older BashCut builds list the plugin as outdated instead of failing.

A plugin is **outdated** (listed, never run) when `minApiVersion` (or `apiVersion`) is newer than the host
("Update BashCut") or `maxApiVersion` is older than `PluginAPI.minimum` ("Update the plugin"). Requests carry
the lower of the plugin's `apiVersion` and the host's current version.

### Host features

Host features (API 8) are names for what a BashCut can do, so a plugin asks for exactly what it uses instead of a whole
API version: `container`, `views`, `requires`, `invoke`, and `views.<component>` for each view component (`views.list`,
`views.audio`, `views.imageCompare`, …). The session `hello` carries `"features": […]` and `plugins views` lists them.
A manifest's `features` names the ones the plugin cannot work without; a BashCut without one lists the plugin as
outdated ("Update BashCut"). For optional features, read `features` from `hello` and adapt instead.

## Trust and availability

A plugin runs only after the user trusts its exact files. Trusting pins the SHA-256 of `plugin.json`, of the
entrypoint and every other file in the plugin folder (path, mode and contents, including hidden files and
Python bytecode; only `.DS_Store` is skipped) in `~/Library/Application Support/BashCut/plugin-trust.json` (mode `0600`),
together with the user's on/off switches. Changing any file, such as a script the entrypoint runs, asks for Trust
again. Symlinks must resolve to an existing target inside the plugin folder; other links are rejected.
The fingerprint cache checks fresh inode, mode, ctime and mtime metadata before reuse.
Grants made before folder digests existed are upgraded once while the manifest and entrypoint still match.
In development builds a plugin folder that is a symbolic link (`scripts/dev-link.sh` in `bashcut-plugins`) is
checked on its manifest and entrypoint only, so it can change while it is written. Each plugin is in one state:

| State | Meaning |
|---|---|
| `ready` | Trusted (or bundled), unchanged, turned on and API-compatible |
| `disabled` | Turned off in the Plugins sheet or with `plugins set --enabled off` |
| `untrusted` | Never approved, such as a plugin that came with a project |
| `changed` | Its manifest or entrypoint changed since approval; choose **Trust** again |
| `outdated` | Its API window does not include this BashCut, or it needs a [host feature](#host-features) this BashCut lacks |
| `needs-plugin` | Ready on its own, but a plugin it `requires` is missing, out of range or not ready (API 8; see [Using other plugins](#using-other-plugins)) |

- Approvals, enabled/hooks switches and local option values belong to `(id, canonical installation root)`.
  Another copy with the same ID starts untrusted and has separate settings. Legacy ID-only approvals cannot
  identify the approved root and require Trust again. Catalog diagnostics identify shadowed installations.
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
  `BASHCUT_APP_STORE`) only runs plugins inside the app: no Browse or Updates, no Add Plugin…, and the user and
  project plugin folders are not searched (App Store Review Guideline 2.5.2; the sandbox would block most
  downloaded tools anyway). Developer ID and `scripts/run.sh` builds have every source. `BASHCUT_PLUGIN_CHANNEL=
  app-store` simulates it in a development build.

## Private and local plugins

A plugin does not have to be in the registry. **Add Plugin…** (Plugins › Installed, the empty Installed view, or
Settings › Plugins) takes a link or, with *Choose File or Folder…* or a drop onto Plugins › Installed, a plugin on
this Mac:

- a plugin **folder** with `plugin.json` at its top level;
- the folder's **`plugin.json`** (its folder is used);
- a **`.zip`** or **`.bashcutplugin`** archive holding exactly one plugin folder, the same layout as a registry
  release.

### From a link

Paste the link the plugin's author shares (HTTPS only):

| Link | What is downloaded |
|---|---|
| `https://example.com/my-plugin.zip` (or `.bashcutplugin`) | that archive |
| `https://github.com/user/repo` (optionally `#v1.2`, a tag, branch or commit) | the repo at that ref (default branch otherwise); the plugin is the repo root |
| `https://github.com/user/repo/tree/<ref>/<folder>` | the repo at `<ref>`; the plugin is `<folder>` |
| `https://github.com/user/repo/blob/<ref>/<folder>/plugin.json`, or its `raw.githubusercontent.com` link | the same as the folder link |
| `https://github.com/user/repo/releases/tag/<tag>` (or `/releases/latest`) | the release's one `.zip` / `.bashcutplugin` asset (`.bashcutplugin` wins when there are both) |
| `https://github.com/user/repo/releases/download/<tag>/<asset>.zip` | that asset |

A repo link is pinned to the commit its ref points at when you download it, so the approval and the install are the
same files; the approval shows the commit (or the release tag). Add `#sha256=<hex>` to the link (or
`#<ref>&sha256=<hex>`, or fill *SHA-256* in the sheet) to require that exact archive; a different download is
refused.

**Private repos and servers:** *Add Token…* in the sheet saves an access token for the link's host (one for
`github.com` covers GitHub's API and downloads; use a fine-grained token with read access to the repo's contents).
It is kept in the Keychain on this Mac, sent only to that host, dropped when a download redirects to another host,
and never written to project files, logs or command parameters.

BashCut remembers where a plugin from a link came from: Plugins › Installed shows the link and commit, and
`plugins list` reports it as `source`. Checking those links for updates is planned.

BashCut checks the plugin before copying anything: a manifest that decodes and validates, an API window this
BashCut supports, an entrypoint that exists and is executable, and no symbolic links leaving the folder. Problems name
the field or file and the fix (`"apiVersion" must be an integer`, `entrypoint bin/provider is not executable (chmod
+x bin/provider)`). An unknown `category` is only a warning; the plugin is shown under Utilities.

The checked copy, not your folder, is what gets installed, so edits made while the approval is open do not slip in.
The approval says **Not from the BashCut registry · unsigned**, shows the source path (and an archive's SHA-256),
and, with a saved project open, lets you choose where it goes:

- **This Mac:** `~/Library/Application Support/BashCut/Plugins/<id>/`, for every project;
- **This project:** `<project>/.bashcut/plugins/<id>/`, which travels with the project folder.

When the same `id` is installed elsewhere, the approval says which copy runs (see
[Discovery and precedence](#discovery-and-precedence)). Installing an id that is already in the chosen folder
updates it. Trust works as for any unsigned plugin: installing pins the exact files, a later change needs approval
again, and only the user can approve. Remove works as for registry plugins.

**Replace…** on a copied plugin that is not from the registry (Plugins › Installed) updates it from a new folder, `plugin.json` or zip, in the
same scope; the new files must have the same `id`, and the approval says **Update**.

### Link (developer mode)

For a plugin you are writing, choose **Install as: Link (developer mode)** in the approval (a folder or its
`plugin.json` only; a zip or a download is always copied). BashCut then installs a symbolic link to your folder
instead of a copy, once your folder still holds the files that were checked; Installed shows **Linked to <path>
(developer mode)**.

After you edit the plugin, choose **Reload** on its row: it stops the plugin's session process, so the next call
starts your new code, and checks its files again. Any change to the pinned files makes the plugin **changed** until
you choose **Trust** again; Reload never trusts it. (Development builds of BashCut check a linked folder on its
manifest and entrypoint only, see [Trust and availability](#trust-and-availability).) Removing a linked plugin
removes only the link; your folder is kept.

Agents and scripts:

- `bashcut plugins validate <path>` or `--url <link> [--ref …] [--sha256 …]` reports `valid`, `id`, `version`,
  `capabilities`, `category`, `problems`, `warnings`, for archives and links `sha256`, and for links `source` (the
  commit or release tag). It installs and runs nothing.
- `bashcut plugins install --path <path>` or `--url <link> [--ref …] [--sha256 …]`, with `[--scope user|project]`,
  checks (and downloads) the plugin, then shows the same approval in the Plugins sheet. A private link uses the token
  saved in Add Plugin…; there is no token parameter. `--link` installs a plugin folder as a link (developer mode).
- `bashcut plugins replace <id> --path <path>` shows the approval to update a plugin from a new folder or zip.
- `bashcut plugins reload <id>` restarts a plugin and checks its files again; it reports `availability` (`changed`
  until the user trusts the new files). `plugins list` reports a linked plugin's folder as `linked`.
- `bashcut ui open add-plugin` opens the Add Plugin sheet.

To share a private plugin with a team, push it to a private GitHub repo and share the link (each person adds a
token once), send the zip (`ditto -c -k --keepParent my-plugin my-plugin.zip`) or commit
it under the project's `.bashcut/plugins/`. Each person approves it on their own Mac.

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
- `BASHCUT_SHARED_DATA`: `~/Library/Application Support/BashCut/PluginData/_shared/`, for runtimes several plugins
  can use, such as Python installs (`UV_PYTHON_INSTALL_DIR`).
- `BASHCUT_SHARED_CACHE`: `~/Library/Caches/BashCut/PluginData/_shared/`, for downloads several plugins can use,
  such as uv's package cache (`UV_CACHE_DIR`).

BashCut creates these folders, shows a plugin's own folders' size when the plugin is removed and offers to delete
them. Removing a plugin never touches the shared folders. Settings › Storage lists them as "Shared plugin runtimes"
and "Shared plugin downloads" (`storage clear shared-data` / `shared-cache`).

Rules for the shared folders:

- Keep only content-addressed, versioned things there (a Python per version, a package cache), never a venv,
  settings or anything one plugin owns. Environments go in `BASHCUT_PLUGIN_DATA`.
- They may be cleared at any time. After the shared cache is cleared, environments built from it must still work:
  uv clones files into each venv on APFS, so a venv keeps its own copy. After the shared data is cleared, the
  plugin's `check` should report the runtime as missing, so Installed offers **Install Dependencies…**.
- Never run `uv cache clean` or otherwise empty them from a setup script: other plugins use them.
- Fall back to your own folders when the variables are not set (an older BashCut).

Agent terminals (Claude, Codex and plugin agents launched by BashCut) get the same `BASHCUT_SHARED_DATA` and
`BASHCUT_SHARED_CACHE`, with `UV_PYTHON_INSTALL_DIR` and `UV_CACHE_DIR` set to their `python` and `uv` subfolders, so
the agent kit's scripts (`uv run`, `uvx`) reuse the same Python and packages. The folders are fixed; there is no
setting to move them, so Settings › Storage always knows what to clean up.

Plugin processes run as the user, without a sandbox, so the shared folders are a convention, not a boundary: any
plugin a user trusts can already write anywhere the user can. One plugin's venv lives in its own data folder, which
other plugins are not told about. `PATH`
gains `/opt/homebrew/bin` and `/usr/local/bin`, since an app opened from Finder starts with only
`/usr/bin:/bin:/usr/sbin:/sbin`. Probes and install recipes get the same environment. They never receive other app environment variables, credentials, the automation socket or a session token.
Provider credentials will need an explicit permission and credential contract rather than ambient
environment access.

## Capabilities

The app wires these capabilities. Each is a `CapabilityAdapter` in `BashCut/Core/Plugins/Capabilities/` that
builds the request parameters and validates the result.

| Capability | Used by | Params | Result |
|---|---|---|---|
| `voice.synthesize` | Voice panel, `voice speak` | `text`, `language`, `outputDirectory`, `takeCount`, `takeOffset` | `takes`: 1–8 `{audioPath, score?}` objects, or a single `audioPath` |
| `captions.transcribe` | Text panel, `captions generate` | `mediaPath`, `language`, `outputDirectory`, optional `startSeconds`/`endSeconds` | `srtPath`, optional `wordsPath` |
| `audio.beats` | Audio panel, `beats detect` | `mediaPath` | `bpm`, `beatsSeconds` |
| `agent.chat` (API 4, session only) | A chat-agent tab in the agent dock, `chat send` | `op` (`turn`, `reset`, `status`); a turn adds `conversation`, `text`, `images`, `context`, `instructions`, `tools`, `kit` | A turn: `stopReason` (`end`, `aborted`, `error`) and `error`; status: `ready`, `provider`, `model`, `detail`. See [Chat agents](#chat-agents) |
| `audio.loudness` | Normalized export, `audio measure` | `mediaPath`, optional `bands` | `integratedLUFS`, `truePeakDbTP`, optional `loudnessRangeLU`, `speechShare`, `presenceShare` |
| `audio.sync` | `media sync` | `mediaPath`, `otherPath` | `offsetSeconds`, `correlation`, optional `halves`, `overlapStartSeconds`, `overlapEndSeconds` |
| `library.search` (API 6) | A library panel's Search…, `library search` | `kind`, `query`, `limit`, `page`, `language`, `outputDirectory` | `items`: up to `limit` library item objects; see [Library search and generate](#library-search-and-generate) |
| `library.generate` (API 6) | A library panel's Generate…, `library generate` | `kind`, `prompt`, `limit`, `params` (hints), `language`, `outputDirectory` | `items`, as for `library.search` |
| `review.check` (API 9) | `review measure`, the Review sheet's Measure | `project`, `revision`, `fps`, `duration`, `width`, `height`, `projectRoot` | `issues`; see [`review.check`](#reviewcheck) |

### Output files

Capabilities that produce files (`voice.synthesize`, `captions.transcribe`, `library.search`, `library.generate`) get a fresh `0700` request folder
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

With `startSeconds` and `endSeconds` (`captions generate --from/--to`), transcribe only that stretch of the media and
keep the times in the media's seconds. BashCut cuts the cues and words to the range and, with `replace`, removes only
this media's captions heard inside it, so a stretch where recognition looped can be transcribed again. A provider
that ignores the range still works: it transcribes everything and BashCut keeps the range.

### Core plugins

`bashcut.audio-analysis` comes inside the app (`Contents/Resources/Plugins/`, source in `Plugins/audio-analysis/`) and needs
no setup. It is an ordinary out-of-process plugin built from Swift with AVFoundation and vDSP:

- `audio.loudness`: ITU-R BS.1770-4 integrated loudness, EBU Tech 3342 loudness range and 4× oversampled true
  peak of the first audio track (stereo or mono; more channels are mixed to stereo).
  With `bands`, also the speech-band (300–3000 Hz) and presence-band (1–4 kHz) energy shares.
- `audio.beats`: spectral-flux onsets, tempo from their autocorrelation (60–200 BPM, weighted toward 120) and
  dynamic-programming beat tracking.
- `audio.sync`: cross-correlation of the two files' loudness envelopes (100 per second), coarse over every overlap
  of at least half the shorter file, then fine around the best lag, and again on each half of the overlap.

The providers have priority 0, so an installed provider with a higher priority, or one chosen for the project,
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

With `bands: true` (`audio measure`), also return `speechShare` and `presenceShare`, each 0 to 1: the share of the
file's energy in the speech band (300–3000 Hz) and in the presence band (1–4 kHz). A provider that leaves them out
still answers `audio measure` without them.

### `audio.sync`

`mediaPath` and `otherPath` are two recordings of the same moment. Return `offsetSeconds` (time in `otherPath` =
time in `mediaPath` + offset, finite, under a day) and `correlation` (−1 to 1). Optionally return `halves`, up to two
`{offsetSeconds, correlation}` matches of the first and second half of the overlap (BashCut reports them as steady
when they agree within 0.02 s), and the overlap in the first file's seconds.

### `review.check`

A plugin's own review of the timeline: a model-scored hook, contrast, brand rules. Every ready provider of every
enabled plugin runs, side by side, when the user or an agent measures the review (`review measure`); `review run`
then lists its issues with the built-in ones for that revision. The request has the whole project (`project`, the
same JSON as `project get`; requests over 1 MB fail, as for any request), its `revision`, `fps`, `duration` in
frames, `width`, `height` and `projectRoot`. Return at most 50 issues:

```json
{"issues": [{"id": "hook", "title": "Weak hook", "detail": "No face or number in the first 2 s",
             "frame": 0, "endFrame": 60, "severity": "warning",
             "fix": {"command": "timeline.apply", "arguments": {"label": "…", "ops": []}, "hint": "Open on a face"}}]}
```

`id` (1–64 characters), `title` (1–120) and `frame` are required; `detail` (up to 1000 characters), `endFrame`,
`severity` (`error`, `warning` — the default — or `info`) and `fix` (a command with arguments, a hint, or both) are
optional. Frames are clamped to the timeline. BashCut prefixes each ID with the provider ID (`<provider>:<id>`) and
adds `source` (the plugin ID), which the Review sheet shows as *From plugin …*. A check has 30 seconds (less when its
provider sets a lower `timeoutSeconds`); a check that fails, returns a malformed result or runs out of time becomes
one info issue, "Plugin check failed", and never stops the others or the built-in checks. A project turns checks off
with `review.disabledChecks`, a list of plugin or provider IDs (`timeline apply` with `setProjectProperties`);
`plugins hooks` lists the checks under `reviewChecks` with `enabled` (for this project) and `active` (can run now).
Declaring `review.check` needs `apiVersion` 9.

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
- `secret` (API 4) is for API keys and tokens.
  - It must have `user` scope and no `default`.
  - BashCut keeps it in the Keychain (service `app.bashcut.plugin-secret`) and shows a password field with
    **Save** and **Clear**.
  - The plugin receives it in `options` like other values.
  - `plugins options` shows only `{"set": true|false}`. For a plugin declaring any secret, **all** options
    are user-only and stored for this Mac; project `pluginOptions` overrides are ignored. Automated option
    writes are refused, including non-secret settings such as the endpoint.
  - Keys are bound to the canonical installation root, the fingerprint and the values of every option marked
    `"bindsSecrets": true` (for example a provider and an endpoint). Enter a key after selecting the
    destination. Changing a binding value selects a separate key; other options do not. Legacy unbound
    keys are never reused automatically and must be re-entered in Settings. Changed plugin code also requires
    a new key entry, even after Trust; approving code does not grant it the previous version's credentials.
    Saving a key for new code deletes that installation's keys for older fingerprints.
  - Action parameters cannot be secrets.
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
| `bindsSecrets` | Not on `secret` or `file` options. The plugin's secrets are stored per value of this option, so a key entered for one destination is never sent to another |

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
| `confirm` | A question only the user can answer, shown before execution from any entry point, including CLI and shortcuts; localized text |

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

## Library packs

`contributes.library` (API 6) ships library packs for any library panel: music and sound effects, text styles,
stickers, effect recipes, transition presets and looks. Each entry names a pack folder inside the plugin:

```json
"apiVersion": 6,
"contributes": {
  "library": [{"path": "packs/party"}, {"path": "packs/lofi-music"}]
}
```

A pack folder is the format `library export-pack` writes and `library import-pack` reads: a `pack.json` with
`{"format": 1, "name": "Party", "items": [...]}` and the files its items' `file` and `preview` name, relative to the
folder. Items are ordinary [library items](automation.md#library-items) (`id`, `kind`, `name`, `tags`, `params`,
`source`, `license`…) and are checked like an imported pack's.

```json
{"format": 1, "name": "Lo-fi", "items": [
  {"id": "lofi-rain", "kind": "audio", "name": "Rain bed", "file": "files/rain.m4a", "tags": ["calm", "rain"],
   "license": "CC0", "params": {"role": "ambience", "loopable": true}},
  {"id": "party-popper", "kind": "sticker", "name": "Party popper", "params": {"emoji": "🎉"}}
]}
```

- Up to 32 packs. A `path` is relative, without `..`, `~` or a leading `/`; the folder and every file must resolve
  inside the plugin folder after symlinks. `plugins validate` reports a pack that cannot be read, with the reason.
- While the plugin is trusted, turned on and compatible, its items are in the **plugin** scope: `library list --scope
  plugin`, `plugin:<id>`, and the panels, where they are grouped under the plugin's name with their pack names.
  `createdBy` is `{"by": "plugin", "plugin", "pluginName", "pluginVersion"}`, whatever the pack says.
- They are read-only. `library update <id> --as <new-id>` (Duplicate & Edit…) saves an editable copy, with its
  files, in the project or user library.
- Placing or applying one (`library place`, `library apply`) copies any file it uses into the project first (by
  content: `music/`, `sfx/`, `stickers/`, `luts/library-<hash>.<ext>`), so removing, updating or turning off the
  plugin never breaks a timeline. The items disappear from the library with the plugin.
- IDs are shared across scopes: an item whose ID is built in, or that an earlier plugin already uses, is left out and
  listed under `diagnostics` in `plugins list`. Prefix IDs with something of your own (`party-…`).
- Packs are data: no plugin process runs to list or place them.

`Fixtures/plugins/example.library` is a worked example: a Party pack (stickers, a text style, a look and a transition)
and an offline `library.search` provider.

## Agent skills

`contributes.skills` (API 7) ships agent skills: `SKILL.md` folders in the agent kit's format that tell agents when
and how to use what the plugin adds (its actions, options and capability commands). Each entry names a skill folder
inside the plugin:

```json
"apiVersion": 7,
"contributes": {
  "skills": [{"path": "skills/loudness-check"}]
}
```

```markdown
---
name: loudness-check
description: Check how loud the media in an edit is and say what to change. Use when … Triggers: "to quá", "loudness check".
---

# Loudness check

1. Find the media with `bashcut media list`, then `bashcut audio measure --media <id>` …
```

- Up to 16 skills. A `path` is relative, without `..`, `~` or a leading `/`; the folder, its `SKILL.md` and any link
  inside it must resolve inside the plugin folder. The front matter `name` must equal the folder name (lowercase
  words joined by `-`, at most 64 characters) and `description` is required (at most 1024 characters). A `SKILL.md`
  is at most 64 KB and a skill folder at most 2 MB. Write the description as the kit does: what the skill is for,
  "Use when …", then `Triggers:` with quoted phrases.
- A skill that breaks a rule is left out and reported (`plugins validate`, `diagnostics` in `plugins list`); the rest
  of the plugin still works.
- Agents get the skills only while the plugin is trusted, turned on and compatible. Turning it off, revoking Trust,
  removing it or a Reload that drops a skill takes the skill away at once.
- In BashCut a plugin skill is named `<plugin-id>:<name>` (scope `plugin`), so it never clashes with the kit's
  `bc:` skills, another plugin's or the user's: `skills list --scope plugin`, `skills get example.skills:loudness-check`.
- They reach agents the way project and user skills do: listed with their paths in the agents' knowledge (the
  `[Notes for every project]` block), linked into the open project's `.claude/skills` and `.agents/skills` as
  `<plugin-id>--<name>`, into the Codex tab's workspace, and into a terminal plugin's `skillsFolder`. BashCut records
  the links it made in `.bashcut/plugin-skills.json` and only ever removes those.
- They are read-only. Knowledge › Skills shows them under **Plugins** with **Copy to This Project** and **Copy for
  Every Project**; `skills get` then `skills save --scope project|user` does the same. `skills save`, `enable`,
  `disable` and `remove` refuse the plugin scope.
- Skills are text: no plugin process runs to list or deliver them, and a skill never ships executables (commands it
  names go through BashCut's CLI or the plugin's capabilities).

`Fixtures/plugins/example.skills` is a worked example: a plugin that only ships a `loudness-check` skill.

## Plugin panels and views

A plugin with `contributes.container` (API 8) gets an icon in the left rail, under the built-in panels, while it is
trusted, turned on and its requirements are met. The icon opens the plugin's panel in the library column. BashCut draws
the panel's frame from the manifest, so every plugin gets the same parts:

- a header with the container title, the plugin name and version, and a button to its settings;
- a picker between its views when it has more than one, and the selected view;
- **Plugin**: its actions as Tools (each with its `when` condition), its skills, the plugins it `requires` with their
  state, and the capabilities it `uses` with **Find…** (Browse filtered by capability) when no ready plugin provides one.

```json
"transport": "session",
"contributes": {
  "container": {"icon": "waveform.badge.mic", "title": {"en": "Voices", "vi": "Giọng"}},
  "views": [{"id": "voices", "title": "Library"}, {"id": "takes", "title": "Takes"}]
}
```

| Field | Rules |
|---|---|
| `container.icon` | SF Symbol name |
| `container.title` | Optional [localized text](#localized-text), at most 24 characters; the plugin name by default |
| `views[].id` | A short key, unique; at most 8 views |
| `views[].title` | Localized text, at most 40 characters |
| `views[].location` | Where the view lives: `panel` (default), `dock` or `sheet` |
| `views[].icon` | Optional SF Symbol for a dock tab or sheet; the container's icon by default |

A container alone (no views) is a panel of the plugin's tools and skills. Views need the `session` transport.

### Where views live

| `location` | Where | Opens | Good for |
|---|---|---|---|
| `panel` | The plugin's panel in the left rail (225 pt wide); a picker switches between several | The rail icon | Browsing, tools next to the timeline |
| `dock` | A tab in the agent dock on the right, next to the agent tabs (330–500 pt wide) | The tab, always there while the plugin is ready | Wider work: libraries, take lists, long forms |
| `sheet` | A sheet over the editor with a Close button (Esc) | `plugins show-view`, the panel's **Views** list, or the plugin itself | A short task: a form, a confirmation with choices |

Only `panel` views need `contributes.container`; a plugin may have dock or sheet views without a rail icon. The panel's
**Plugin** section lists the plugin's dock and sheet views with a button that opens each. A plugin opens its own views
from a view or action request with the host call `plugins.show-view` (`{"plugin": "<its id>", "view": "<id>"}`); it
cannot open another plugin's. A view answer with `"close": true` closes its sheet (a finished form).
`location.panel`, `location.dock` and `location.sheet` are [host features](#host-features).

### View requests

The app asks the plugin for a view's components and sends what the user does. Both requests carry a
[host channel](#host-channel-api-4).

| Method | Params |
|---|---|
| `view.render` | `{"view", "state", "values", "locale", "context", "options"}` |
| `view.event` | the same plus `"event": {"node", "type", "value"}` |

- `state` is whatever the plugin returned last time (or `null`), so a plugin can keep no state of its own.
- `values` maps every input's `id` to its current value.
- `context` is the read-only editor snapshot actions get (project, selection, playhead).
- Event `type` is `click` (button), `change` (input), `submit` (text field with `submit`, on Return), `select` (list
  row; value = item `id`) or `action` (list row button; value = `{"item", "action"}`).

The answer:

```json
{
  "title": "Voices",
  "body": [{"type": "text", "text": "**3** voices", "markdown": true}, {"type": "button", "id": "refresh", "title": "Refresh"}],
  "state": {"page": 1},
  "refreshSeconds": 30,
  "notify": "Loaded"
}
```

- `body` (required): the components. `state`: kept and sent back (at most 64 KiB; left out, the last one is kept).
  `close: true` closes the view's sheet.
  `refreshSeconds` (2–3600): render again after that long, only while the view is on screen. `notify`: a status
  message shown once.
- While working, send `{"type":"event","id","event":{"kind":"render","body":[…],"title"?}}` to redraw before the answer
  (a progress bar, partial results), or `{"kind":"notify","text"}` for a status message.

### Components

Every component is `{"type", "id"?, …}`. Buttons, inputs and lists need an `id` (a short key, unique in the view);
others may have one. Text is shown as given (the plugin localizes it with `locale`).

| Type | Fields |
|---|---|
| `section` | `title`?, `collapsed`?, `children` |
| `row` | `children` side by side, `spacing`? |
| `divider`, `spacer` | `size`? (spacer) |
| `text` | `text`, `style`? (`body`, `title`, `heading`, `caption`, `secondary`, `mono`), `markdown`? (inline), `color`? |
| `badge` | `text`, `color`? (`accent`, `green`, `orange`, `red`, `purple`, `secondary`) |
| `keyValue` | `items: [{"key", "value"}]` (at most 100) |
| `progress` | `value`? (0–1; spinner without), `label`? |
| `image` | `path` (a local file), `height`? (16–600), `caption`? |
| `imageCompare` | `before`, `after` (local files), `height`?, `beforeLabel`?, `afterLabel`?; drag to compare |
| `audio` | `path`, `title`?: a play/stop button (one sound plays at a time) |
| `list` | `items: [{"id", "title", "subtitle"?, "icon"?, "image"?, "badge"?, "audio"?, "actions"?: [{"id", "title", "icon"?}]}]` (at most 500, 3 actions per row), `selected`?, `empty`? |
| `button` | `title`, `icon`?, `style`? (`primary`, `destructive`, `link`), `confirm`?, `wide`?, `disabled`? |
| `textField` | `label`?, `placeholder`?, `value`?, `search`? (sends `change` 300 ms after typing stops), `submit`? |
| `textArea` | `label`?, `value`?, `height`? (40–400) |
| `toggle` | `label`, `value`? |
| `picker` | `label`?, `value`?, `options: [{"value", "label"}]` or strings (at most 200) |
| `slider` | `label`?, `value`?, `min`, `max`, `step`?: sends `change` when the drag ends |

An input's `value` in an answer replaces what the user typed, except for an input whose change is still on its way.
Leave `value` out to keep the user's text. A text field without `search` and a text area send their value with the
next event instead of on every keystroke.

A component type this BashCut does not know draws "Needs a newer BashCut" and the rest of the view still works; check
`views.<type>` in the hello's `features` before relying on a new one.

### Limits and performance

- A view renders only while its panel is on screen; `refreshSeconds` timers stop when it is hidden.
- The panel is one lazy column: only the top-level components on screen are built, so a long view scrolls smoothly.
  Put long content at the top level or in a `list` rather than inside one huge `section`.
- Streamed `render` events are drawn at most every 60 ms; the ones in between are skipped. Answers are read off the
  main thread.
- One request per view runs at a time. Events that arrive meanwhile wait in order; a newer `change` of the same input
  replaces a waiting one (at most 16 wait).
- A view has at most 2000 components, nested at most 12 deep; longer texts are cut at 20,000 characters.
- Lists draw lazily. Images are read off the main thread as thumbnails of at most 640 pixels and cached; give
  `image` small files or thumbnails anyway.
- Answers over the session's line limit (8 MiB) fail; keep data in your plugin and send what is on screen.

Not available (they would cost performance or safety): webviews, free drawing, video players, timeline or viewer
overlays, inspector tabs, drag and drop from a view, and updates the plugin sends without a request.

### Commands

`plugins views` lists the plugins with panels or views, each view's location and whether it is shown, tools, skills,
requirements, uses and the host features. `plugins show-view <plugin> --view id` shows a view where it lives (the
sheet is dialog `plugin-view` in `ui dialog`; `ui respond close` closes it).
`plugins view <plugin> [--view id] [--open]` renders a view and returns its components with the input values;
`--open` also shows it. `plugins view-event <plugin> --node go [--type click|change|submit|select|action]
[--value …]` does what a user does and returns the new components, so agents and tests can drive a plugin's UI.

## Using other plugins

A plugin can build on what other plugins provide. Prefer the first way that works:

1. **Call a BashCut command** over the [host channel](#host-channel-api-4) from a view or action request:
   `voice.speak` to generate speech, `captions.generate`, `beats.detect`, `media.import`, `media.place`,
   `timeline.apply`, … BashCut picks the provider the user chose (VieNeu-TTS or any other `voice.synthesize`
   plugin), checks the request, stores files in the project and records the edit with the plugin as author. Your
   plugin never needs to know which plugin did the work.

   ```json
   {"type": "call", "id": "<request id>", "callId": "c1", "method": "voice.speak",
    "params": {"text": "Xin chào", "keepTakes": true}}
   ```

2. **`plugins.invoke`** for a capability that has no BashCut command (a capability another plugin defined, such as
   `image.unwatermark`). List it in `uses`; calling a capability that is not listed fails. BashCut resolves the
   provider like any capability, adds its option values and a fresh `outputDirectory`, and returns
   `{"plugin", "provider", "outputDirectory", "result"}` with the provider's result unchanged (`outputDirectory` is
   `null`, and the folder gone, when the provider wrote no files).

   ```json
   {"type": "call", "id": "<request id>", "callId": "c2", "method": "plugins.invoke",
    "params": {"capability": "image.unwatermark", "params": {"path": "/…/frame.png"}, "provider": null}}
   ```

   The called plugin gets no host channel, so invocations cannot loop; at most 4 run at once per plugin.
   `agent.chat` and `agent.terminal` cannot be invoked. `bashcut plugins invoke <capability> --params '{…}'` does the
   same from the command line (a job).

3. **`requires`** when the plugin needs one particular plugin (its own commands, files or a feature only it has):

   ```json
   "requires": [{"id": "bashcut.vieneu-tts", "version": "^0.1.0"}]
   ```

   `version` is a range: `*` (default), `1.2.3`, `>=0.2.0`, `<2.0.0`, `^1.2.0` (same major; same minor below 1.0),
   `~1.2.0` (same minor), or several separated by spaces (`>=1.0.0 <2.0.0`). Until every required plugin is
   installed in range and ready (its own requirements included; a loop never is), the plugin is listed as
   `needs-plugin` with the reason and nothing of it runs: actions, hooks, views, skills and providers. After the
   plugin is installed from the registry, BashCut offers to install the first missing requirement the registry has
   (each install is still approved and trusted on its own). `plugins list` reports each requirement's state
   (`ready`, `missing`, `wrong-version`, …).

Prefer capabilities (1, 2) over `requires`: the user keeps the choice of provider, and your plugin works with any.

## Library search and generate

A provider of `library.search` finds items in some source (Freesound, Pexels audio, Giphy…); a provider of
`library.generate` makes new ones from a prompt (AI music, stickers). Both return **candidates**; nothing enters the
library until the user or an agent saves one. Declare the kinds a provider serves, so the right panels offer it:

```json
"apiVersion": 6,
"capabilities": ["library.search"],
"providers": [
  {"id": "example.sounds.freesound", "capability": "library.search", "name": "Freesound", "kinds": ["audio"]}
]
```

The request's `params`:

| Field | Meaning |
|---|---|
| `kind` | The library kind wanted (`audio`, `sticker`, `look`…) |
| `query` (search) / `prompt` (generate) | What the user typed |
| `limit` | Most items to return (1–50; 12 for search and 4 for generate by default) |
| `page` (search) | Result page, from 1 |
| `params` (generate) | Hints such as `{"seconds": 30}`, passed through from `library generate --params` |
| `language` | The project's content language |
| `outputDirectory` | A fresh `0700` request folder for downloaded or generated files |
| `options` | The plugin's option values (API keys go in a `secret` option) |

The result is `{"items": [...]}`, at most `limit` library item objects. `kind` may be left out (it is the one asked
for; another kind is refused) and so may `id` (a missing, invalid or repeated one becomes `candidate-<n>`).
`file` and `preview` must be files in `outputDirectory` (absolute or relative to it, inside it after symlinks):
download or write them there. Give `source` (a URL or a note) and `license` so people can check them before use.
Each item is checked like a saved one of its kind (an `audio` item needs a `file`, a `sticker` an `emoji` or a
file, and so on); one bad item fails the request, and its folder is removed.

```json
{"items": [
  {"name": "Rain on a window", "file": "rain.wav", "preview": "rain.png", "tags": ["rain", "calm"],
   "source": "https://freesound.org/s/12345/", "license": "CC-BY 4.0", "params": {"role": "ambience"}}
]}
```

BashCut keeps the request folder under `~/Library/Caches/BashCut/LibraryCandidates` for a day. `library search` and
`library generate` run as jobs whose result lists the candidates with an `index`, `fileURL` and `previewURL`;
`library add --from-result <job>:<index>` (or the panel sheet's **Save**) copies one into the project or user
library with its source, license, the provider as `provenance` and the plugin in `createdBy.plugin`. Agents saving to
the user library wait for approval. Network access is the plugin's own: BashCut only starts it, as for any capability.
Use a provider `timeoutSeconds` for slow generation, and report progress over the session transport.

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
| `selection.changed` | `item` (primary), `items` (every selected item), `track` | Yes |
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
- At most 4 hooks run at once across all plugins (fewer on a Mac with fewer cores). Plugins take turns, so one
  edit heard by hundreds of plugins never starts hundreds of processes; `plugins hooks` shows the `queue`.
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

### Host channel (API 4)

Requests the app sends with a host channel accept two more lines while they run. Since API 4 that is `agent.chat`; since
API 8 also `view.render` / `view.event` and `plugin.action` requests of session plugins whose `apiVersion` is 8 or
later:

| Direction | Message |
|---|---|
| Plugin → app | `{"type":"event","id","event":{…}}`: handed to the caller in order; counts as activity like `progress` |
| Plugin → app | `{"type":"call","id","callId","method","params"}`: runs a BashCut command |
| App → plugin | `{"type":"callResult","callId","result"}` or `{"type":"callResult","callId","error":{"code","message"}}` |

- While a call runs, the request's silence timeout is paused.
- Calls on a request without a host channel get the error "This request cannot call BashCut".
- Call params and results are limited to 1 MiB.
- Views and actions (API 8) call as author `plugin`, with one command token per plugin, limited to the chat-agent
  commands plus `plugins.run`, `plugins.invoke`, `plugins.views` and `ui.notify`. Edits are validated and undoable
  and the history shows the plugin as their author. An action that edits through calls should return no
  `operations` of its own.

A worked example covering options, three actions, three hooks and both transports is
`Fixtures/plugins/example.toolkit` (Python standard library only).

## Chat agents

A plugin that provides `agent.chat` becomes a tab in the agent dock, titled with the plugin's name. Any number of
chat agents can be installed; AI Editor (`bashcut.director` in `bashcut-plugins`) is the first. The full protocol
is in [11 — Chat agents](../specs/11-chat-agents.md).

- **`turn`** sends:
  - `tools`: the BashCut commands the agent may call, as `{name, method, description, inputSchema}`. Everything
    except `agent.*`, `chat.*` and `ui.notify`.
  - `instructions` and `context`: a generic editing preamble, the command instructions, the project context
    and the timeline summary.
  - `kit`: the agent kit, as `{root, skillsFolder, version, skills: [{name, description}]}`.
- The plugin streams `event`s for the tab:
  - `text` and `thinking` deltas;
  - `tool` and `toolEnd` rows with `callId`, `name`, `ok` and `summary`;
  - the final `message`;
  - a `notice`.
- It runs commands with `call` lines. The app runs them through the same registry as Claude Code and Codex,
  with an agent token for that conversation. Edits need **Allow agent timeline edits**, and privileged commands
  still ask the user.
- The plugin never receives the automation socket or a token.
- The tab's transcript is saved per project in `.bashcut/chat/<plugin id>.json`. The plugin keeps its own
  conversation state.
- **Slash commands.** Typing `/` in the tab opens a menu:
  - the app's own commands for every agent: `/new` (`/clear`), `/stop`, `/settings`, `/copy`, `/export`;
  - `/skill:<name>` for each agent-kit skill;
  - the plugin's commands, which it lists with op `commands` (`{commands: [{name, args?, summary, choices?}]}`).

  When the user runs a plugin command, the app sends op `command` with `name` and `args`. The plugin answers
  `{text?, options?}`: `text` is shown in the tab, and `options` is a patch of its non-secret options that the
  app stores.
- **Input:** Enter sends, and Shift+Enter or Option+Enter starts a new line.
- **CLI:** `chat status`, `chat send <text> [--plugin] [--image]`, `chat transcript`, `chat stop`, `chat reset`,
  `chat commands`, `chat command "<line>"`, and `ui action agent.open-chat`.

## Terminal agents

A plugin that provides `agent.terminal` (API 5) adds an agent CLI, such as Gemini CLI, to the agent dock as a
terminal tab next to Claude, Codex and Shell. The CLI keeps its own interface and login, and reaches BashCut through
the bundled `bashcut-mcp` server with a token for that tab, like Claude Code and Codex. Use `agent.chat` instead when
the plugin runs the model loop itself against an API. The full protocol is in
[12 — Terminal agents](../specs/12-terminal-agents.md).

```json
"apiVersion": 5,
"capabilities": ["agent.terminal"],
"providers": [{"id": "dev.example.gemini.terminal", "capability": "agent.terminal", "name": "Gemini"}],
"terminal": {"icon": "sparkles", "environment": ["GEMINI_*", "GOOGLE_*"]}
```

- `terminal.environment` lists the variables the CLI may inherit (a trailing `*` is a prefix; `BASHCUT_*` and `PATH`
  are refused). Everything else in the app's environment stays out.
- Op **`launch`** gets `workspace`, `agentFolder` (a folder BashCut owns for the plugin's tabs), `project`, `prompt`
  (BashCut's instructions and the project context), `mcp` (`{name, command, arguments, environment}`), `kit`,
  `resume` and `canEdit`. It answers `{executable, arguments?, directory?, environment?, skillsFolder?}`: argv only,
  never a shell string. The plugin may write the CLI's config files in `agentFolder` first.
- Op **`session`** (optional) gets `workspace`, `agentFolder`, `project` and `notBefore`, and answers `{id}` with the
  newest session for the project, so the next tab continues it.
- **Skills stay in BashCut.** The plugin never ships the agent kit. It returns `skillsFolder` (inside `agentFolder`)
  and BashCut links the kit's skills there, or it tells the model where `kit.root` is.
- The plugin process never sees the token; only the terminal does, in `BASHCUT_SESSION_TOKEN`, for the MCP server.
- **CLI:** `agent terminals` lists what the dock can open; `agent open <id> [--new]` opens one.

## Commands

Everything above is available to agents through the CLI and MCP (`bashcut_plugins_*` tools):

| Command | Mode | UI equivalent |
|---|---|---|
| `plugins list` | read | Plugins sheet: availability, transport, actions, hooks, options, library packs, skills, provider kinds, container, views, requires (with state), uses |
| `plugins views` | read | The plugin icons in the left rail and their panels: views, tools, skills, requirements, uses; the host features |
| `plugins show-view <plugin> --view <id>` | ui | Opening a view where it lives: the rail panel, its dock tab or its sheet |
| `plugins view <plugin> [--view id] [--open]` | ui | Opening a view; returns its components and input values |
| `plugins view-event <plugin> --node <id> [--type …] [--value …]` | ui | Clicking, typing or selecting in a plugin view |
| `plugins invoke <capability> [--provider P] [--params '{…}']` | edit, job | None: a capability's raw result, for capabilities without a command |
| `plugins health [plugin]` | read | Check Health |
| `plugins actions [text] [--plugin id]` | read | Every contributed action (or those matching the text or plugin) with placements, `when`, shortcut, a JSON Schema for its params, whether it is enabled now and when it last ran |
| `plugins run <action> [--params '{…}']` | edit, job | Clicking the action and filling its sheet |
| `plugins hooks` | read | Hook Activity: subscriptions, the delivery queue (limit, running, queued, debouncing), recent runs, waiting proposals |
| `plugins proposal <id> --decision apply\|discard` | edit | The review sheet |
| `plugins options <plugin>` | read | Options… |
| `plugins option <plugin> --option <id> [--value <text>]` | edit | Editing an option; no value resets it |
| `plugins set <plugin> [--enabled off] [--hooks off]` | edit | The Enabled and Hooks switches (agents can only turn them off) |
| `plugins search [query] [--capability <id>] [--refresh]` | read | Browse |
| `plugins updates` | read | Updates |
| `plugins install <plugin> [--version <v>]` | edit, job | Install or Update in Browse: downloads and verifies, then shows the approval (only the user can approve) |
| `plugins remove <plugin> [--data]` | edit | Installed › Remove; `--data` also deletes the plugin's data and cache folders |
| `plugins setup <plugin>` | edit | Install Dependencies… (opens the approval; only the user approves) |
| `library search <text> --kind K [--provider P]`, `library generate <prompt> --kind K` | edit, job | A library panel's Search… and Generate… (API 6 providers) |
| `library add --from-result <job>:<index>` | edit | Save in that sheet |

`ui actions` lists plugin actions next to built-in ones and `ui action <id or shortcut>` runs them. An action with
parameters or `confirm` opens its sheet (dialog `plugin-action`); answer it with `ui respond run|cancel`, or use
`plugins run --params` instead. When `confirm` is declared, the action's job waits for the user in the
`plugin-confirm` sheet (unless the user already ran it from the parameter sheet, which shows the text, or Settings
allows all agent actions). Waiting never blocks the app: commands keep being answered, `jobs status` shows the job
running, and `ui dialog` lists the sheet. Only the user can choose Run; automation can only answer `cancel` (or
`jobs cancel` the job). Cancelling starts no plugin request. `ui open plugin-proposals` opens the review sheet.

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
- **Preflight:** the approval lists dependency probes and install commands without executing the pending
  archive or chosen folder. Dependencies are marked *Checked after approval*. Health checks run only for
  approved, unchanged, enabled, API-compatible plugins, including checks from Doctor and automation.
- **Space:** before approval, the estimate conservatively includes every declared dependency download and the
  archive. Installation requires at least 1.2 × this estimate in free space.
- **Repair:** when a probe reports a dependency with a recipe as missing (for example after a cancelled setup),
  Installed shows **Install Dependencies…**, which asks for approval and runs the recipes again
  (`plugins setup <plugin>` opens the same approval).
- Recipes should not depend on the Mac's own tools beyond `/usr/bin`: macOS ships Python 3.9 and no Homebrew.
  `bashcut.vieneu-tts` downloads `uv` into `BASHCUT_PLUGIN_DATA` and a Python into `BASHCUT_SHARED_DATA`, for
  example.

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
- Plugins own one panel each in the left rail (API 8), dock tabs and sheets, all with declarative views the app
  draws; they cannot own windows, webviews, inspector tabs or viewer overlays, or draw freely. Library packs and library search/generate
  (API 6) fill the existing library panels. Agent skills (API 7) join the agents' skills.
- The plugin registry (browse, install, update, remove, signatures, yanked versions, daily update check) is
  implemented.
- A credential contract and detailed capability permissions are future work.
