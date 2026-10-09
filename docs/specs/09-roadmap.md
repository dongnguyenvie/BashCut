# 09 — Roadmap

Each milestone must be usable on its own. Estimates assume one developer working with an agent. The engine and
the timeline are the hardest parts, so they come first and are measured early. Current progress per item is in
[implementation.md](../status/implementation.md).

## Status

| Milestone | Scope | Status |
|---|---|---|
| M0 | Skeleton and engine spike | Done; accepted on real DJI footage (2026-10-02) |
| M1 | Core editor | Features in place; hand-rebuild acceptance and accessibility QA pending |
| M2 | Agent dock and automation | Mostly done (46 CLI/MCP commands, Claude/Codex/Shell); full real-agent acceptance pending |
| M3 | Text, captions, export | Mostly done (export queue E-1 done); first vlog made entirely in the app not yet recorded |
| M4 | Audio and voice | Partial: ducking, loudness, voice takes, beats, framing done; music library and voice cloning open |
| M5 | Color, transitions, review | Mostly done; measured review checks and automated fixes open |
| M6 | Extensions | Partial: OTIO export, voiceover recording, constant speed done |
| — | Refactor rounds R0–R6 | Done ([10-refactor-plan.md](10-refactor-plan.md)) |

## M0: Skeleton and engine spike (≈ 1 week)

**Repo setup.** Create the `bash-cut/` repo with `project.yml`, `Configs/`, `scripts/verify.sh`, `AGENTS.md`,
`.claude/rules/`, SwiftLint, `CHANGELOG.md` and the third-party list
([third-party.md](../reference/third-party.md)).

**Packages.** Add swift-collections and swift-snapshot-testing.

**Project model.** `BashCutProject` gets the model, the basic `EditOperation`s (insert, delete, split, trim,
move), apply and inverse, and tests.

**Engine spike:**

1. Composite 20 DJI clips at 1080×1920 with reframes and one Core Text caption layer.
2. Play them through `AVPlayer` with the custom compositor.
3. Export 30 s with `AVAssetWriter`.

**Done when:**

- playback is smooth at 29.97 fps;
- scrub latency is under 100 ms;
- export is faster than real time;
- `verify.sh build`, `test` and `lint` pass.

If the spike misses these targets, revisit the engine design (for example, mandatory proxies) before building
the UI.

**Result:** accepted. `bashcut-bench` on 20 HEVC DJI clips plays with no dropped frames, scrubs at p95 19.6 ms
(8.9 ms with proxies) and exports at 9× real time.

## M1: Core editor (≈ 3–4 weeks)

- **Projects:** Welcome screen; New Project, including the footage symlink; save, autosave, undo; reload when
  the file changes on disk.
- **Media library:** thumbnails and hover-scrub; source viewer with In/Out and insert.
- **Timeline:** magnetic Main, Overlay and Captions tracks plus four audio tracks; split, delete, trim, move and
  snapping; clip roles and sections.
- **Viewer and Inspector:** viewer, Inspector with transform and volume, waveforms.
- **System:** Doctor, Settings, English and Vietnamese strings.

**Done when:** the `lau-bo-noi-dat` cut (48 cuts) can be rebuilt by hand with no stutter or lag.

## M2: Agent dock and automation (≈ 2 weeks)

**First, verify** the **(to verify)** items in [05-agent-integration.md](05-agent-integration.md) and
[04-dependencies.md](04-dependencies.md).

- **Dock:** SwiftTerm tabs for Claude, Codex and Shell, with the working directory set to the workspace.
- **Automation:** the automation socket, the `bashcut` CLI (swift-argument-parser) and `bashcut-mcp` (MCP Swift
  SDK); commands `context`, `project`, `timeline get/apply`, `media list`, `ui *`.
- **UI pieces:** ⌘K popover, context chip, ◆ badges, undo toast.
- **Workspace side** (done by an agent working in the workspace): a "BashCut projects" section in `CLAUDE.md`,
  `AGENTS.md` and `.agents/skills`, and the `nolan-bashcut` skill.

**Done when:** you select a clip, press ⌘K and type "trim to 4 s"; Claude makes the edit, the ◆ badge appears,
and ⌘Z reverts it. The same flow works with Codex.

## M3: Text, captions, export (≈ 2–3 weeks)

This milestone produces **the first vlog made entirely in the app**.

- Text with the Bold Outline and Cinematic Serif presets, inline editing and the TikTok safe area.
- Auto Captions through a `captions.transcribe` plugin (WhisperKit is one candidate after checking Vietnamese
  accuracy) and `.srt` export.
- Export: TikTok and YouTube presets, a background queue (E-1, done), post-export numbers.
- Import from `edl.json`.

**Done when:** a new video is cut and exported entirely in BashCut, ready to publish, and importing
`lau-bo-noi-dat` matches 48 cuts and 109.81 s.

## M4: Audio and voice (≈ 2–3 weeks)

- Music and SFX library with BPM, loudness and license badges.
- Ducking, and −14 LUFS normalization through an `audio.loudness` provider (libebur128 is one possible
  implementation).
- Plugin catalog, health, install approval and provider resolution for voice, captions, beats and loudness.
- Voice tab: generate three takes through `voice.synthesize`, score them and insert one into Voiceover. The
  Clone New Voice wizard is a separate provider capability.
- A warning when the voiceover overlaps real speech.
- Beat detection, beat snapping and automatic change framing.

## M5: Color, transitions, review (≈ 2–3 weeks)

- LUTs and basic adjustments, with a before/after view.
- Transitions: dissolve, whip, blink, zoom.
- Full Review panel with Ask Agent to Fix.
- Quick actions, session resume, Claude ↔ Codex handoff.

## M6: Extensions (as needed)

- Effect library from `recipes.json`: animated overlays, text animation, stickers.
- Speed ramps, simple keyframes, Demucs separation, direct voiceover recording.
- OTIO export.
- Structured chat mode.
- Signing, notarization, DMG and Sparkle, only if BashCut gets distributed.

## Plugin platform

Follows [03-architecture.md](03-architecture.md) §5 "Plugin platform roadmap".

- **Done:** `CapabilityService` shared by panels, CLI/MCP and export; `CapabilityAdapter` and `PluginTransport`
  (one-shot process transport); `captions.generate`, `beats.detect`, `voice.speak`, `plugins.list` and
  `jobs.status`/`jobs.cancel`.
- **Done:** bundled native `audio.loudness` and `audio.beats` providers (`bashcut.audio-analysis`); `vision.faces`
  and `vision.text` on Apple Vision (`bashcut.vision`, P2-H6/H7).
- **Then:** an API version window, provider availability states, enable/disable and Install/Enable prompts.
- **Then:** an optional long-lived `session` transport with progress and cancel, needed by Whisper and VieNeu
  wrappers.
- **Then:** hash-pinned plugin trust and manifest-declared provider options.
- **Done (plugin API 8, #390):** plugin panels in the left rail, dock tabs and sheets with declarative views; plugins
  calling app commands from views and actions; `requires`, `uses` + `plugins.invoke`; host feature flags.
- **Later:** webview views, free drawing, video in views, timeline and viewer overlays, plugin inspector sections,
  drag and drop from views, updates pushed outside a request; a `views` template in `bashcut-plugins/scripts/new-plugin.py`.

## Reserved: Apply to DaVinci Resolve (no date)

Built only when there is a real need, for example finishing a video in Resolve or handing it to someone who uses
Resolve. The design is in [03-architecture.md](03-architecture.md) §7, and the data rules in
[02-project-format.md](02-project-format.md) §5 keep it possible without a migration.

1. `ResolveExporter.plan`: classify every property as native in Resolve or rendered by BashCut, and show the
   plan.
2. Render the artifacts: an alpha overlay, pre-rendered transition and speed clips, and four audio stems, written
   to `resolve-media/b<HHMMSS>/`.
3. Generate a bridge task and run it through `bridge_run.py --project`. Map exit codes 2, 3 and 4 to GUI
   instructions.
4. Verify with numbers (clips per track, offline count, V1 gaps, duration), then store the Resolve IDs in
   `interop.resolve`.

## Risks

| Risk | Mitigation |
|---|---|
| Compositor or timeline performance on 4K or HEVC DJI footage | M0 spike (passed), automatic proxies (M-5), `bashcut-bench` and `verify.sh perf` |
| Preview drifting from export | one composition for both; golden-frame tests |
| NLE scope creep | stick to P0/P1/P2; leave to the agent anything a skill already does |
| Claude or Codex CLI flags change | all flags live in the `AgentProvider` conformances; the interactive TUI depends on few flags; the `bashcut` CLI works even if MCP breaks |
| Agent and user editing at the same time | `rev` + `baseRev`, one undo step per request, wait for in-progress drags |
| WhisperKit is weaker than mlx-whisper on noisy Vietnamese audio | compare providers in M3; keep either engine replaceable behind `captions.transcribe` |
| A plugin dependency or ML venv is missing or broken | health probes mark only that provider degraded; Plugins shows its reviewed install plan; editing still works |
| A plugin crashes, hangs or emits unsafe paths | one bounded child per request, timeout and cancellation, filtered environment, output-folder confinement |
| Vietnamese fonts and emoji in captions | Core Text plus diacritics in golden tests |
| A future Resolve export is blocked by a data decision | Resolve-ready rules ([02-project-format.md](02-project-format.md) §5) enforced in `.claude/rules/project-model.md` and reviewed on every schema change |

## Decisions (2026-10-02)

| Topic | Decision |
|---|---|
| Render engine | AVFoundation + Core Image/Metal for preview and export; ffmpeg only as an optional helper |
| macOS minimum | 14.0 |
| Codex | On par with Claude from M2 (workspace gets `AGENTS.md` + `.agents/skills`) |
| Repo | Separate repo in `bash-cut/` |
| UI language | English by default, Vietnamese localization |
| Optional engines | `bashcut.plugin/1` child processes with capability/provider resolution; no provider-specific SDK in the base app |
| DaVinci Resolve | Not built now; data model stays Resolve-ready; "Apply to Resolve" reserved |

## Open questions

The defaults below apply unless Nolan says otherwise.

1. **Keyframes and speed ramps.** Default: M6. The reference videos mostly use hard cuts and reframes.
2. **Default transcription provider.** Default: prefer an installed local WhisperKit provider, pending the M3
   accuracy check against an mlx-whisper provider.
3. **Distribution.** Decided: Developer ID signed and notarized releases on GitHub and the Homebrew tap
   `dongnguyenvie/homebrew-tap`, plus TestFlight. No Sparkle: BashCut checks the latest GitHub release once a day
   and on demand (BashCut › Check for Updates…, `app update-check`) and tells the user how to update (`brew upgrade
   --cask bashcut` or the release page). It never installs updates itself.
