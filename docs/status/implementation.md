# Implementation status

What BashCut does at HEAD, how it was verified, and what is left. The full scope is the roadmap in
[09-roadmap.md](../specs/09-roadmap.md); the control-by-control UI audit is in [mockup-parity.md](mockup-parity.md).

## Summary

M0 is accepted on real DJI footage, and the refactor plan (R0–R6) is complete. Most of M1–M3 and M5 is in place,
with parts of M4 and M6. Agents reach every UI action and dialog through 46 CLI/MCP commands. Milestones M1–M6 are
not complete: several acceptance runs, bundled providers and the larger M4/M6 features remain.

## Milestones at a glance

| Milestone | Status | Notes |
|---|---|---|
| M0 Skeleton and engine spike | Done | Accepted on 20 HEVC DJI clips (table below) |
| M1 Core editor | Features in place | Hand-rebuild of the 48-cut reference and accessibility QA pending |
| M2 Agent dock and automation | Mostly done | Claude/Codex/Shell terminals, socket, CLI, MCP; real authenticated agent runs only partly smoke-tested |
| M3 Text, captions, export | Mostly done | Export queue (E-1) done; no bundled transcription provider; first all-in-app vlog not yet recorded |
| M4 Audio and voice | Partial | Ducking, loudness, voice takes, beats, framing done; music/SFX library and voice cloning open |
| M5 Color, transitions, review | Mostly done | LUTs, transitions, review, resume and handoff done; measured review checks open |
| M6 Extensions | Partial | OTIO export, voiceover recording, constant speed, ramps, keyframes done; effects, Demucs open |

## Implemented

### Project & storage

- Separate Git repository with SwiftPM (single target source) and XcodeGen configuration, committed lockfiles and
  verification scripts.
- Lossless project JSON (`bashcut.project/1`, described by the generated `docs/reference/project.schema.json`) with rational FPS, role-based dynamic
  tracks, atomic `EditOperation` batches, source/overlap/render validation, revisions and persisted undo/redo.
  Unknown fields round-trip.
- New Project wizard: name, aspect ratio, resolution, rational FPS, content language, destination and an
  optional footage symlink. Publication is exclusive and leaves existing folders and the current document intact
  on failure. Agents use the same code through `project create`, `project open` and `project save`.
- Atomic save, autosave every 30 seconds and on deactivation, recovery choice, restored history, and
  external-change handling with a reload/conflict sheet listing project, media, track and item differences.
- Project folders are watched with filesystem events, with an activation check as a fallback.
- Regenerable project caches live in `.bashcut/cache/` (excluded from Time Machine; older per-cache folders are
  moved in on open), and `.bashcut/.gitignore` lists them (written once on create or save); the plugin
  registry copy lives in `~/Library/Caches/BashCut/Registry` and an old Application Support copy is moved there
  once. The full layout is in [Storage on disk](../reference/project-format.md#storage-on-disk).
- Open projects from Finder (double-click or **Open With**) or by dropping a `project.bashcut.json` or its folder
  on the Dock icon. BashCut registers as an alternate app for JSON and folders, never the default.
- Media picked from the linked `footage` folder is stored as `footage/<file>`; older `../../…` paths into it are
  rewritten in one undoable edit when a project opens.

### Timeline & editing

- Mockup-based native layout: eight library tabs, media thumbnails and search, viewer with safe area, five
  Inspector tabs, history and review.
- Dynamic layers: repeated video/image, text and audio layers with explicit stacking order and vertical scrolling.
  Core validation enforces layer rules (visual above audio, one undeletable main layer, no overlap within a layer,
  matching media kinds) and repairs older projects on open. Placement spills CapCut-style onto the next free layer.
- Source viewer with In/Out and insert/overwrite; split, delete, ripple and lift (Shift-Delete); scroll, zoom and
  clip/beat snapping; drag move and trim.
- Atomic roll and slip from the Inspector, modifier-key timeline gestures and agent commands.
- Video with embedded sound creates linked Main/Dialogue items that move, trim, split, slip, roll and delete
  together in one undo step; the Inspector can unlink them.
- Dragging within a magnetic track reorders and compacts it; linked Dialogue follows.
- Automatic Change Framing cycles Wide, Medium, Close and left/right presets through validated `transform` and
  `reframePreset` properties; manual edits switch the item back to Custom.
- Freeze Frame, tags, transform and opacity, constant speed with optional pitch preservation.
- Still images (media kind `image`): import, drag in or `media import` a JPEG, PNG (transparency kept), HEIC or other
  image; it is placed for 3 s and trims to any length up to an hour. The engine reads it through a one-frame
  ProRes 4444 movie in `.bashcut/cache/stills/`, remade when the image changes.
- Keyframes (item field `keyframes`) animate zoom, pan, tilt, rotation and opacity of clips, images and text, with
  linear, ease-in/out/in-out and hold keys. Presets: slow zoom in/out and pans (Ken Burns), and fade, pop, slide-up
  and zoom-punch for text. Inspector › Animation, the diamond key at the playhead, and sliders that set keys once a
  property is animated; `clip motion` and `clip keyframe`. Split and start trims keep keys on the same picture.
- Volume keyframes: the `volume` property (dB, replacing `volumeDb`) on audio items and clips with sound, stacked
  with fades and ducking. The audio mix gets a point at each key plus steps between keys, so eases and the dB curve
  hold with AVAudioMix's linear ramps. Inspector › Audio › Keyframe volume at playhead; `clip keyframe --property
  volume`. Picture keys alone decide whether the compositor animates a layer.
- Word-by-word captions: `wordStyle` highlight (the word being said), karaoke (words said so far) or reveal (words
  appear as said), in the highlight colour `textStyle.highlight`. Timings come from the provider's word timings
  (`wordsPath`, stored as the caption's `words`) or are estimated from word length. Inspector › Text › Word by word,
  Auto Captions, `captions words`, `captions generate --word-style`.
- Edit menu (Cut, Copy, Paste, Select All) for text fields and terminals.

### Media & proxies

- Original-media import with probing, offline badges and metadata; thumbnails with debounced, quantized
  hover-scrub and source-time feedback.
- `@assets/...` media resolves through the configured workspace everywhere (thumbnails, source viewer, plugin
  inputs, preview, export); validation rejects unknown namespaces and traversal.
- Cached stereo waveforms read off the UI actor with cancellation and bounded peak data; refresh, progress and
  errors show in the timeline toolbar.
- Preview proxies (M-5): `ProxyManager` flags HEVC, larger-than-1920 px or above-20 Mbit/s video and writes
  `.bashcut/cache/proxies/<media id>.mov` (H.264, at most 960 px, keyframe every 10 frames, AAC, original frame times).
  `ProxyQueue` encodes one at a time as `media.proxy` jobs; the preview switches to each proxy as it lands and
  exports always read originals. `media proxy [--force]` and **Create Preview Proxy** make them by hand.
- The viewer scrubs with chase-time seeking: one exact seek in flight, newest target next.

### Text & captions

- Six shared Core Text presets (Bold Outline, Cinematic Serif, Keyword Sticker, Place Card, Hook Title, Chapter
  Card), editable styling, emoji text stickers and Vietnamese captions.
- SRT add, replace and export from the Text library and the CLI, with Unicode and multiline cues, rational-FPS
  conversion and one-step undo.
- Auto Captions resolves a healthy `captions.transcribe` provider, sends the media path and language, validates
  bounded UTF-8 SRT output and imports it atomically with provider provenance.

### Audio & voice

- Volume, mute and fades; automatic music ducking under tagged Dialogue and all Voiceover regions, with level,
  attack and release in integer frames, mixed the same way in preview and export.
- The Audio panel resolves `audio.beats`, validates BPM and beat times, maps them through trim and speed to
  timeline frames, and adds undoable beat-grid drawing and snapping.
- The Voice panel resolves a healthy `voice.synthesize` provider (with an undoable project preference), generates
  three confined, validated takes, and previews, scores, selects and inserts one with provenance. Discarded
  request folders are cleaned up.
- Direct voiceover recording asks for microphone permission, writes 48 kHz mono WAV under the project, shows
  duration and input level, and inserts at the playhead.
- Review warns when voiceover comes within 0.3 s of tagged speech on any layer.

### Color & transitions

- Exposure, contrast, saturation and basic looks (Original, Vivid, Muted film, Black & white).
- Adjustment layers: items with only a `color` grade (and LUT) that apply it to every layer below them while on
  screen, in preview and export; trimmable, movable, stackable and bypassed by hiding the layer
  (`adjustment add`, `layers add --kind adjustment`, Add Layer › Adjustment Layer, Filters › Add adjustment).
- Style kits (Food review, Cinematic): one undoable edit adds a full-length adjustment with the kit's look,
  replacing an earlier kit's, and sets the kit's caption preset on every caption (`style apply`). They replace
  the project-wide style setting, which was never read.
- Project-scoped `.cube` 3D LUTs with a validated catalog, undoable add/delete/apply, adjustable strength and agent
  operations; preview and export share one Core Image renderer. LUT files stay on disk when their catalog entry is
  undone.
- A synchronized vertical Before/After split in the viewer that bypasses color and LUTs only.
- Undoable transitions (dissolve, whip, blink, zoom, spin, shutter, wipe) with adjustable duration; preview and
  export share the same tweening, and transitions are removed when edits separate their clips.

### Library

- One item model for every library panel (#74): kind, tags, pack, source and license, created by, version
  history, usage and params, in project (`.bashcut/library`), user (Application Support), plugin and built-in
  scopes. `library list|get|stats|add|update|remove|move|save-selection|apply|place|import-pack|export-pack`;
  agents' user-scope writes need approval. Placing audio (#78) and image stickers (#64) are open.
- Transition presets (#77): kind, duration, easing (`linear`, `in`, `out`, `inOut`, stored on the transition and
  honored by preview and export) and an optional sound (`params.sfx`, an audio item, or the preset's own file),
  applied as one undo step with the sound on an SFX layer; saved from the selected cut, edited from the Transitions
  panel (Edit…, easing on the active transition) or `library update --params`.
- Library performance: use counts live in `usage.json` (an older `usage` field in `library.json` is read until the
  next save moves it), stored files keep their `fileSHA256`, and changes, packs, stats and use counting run on the
  `LibraryWorker` actor, off the main actor and one at a time.
- Built-in packs (#75): Text styles (the 6 caption presets), Emoji (8 stickers), Framing (Punch in 1.3×, Reset
  framing) and Transitions (Soft dissolve, Quick whip, Zoom punch).
- Shared panel UI (#80): the Audio, Text, Stickers, Effects, Transitions and Filters panels show their library items
  with search, pack, tag and scope filters (`ui view --library-*`), agent and scope badges, Add… and drops (files or
  packs), Save selection as… (text style, framing, transition, look) and a context menu (Duplicate & Edit, Rename,
  Move to project/this Mac, Show Source & License, Show in Finder, Remove). The item sheet is the `library-item`
  dialog. Voice stays provider-driven.

### Export

- One AVFoundation custom compositor for preview and export, including captions and the audio mix.
- Presets: TikTok, YouTube 1080p/4K, Quick Draft and ProRes; AAC 320 kbps; optional companion SRT.
- Background export queue (E-1): `ExportRequest` snapshots the project and refuses existing or already-queued
  outputs, `ExportPipeline` renders (with optional two-pass loudness normalization) and writes the SRT, and
  `ExportQueue` runs one export at a time on the shared `JobCenter`. The status bar shows step, progress and queued
  count; failed or cancelled output is removed.
- Receipts: the last 20 exports per project persist and compare duration, size, cuts, captions, tagged speech
  coverage and LUFS with the previous export.
- An optional `audio.loudness` provider enables target-LUFS normalization with a −1 dBTP ceiling, final
  measurement and undoable mix-gain/provenance persistence.
- OpenTimelineIO export (source/timeline rates, gaps, layers, text generators, speed, markers, BashCut metadata)
  from the Export sheet and the CLI.
- Legacy `edl.json` import (cuts, source ranges, borrowed picture, linked dialogue, transforms, tags, subtitles,
  voiceovers, section markers) into a new project, with a cut/voiceover/duration comparison report and warnings.
  Exporters and importers are listed in `TimelineFormats`.

### Agents & automation

- SwiftTerm Claude, Codex and Shell tabs with workspace/resume input, context and quick-action paste, current-frame
  attachment, ⌘K Ask, and a detachable, resizable Agent window.
- Terminals are `AgentProvider` conformances in one registry that drives launch, menus, Settings, bookmarks and
  discovery. Each terminal gets only an allowlisted environment, never the app's full environment or
  `ANTHROPIC_API_KEY`.
- Resume bookmarks persist per project and provider, outside source control; background discovery finds existing
  sessions and records new ones. Handoff opens the other provider with project, timeline, memo and skill context.
- Token-scoped local automation socket (mode 0600), the bundled `bashcut` CLI and the official-SDK `bashcut-mcp`.
  Claude and Codex get ephemeral stdio MCP configuration. Agents outside BashCut use a 0600 token file read by the
  CLI and MCP.
- 48 commands declared once as `CommandSpec`s, which generate validation, the CLI parser, MCP tools and agent
  instructions. Every button, menu item and shortcut is a `UIAction` (`ui actions`, `ui action <id|shortcut>`);
  every alert, panel and sheet goes through `ModalCenter` (`ui dialog`, `ui respond`, `ui open`).
- Agent edits keep a before/after diff, show ◆ markers and an Undo/Show Changes toast, and restore the latest diff
  after reopen. Edits are recorded in a metadata-only audit log.
- Privileged exports need a live token and an in-app approval sheet showing the concrete output; agents can only
  decline it. A Settings switch (off by default) runs agent exports without confirmation, audited as
  auto-approved.
- The model-API tab (Responses, Chat Completions, Anthropic Messages; one script or timeline proposal per request)
  was removed on 2026-10-04: without tools or the agent kit it could not finish a video. API keys work through the
  Claude Code and Codex tabs.
- Agent Knowledge (#100) keeps the project memo and project skills in the open project's folder (skills linked
  into the project's `.claude/skills` and `.agents/skills`), plus notes for every project in Application Support;
  never the agent workspace or home folder. A memo older builds left there is offered for migration
  (`knowledge migrate`); agent writes to the user notes need approval.
- The Knowledge window (#68) replaced the Agent Knowledge sheet: Lessons (search, scope/status/tag filters, sort,
  inline edit, approve/reject, enable/disable, delete, source and "New since last visit"), Preferences, Project
  facts, Notes and Skills. It polls the knowledge files' signature and reloads on change.
- The Knowledge inbox (#69): proposed lessons (kit changes tagged `kit` show their diff) and agents' preference
  changes for every project (`proposals.json`, applied on approval, editable first) with Approve / Edit / Reject;
  `knowledge proposals` lists both, `approve`/`reject` take `l-…` or `p-…` IDs. The dock's book button shows the
  proposal count, or a dot for entries changed since the last visit.
- A shared debug log (`~/Library/Logs/BashCut/debug.log`) written by the app, CLI and MCP bridge.

### Plugins

- Versioned out-of-process `bashcut.plugin/1` manifests discovered in project, user and bundled roots, with a
  Plugins installer that shows exact install commands before approval and reports dependency health. Agents can
  cancel but not approve an install.
- `CapabilityService` is the single path from a capability request to a validated, provenance-tagged result. Each
  capability is one `CapabilityAdapter`; calls go through a `PluginTransport`, with `PluginProcessRunner` as the
  one-shot process transport (one bounded child per request, filtered environment, process-group cancellation).
- `captions.generate`, `beats.detect` and `voice.speak` run as background jobs with `jobs.status`/`jobs.cancel`
  and apply one undoable agent-attributed edit; `plugins.list` and `plugins health` report providers,
  availability and diagnostics. See [plugins.md](../guides/plugins.md).
- Plugin API 2: an API window (`minApiVersion`/`maxApiVersion`), SHA-256 trust pins with user-only Trust and
  enable switches (states ready, disabled, untrusted, changed, outdated), native `options` per user or project,
  `contributes.actions` in fixed placements (Plugins menu, toolbar, clip/track/timeline/media context menus,
  library panels, inspector tabs) with `when` conditions and parameter sheets, and `contributes.hooks` for 19
  editor events (debounced, rate-limited, notify-only; hook edits wait for review unless Settings applies them).
  Results propose operations and a per-plugin `pluginData` entry committed as one undoable `plugin` edit.
  `PluginSessionTransport` (handshake, NDJSON, progress, cancel, idle shutdown, crash restart) runs plugins that
  ask for it. Commands: `plugins actions|run|hooks|proposal|options|option|set`; plugin actions also go through
  `ui actions`/`ui action`. Worked example: `Fixtures/plugins/example.toolkit`.
- Catalog refresh performance (#103): discovery keeps manifests in a `PluginCatalogCache` and reads a plugin again
  only when its `plugin.json` or entrypoint changes (stat identity, mode, size, mtime, ctime). A refresh shows each
  plugin's availability from the last file check (`PluginTrustStore.knownAvailability`); plugins not checked yet in
  the session, or whose manifest or entrypoint changed, are checked off the main actor in parallel and show
  "Checking…" until then. Running a plugin, Reload and `plugins list` for an unchecked plugin still walk every
  file. Measured in release (`scripts/verify.sh perf`, M1 Max): 1000 plugins × 5 files refresh in ~33 ms
  (was ~400 ms on the main actor); 100 plugins × 2000 files in ~3 ms (was ~360 ms, and ~11 s after a relaunch).

### Settings & diagnostics

- Settings persist the workspace, default agent, agent edit permission, external-agent token, export auto-approval,
  default export preset, interface language and recent projects. Turning off edit permission revokes live tokens
  at once.
- Doctor reports workspace access, Claude/Codex and optional tool discovery, socket status, agent instructions and
  skills, project folders, plugin catalog diagnostics and live dependency health (`doctor run`).

### Localization

- English and Vietnamese resources for current controls (`Localizable.xcstrings` plus both `Localizable.strings`),
  with an interface-language override in Settings.

## M0 engine acceptance on real DJI footage (2026-10-02)

`bashcut-bench` (`Tools/Bench`) on 20 vertical DJI clips (HEVC Main10 `hvc1`, 1080×1920, 29.97 fps, about 30 Mbit/s;
30.03 s timeline with reframes and a Vietnamese caption per clip), MacBookPro18,4 (M1 Max), release build:

| Metric | Originals | With proxies (`--proxies`) | Budget |
|---|---|---|---|
| Composition build | 37 ms | 14 ms | — |
| Decode through the compositor | 324 fps | 355 fps | — |
| AVPlayer playback, 10 s | 300/299 frames, 0 dropped | 300/299, 0 dropped | ≤ 1 % dropped |
| Scrub p95, AVPlayer exact seek to a decoded frame | 19.6 ms (p50 12.5, max 19.9) | 8.9 ms (p50 7.2, max 9.5) | < 100 ms |
| Scrub p95, AVAssetImageGenerator (reference) | 34.8 ms | 18.6 ms | — |
| Export 30 s H.264 (always originals) | 3.33 s (9.0× real time) | 3.33 s | > 1× |
| Proxy generation, 20 clips | — | 4.3 s | — |

All budgets pass with and without proxies. The earlier failing figure (p95 138 ms) measured AVAssetImageGenerator
before the compositor rewrite and asset cache; the viewer seeks through AVPlayer, which the bench now measures.
Re-run it after engine changes:

```bash
swift build -c release --product bashcut-bench
.build/release/bashcut-bench <footage-dir> --clips 20 [--proxies]
```

## Feature bench (2026-10-06)

`scripts/bench-features.py [--only groups] [--stress N] [--keep]` against the running app (debug Xcode build, M1
Max): 219 checks. After the fixes in the same change, nothing fails; open notes:

| Finding | Detail |
|---|---|
| Re-importing a file | `media import` of a file already in the project adds a second media entry (no reuse) |
| Edits that change nothing | still make a revision and an undo step |
| Slow service commands (UI stays responsive) | `agent status` ~0.9 s, `chat status` ~0.5 s, `storage get` 0.3–0.6 s |
| Edit cost at scale | one `setProperties` round trip: 27 ms at 100 clips, 78 ms at 1000 (release build; core alone is ~3 ms). About 60% of the main thread is `TimelineCanvas.draw` repainting the whole visible timeline after each edit (clip titles, filmstrips) |
| Edit cost at scale, fixed (#348) | the real cost was Core Animation rasterizing every visible clip (`CA::CG::Queue`, the main thread waits for it in `CABackingStoreGetFrontTexture`), not the draw calls. The canvas now diffs the drawn project against the new one and repaints only changed clips and gaps (`TimelineCanvas+Invalidation.swift`); the header repaints only when layers change. Release, M1 Max: 1,000 clips 52.5 → 22.9 ms per edit (100 edits 4.3 → 2.2 s, 100 undos 4.3 → 2.0 s); 100 clips 27 → 15.6 ms. Most of what is left is SwiftUI updating other views |
| Export | once, `context get` waited 0.6 s while an export finished; not reproduced in three reruns |
| Known gaps | `library place` of audio and sticker items (#78, #64) |

## Agent automation latency (2026-10-03)

`scripts/bench-automation.py --edits 5` against the running app (debug build from `scripts/run.sh`, a 16:9 project
with 44 items and 18 media, M1 Max). p50 values, before → after the agent-latency fixes:

| Path | Before | After |
|---|---|---|
| Socket `context get` / `timeline get` (JSON, 7 KB) | 0.1–0.4 / 1.0 ms | unchanged |
| MCP `context get` | 11.7–15 ms | 2–3 ms |
| MCP `timeline get --format text` | 13–23 ms | 3–4 ms |
| MCP `timeline get` (JSON) | 40–45 ms | 11–14 ms |
| MCP start + initialize | 95 ms | 9–13 ms |
| MCP `tools/list` (73 tools with schemas, once per session) | 50–60 ms | 50 ms, then 1.6–1.8 ms (core scaling) |
| Edit → `ui frame` ready | ~255 ms (first 1.2 s) | ~230 ms, then ~210 ms (core scaling) |

Causes fixed: the MCP SDK's stdio transport polled stdin/stdout every 10 ms (`MCPBridge/BlockingStdioTransport.swift`
blocks instead); every result was sent twice (pretty text and `structuredContent`) and the SDK re-decodes structured
results through Codable at about 1 ms per KB (now compact text only, also about a third fewer tokens); preview
readiness and `ui frame` polled every 100 ms (now 10 ms); the debug log JSON-encoded whole results on the main actor
before truncating them (now a bounded writer).

Core edit cost on synthetic projects: `swift run -c release bashcut-core-bench` in `Packages/BashCutCore` (20
media; 60% of the items on the main layer with a dissolve at every tenth cut, 20% captions, 20% music). p50 at
100 / 500 / 1,000 items, before → after the core-scaling fixes:

| Measure | Before | After |
|---|---|---|
| One `setProperties` edit | 0.97 / 8.0 / 24 ms | 0.6 / 1.5 / 3.1 ms |
| Ripple delete | 1.0 / 9.6 / 30 ms | 0.5 / 1.5 / 3.2 ms |
| Undo | 1.4 / 11 / 34 ms | 0.3 / 1.5 / 3.0 ms |
| `validate()` of a changed project | 0.5 / 3.2 / 9.2 ms | 0.4 / 1.3 / 2.6 ms |
| 200-step history journal | 1.9 / 6.9 / 13 MB | 0.02 / 0.1 / 0.1 MB |
| Journal encode / decode | 0.14 / 0.52 / 0.97 s, 0.77 / 2.9 / 5.5 s | 5 / 21 / 35 ms, 14 / 48 / 66 ms |
| MCP `tools/list` (bridge alone / with the app's plugin actions) | 35 / 50 ms | 0.1 / 1.7 ms |
| Edit → `ui frame` ready (running app, 44 items) | ~230 ms | ~210 ms |

What changed:
- `Project` keeps `tracks` (and each `Track` its `items`) as typed stored arrays. Before, every item mutation
  rebuilt the layer's and the project's arrays from JSON, so one ripple was O(items²). `fields` is now computed
  (whole JSON for encoding); single keys are read through the subscript.
- Validation built a sorted copy of a video layer for every transition (80% of an edit at 1,000 items); `VideoCuts`
  indexes the cuts once. Media lookups use a dictionary; item properties are checked by walking the item's own keys.
- A project remembers that it passed `validate()` until it changes, so `applying` validates once per edit, and the
  preview builder and saves skip it.
- The history journal stores each step as a `ProjectDelta` against the next newer state (runs of unchanged items
  are `[start, count]`). Old full-snapshot journals still load.
- The preview builds the new composition in a fresh `AVPlayer`, waits until it is ready at the playhead and swaps
  it in; the viewer keeps the previous picture instead of going blank. `ui frame` does not wait for the swap: it grabs
  from `PreviewController.currentBuild`, the new composition as soon as it is built.
- Edits that keep what plays where (colour, text, opacity, transform, keyframes, volume, fades) no longer load a
  new player: the builder hashes the composition's tracks and segments (`CompositionSnapshot.structure`), and when
  the hash matches what is shown, the shown player item takes the new video composition and audio mix and redraws
  the playhead frame. With 40 clips, such an edit is on screen about 7 ms after the 50 ms debounce, against about
  110 ms for a swap.
- `bashcut-mcp` answers `tools/list` itself from the catalog encoded once; the SDK encoded the 35 KB list through
  its `Value` tree on every call.

Render hot paths after keyframes and word captions (2026-10-04): playback and export stay within budget
(`bashcut-bench`, 14 DJI clips: 315 fps decode plain, about 255 fps with every clip keyed and karaoke captions; the
difference is the per-frame transforms and opacity, not text). The text cache key (the whole item JSON-encoded) and
the keyframe anchor are made once per text layer instead of per frame; the Inspector reads the playhead only in the
*Keyframe at playhead* buttons; `placedCues` binary-searches the words near each cue.

Still open: timing edits (trim, move, speed, new clips) still build and load a whole new composition (patching the
shown `AVMutableComposition` in place would need engine work), and the remaining per-edit cost is one full
`validate()` (about 2.6 µs per item).

### LUT rebuild cache (2026-10-04)

Reproduce with `scripts/verify.sh test --filter LUTBuildTests`. Generated fixture: one 30-frame video item and
one 64³ LUT; warm the builder, then measure five opacity edits. Debug build on this M1 Max; milliseconds:

| Metric | Before (`04b87fc`) | Persistent parsed-LUT cache |
|---|---|---|
| Median `CompositionBuilder.build` | 2165.721 | 0.315 |
| Parsed LUT loads across warm-up + five edits | 6 | 1 |

This measures rebuild work only, not player readiness or end-to-end display latency. The first parse still has
its original cost. The cache is bounded to 64 MiB, keyed by resolved URL and freshly read modification time,
size and inode. Tests cover reuse, replacement, deletion, dimension validation and least-recently-used eviction.

## Verification

### Automated tests

2026-10-04 rework: the Vietnamese caption golden is captured directly from the shared compositor, before
hardware H.264 encoding. Player readiness and export metadata/non-black picture are separate tests. Full build,
app/core tests and strict lint pass. A deliberate missing-caption mutation fails the golden comparison.

The latest full runs pass 294 tests: 143 in the app modules (`Tests/`) and 151 in `Packages/BashCutCore`. The
Swift 6 build and strict SwiftLint pass.

- **Core:** inverses, revisions and atomic failure; ripple and source timing; linked A/V, magnetic reorder and
  reframing; transitions; LUT catalog; freeze frame; ducking and audio validation; shared-media traversal and
  symlink confinement; legacy EDL import; OpenTimelineIO export; unknown fields; render bounds; review rules and
  voiceover proximity; layer rules and repair; diffs; plugin catalog, provider resolution, process isolation and
  health; the op-keyed codec and an apply→undo→redo round trip for every operation; history depth capping.
- **Engine:** golden frames with Vietnamese captions, grayscale and opacity, mute, six caption presets, ducking and
  `AVAudioMix` ramps, transition tweening, `.cube` rendering, freeze frames, time mapping through one million
  frames, media sources and proxy detection. Waveform tests use generated stereo audio and test range queries,
  disk-cache recovery and invalidation.
- **Storage:** reopen and history, stale saves, autosave recovery, damaged caches, export history; project
  creation with Vietnamese folder names, footage preservation, invalid input, collisions and staging cleanup.
- **Automation and agents:** authorization, revocation, wire decoding, 0600 socket round trips and concurrent
  clients; command-spec consistency (names, MCP schemas, defaults, CLI parsing, agent instructions); UI actions;
  isolated Claude/Codex MCP and resume launches; session discovery.
- **Plugins and document:** capability service with fake transports (resolution, health fallback, output
  confinement, take scoring and cleanup, loudness provenance); export queue, proxy queue, preview, file sync,
  settings, modal center and automation controllers with fakes.

`scripts/verify.sh perf` repeats the engine test at 20 synthetic clips; it is not a substitute for the real-footage
bench above. It then times a plugin catalog refresh with 1000 generated plugins (and 100 with 2000 files each)
and fails above 50 ms.

### Native smoke tests

- **New Project:** name, landscape, destination and creation; the editor showed 1920×1080 at 29.97 fps.
- **Export:** Quick Draft with captions rendered a 720×1280 H.264/AAC file while the editor stayed usable, then
  showed a 3.00 s / 3-cut / 1-caption / 542 KB receipt; the SRT and `bashcut export status` were checked.
- **Privileged export from the embedded Shell:** the first request was denied and wrote nothing; the second showed
  author, preset, output and SRT, was approved and rendered. Both decisions were audited.
- **Shell:** read context, applied a caption edit, saw it in preview and timeline, undid once; an external CLI edit
  without a token was rejected.
- **Codex:** started in the embedded terminal, read context and timeline, applied one operation through the socket
  (revision 21 → 22), surfaced the agent diff and restored the caption with Undo (revision 23).
- **Source viewer:** inserted source frames 11–33 as exactly 22 timeline frames, undid, then overwrote without
  extending the timeline.
- **Earlier:** opened synthetic footage, seeked, split, saved and reloaded external changes.

## Known limitations / remaining work

- **Acceptance:** the M1 hand rebuild of the 48-cut reference, the M3 all-in-app vlog, broader accessibility QA,
  UI automation tests, and real authenticated Claude/API tasks are not verified. Provider-backed jobs are not yet
  smoke-tested with a real agent and an installed provider.
- **Native checks outstanding:** waveforms, the standalone SRT file pickers, modifier-key trim gestures, and live
  microphone permission and metering.
- **Xcode:** the generated project builds with signing disabled and package-plugin validation skipped for the
  locked SwiftTerm build plugin.
- **Automation:** voice-enrollment approval; analysis and interchange providers still need wiring to their panels.
- **Plugin platform:** plugin-owned panels and a credential contract ([03-architecture.md](../specs/03-architecture.md) §5).
- **M3–M6:** bundled transcription provider and real-engine acceptance, music/SFX library with BPM and license
  badges, voice cloning, expanded legacy effect/overlay/SFX import, effect recipes, keyframes,
  Demucs, and more interchange validation. Resolve remains reserved.
- **Review and loudness:** coverage uses explicit speech tags and voiceover timing; it does not measure silence or
  transcribe untagged audio. Export loudness is measured only when normalization is on (the core `bashcut.audio-analysis` plugin provides it).
- **Editing scope:** ripple affects the edited track and its linked counterpart only. Source insert/overwrite
  targets Main. Unknown future effects round-trip but are not rendered.
- **History:** full-snapshot undo is capped at 200 steps; `history.jsonl` stores one atomic checkpoint, and an
  append-only journal with compaction is pending.
- **Localization:** some dynamic diagnostic messages are still English; full localization QA is pending.

### Repeated-media build lookup (2026-10-04)

`swift test --filter MediaSourceTests/repeatedSource` uses 240 one-frame cuts of generated video, warms the
builder, then measures five Debug builds on the same M1 Max. Before (070b6c1): median 41.294 ms and 1,440
source resolutions across six builds. After per-build media/item dictionaries and loaded-media reuse: median
23.075 ms and six resolutions. The test asserts one resolution per media per build and verifies that a proxy
created between builds is selected. These timings measure composition construction, not player readiness.

### Caption interval sweep (2026-10-04)

`swift test --filter CaptionBuildTests` constructs 1,000 sequential three-frame captions, verifies every
instruction's caption ID and measures three Debug builds on the same M1 Max. Before (b4db9bf): median
390.820 ms. After sweeping start/end events with an active layer set: 16.692 ms (about 23× faster).
`IntervalSweepTests` compares overlapping, unsorted, empty, skipped and repeated boundaries with the previous
half-open interval filtering rule, retaining original layer order. This measures construction, not rendering.

### Audio composition lanes (2026-10-04)

`swift test --filter AudioLaneTests/sequential` measures 240 one-frame audio cuts from generated AAC media,
three Debug builds with a muted AVPlayer on this M1 Max. Before (22cce9d): 240 tracks, median construction
19.420 ms and build-to-ready 717.611 ms. With shared lanes: one track, construction 18.793 ms and
build-to-ready 93.591 ms. Separate earlier construction-only runs were 8.912 vs 15.446 ms: fewer tracks do not
necessarily make construction faster, but the player readiness improvement is substantial in this fixture.
Tests verify independent overlapping project layers, pitch-mode separation, ramp reset after fades and gaps,
and decoded PCM RMS retaining a -20 dB step at a shared-track clip boundary. Readiness is polled every 1 ms;
these timings are local observations, not portable thresholds.

### Bounded caption rasters (2026-10-04)

`CaptionRasterTests` compares cropped and full-canvas reference drawing for six presets at landscape and
portrait sizes, three vertical positions, Vietnamese accents, emoji and thick outlines. Every RGBA channel
stays within one 8-bit level (integer-translated CoreText antialias quantization); animated word variants
also match within one level. The existing pre-encode caption golden remains unchanged. A 3840×2160
“Xin chào” raster occupies 303,104 bytes versus 33,177,600 bytes for a full canvas, about 109× smaller.
This is CPU bitmap storage, not a measurement of GPU upload time. The cache retains the positioned CIImage,
and the compositor reuses it without constructing a wrapper on each frame.

### Prepared picture keyframes (2026-10-04)

`PreparedMotionTests` compares the previous `ItemMotion.value` scan with prepared segments plus binary search
on the same M1 Max Debug run. For 10,000 picture samples (all five properties plus transform), two keys per
property take 20.014 → 14.213 ms; 1,000 keys per property take 2,042.708 → 31.427 ms. The checksum includes
transform and opacity. These are interpolation/transform costs, not total render throughput. Tests cover every
easing mode, exact hold boundaries, negative/shifted keys, reverse seek order, fractional FPS, static defaults
and transition holds. The compositor clamps local time once and samples typed channels together.

### Native test isolation (2026-10-04)

`verify.sh test` runs app suites in parallel again, then the two Unix-socket suites (`AutomationTests`,
`AutomationControllerTests`) in a quiet sequential pass; core model tests remain parallel. The earlier global
`--no-parallel` hid five `EngineControlsTests` that read generated media without awaiting its generation
(AVFoundation -11800/-17913 when run first); they now await `TestFixtures.requireMediaRoot()`. The socket
suites' latency assertions and client timeouts fail only while CPU-bound render suites saturate the machine.
App suites take ~29 s instead of ~65 s on this host.
The audio lane benchmark now waits for paused readiness instead of starting/stopping playback between
samples. On this host, immediate playback left later items at `.unknown`; paused readiness passed all
three iterations (27.773 ms median build-to-ready in the isolated check). No timeout or correctness
assertion was loosened. Native ramp playback/export coverage remains separate.

### Long export baseline (2026-10-04)

Run `BASHCUT_LONG_EXPORT_BENCH=1 BASHCUT_BENCH_SHA="$(git rev-parse HEAD)" scripts/verify.sh test --filter LongExportTests`.
The opt-in benchmark exports 200 generated-media cuts, 9,000 frames / 300.3 seconds, at 160×90 with AAC,
then reads the encoded video to verify every frame, the audio track and duration. It prints a JSON report
with Git SHA, OS, dimensions, duration, bytes, elapsed export seconds and throughput. It is intentionally
small in pixel dimensions to expose sample-transfer overhead; it is not a 1080p/4K export claim.
Baseline `e760321` on this M1 Max / macOS 15.7.7 Debug run: 22.811 seconds, 394.545 frames/s,
43,566,760 bytes. This is the baseline before C1's callback-driven sample pump.

### Readiness-driven export transfer (2026-10-04)

The C1 worktree based on `3cfd5dd` completes the same long-export scenario in 9.651 seconds (932.523 fps),
versus 22.811 seconds before, about 2.36× faster. Both verify 9,000 encoded frames, audio and timeline duration;
these low-resolution numbers isolate sample-transfer overhead and do not represent 1080p/4K performance.
Each reader/writer pair has a dedicated serial queue and drains only while the writer input is ready.
A 100 ms health check handles terminal native failures that may not trigger another readiness callback;
it does not pace samples. Cancellation interrupts native reading, then drains every stream queue before
returning to writer cleanup, so no append can race cleanup. Tests exercise controlled backpressure,
blocked-read cancellation, cancellation before registration, read errors and failures while all inputs
are not ready. Native tests cover video-only, audio/video, ProRes, ramped export, compositor failure,
publication/cancellation cleanup and destination races.

### Audio-only loudness measurement pass (2026-10-04)

`RenderEngine.exportAudio` writes 48 kHz, stereo, float PCM in CAF through the same mixed-audio reader and
atomic publication path as full export, with no video reader/compositor. The normalization pipeline uses
this file for its first measurement, applies the gain through `EditOperation`, exports the final movie and
still verifies that encoded movie. Temporary PCM is removed on success/failure. PCM uses more temporary
space than AAC (115,319,296 bytes for this five-minute fixture), in exchange for avoiding a lossy first pass.
The same C1 fixture on the C2 worktree takes 9.886 seconds for the full movie versus 0.264 seconds for PCM.
This compares **measurement rendering only**, excluding the loudness analyzer and final encode.

Tests deliberately install a failing video compositor: audio-only measurement succeeds without invoking it.
Native normalization with gain, fades and volume keys reaches −20 LUFS within 0.3 LU using the bundled meter;
the actual encoded movie is measured again and temporary files are absent afterward. Tests also cover an
analyzer failure, no-audio projects, stereo PCM format/duration and both pitch modes of ramped audio.

Full verification for this change: SwiftPM build/test/lint passed (114913/114915/115043), and
`verify.sh xcode test -parallel-testing-enabled NO` passed 243 tests in 76 suites (115043).
The Xcode test target now explicitly links `BashCutAudioAnalysis`. CI wiring remains a separate open item.

### Export buffer and codec settings (2026-10-04)

C4 disables `alwaysCopiesSampleData` for video/audio readers, sets H.264 High AutoLevel, expected source
frame rate and a two-second maximum keyframe interval, and enables MP4 fast-start metadata placement.
ProRes remains intra-frame and does not receive H.264-only settings. Native tests parse MP4 top-level boxes
(`moov` before `mdat`), AVC profile metadata, rational frame rate, all 225 encoded frames, sync-picture
spacing and decoded start coverage. Marker buffers are excluded from sync-picture checks; B-pictures may
present before the first sync picture. MP4/ProRes, PCM, error and cancellation tests continue to pass.

The five-minute fixture is 9.834 s / 915.231 fps / 42,968,270 bytes, versus C2's 9.886 s / 43,562,566 bytes;
throughput is effectively unchanged at this scale. No broader speedup is claimed. Full build/test including
the long benchmark/lint passed 120222/120225/120412. Fast-start creates an encoder sidecar on some failures,
so each export now owns a private 0700 staging directory and removes that entire directory after publication
or failure. The final path is still published with an exclusive same-filesystem rename.

### History availability (2026-10-04)

Document action validation now uses `canUndo`/`canRedo` instead of materializing arrays of snapshot entries.
`HistoryAvailabilityTests` checks 10,000 pairs at 199 undo entries and one redo entry: 28.583 ms for the old
array path versus 2.753 ms for the direct accessors (M1 Max, Debug). This is a small per-call saving, not an
overall edit-latency claim. The test also verifies availability and the top label before editing, after undo,
redo, exhausting the stack and branching after undo.

### Hosted verification (2026-10-04)

The macOS 15 arm64 / Xcode 26.3 workflow runs SwiftPM build, full app/core tests and CLI/MCP subprocess
tests, strict lint, and Xcode build/test on every pull request. Logs and failed snapshot images are retained.
[Run 37181160682](https://github.com/dongnguyenvie/BashCut/actions/runs/37181160682) at `1b9e228` passed all
steps. Its first predecessor exposed device-dependent RGB fixtures and H.264 source variation in a caption
golden. Explicit sRGB fixtures and a black compositor background fixed those dependencies without relaxing
image thresholds. Local Xcode verification also passed 245 tests in 77 suites.


### Native fixtures and discontinuous audio gain (2026-10-04)

Tests generate a shared, per-process temporary H.264/AAC fixture with AVFoundation: 60 moving 320×180
frames at 30000/1001 and a 48 kHz mono sine tone. The video input explicitly uses a 30000 timescale;
default writer rounding otherwise changes fractional frame timestamps. The standalone `bashcut-fixtures`
executable uses the same generator. CI needs neither ffmpeg nor a manual fixture step. Tests check every
frame timestamp, codecs, dimensions, duration, audible PCM, concurrent requests, cancellation before
publication and preservation of an existing destination.

The new fixture exposed a native audio-mix regression at adjacent clips with different gain. A -20 dB
cut decoded at a 0.7385 amplitude ratio instead of 0.1, despite correct `getVolumeRamp` metadata. The
failure also reproduces with generated PCM, so it is not confined to AAC priming. Touching discontinuous
envelopes now use different composition lanes; a lane becomes reusable after a gap or at a continuous
gain boundary. Four adjacent 0/-20/-6/-14 dB clips use two lanes and decode within the existing 0.005
amplitude tolerance on both AAC and PCM, with spectral and varispeed pitch modes. The 240-cut constant-gain
fixture still uses one lane. No ramp timestamps or correctness thresholds were relaxed.
