# 09 — Roadmap

Each milestone must be usable on its own. Estimates assume one developer working with an agent.
The engine and the timeline are the hardest parts, so they come first and are measured early.

## M0: Skeleton and engine spike (≈ 1 week)

**Repo setup.** Create the `bash-cut/` repo with:

- `project.yml`, `Configs/`, `verify.sh`;
- `AGENTS.md`, `.claude/rules/`, SwiftLint, `CHANGELOG.md`, `docs/THIRD_PARTY.md`.

**Packages.** Add swift-collections and swift-snapshot-testing.

**Project model.** `BashCutProject` gets the model, the basic `EditOperation`s
(insert/delete/split/trim/move), `apply`/inverse, and tests.

**Engine spike.**

1. Composite 20 DJI clips at 1080×1920 with reframes and one Core Text caption layer.
2. Play them through `AVPlayer` with the custom compositor.
3. Export 30 s with `AVAssetWriter`.

**Done when:**

- playback is smooth at 29.97 fps;
- scrub latency is under 100 ms;
- export is faster than real time;
- `verify.sh build/test/lint` pass.

If the spike misses these targets, revisit the engine design (for example, mandatory proxies)
before building the UI.

## M1: Core editor (≈ 3–4 weeks)

**Projects:**

- Welcome screen.
- New Project, including the footage symlink.
- Save, autosave, undo.
- Reload when the file changes externally.

**Media library:**

- Thumbnails and hover-scrub.
- Source viewer with I/O and insert.

**Timeline:**

- Tracks: magnetic Main, Overlay, Captions, plus four audio tracks.
- Editing: split, delete, trim, move, snapping.
- Clip roles and sections.

**Viewer and Inspector:**

- Viewer.
- Inspector with transform and volume.
- Waveforms.

**System:** Doctor, Settings, and English + Vietnamese strings.

**Done when:** the `lau-bo-noi-dat` cut (48 cuts) can be rebuilt by hand with no stutter or lag.

## M2: Agent dock and automation (≈ 2 weeks)

**First, verify** the **(to verify)** items in `05-agent-integration.md` and `04-dependencies.md`.

**Dock.** SwiftTerm tabs for Claude, Codex and Shell, with `cwd` set to the workspace.

**Automation.**

- The automation socket, the `bashcut` CLI (swift-argument-parser) and `bashcut-mcp` (MCP Swift
  SDK).
- Commands: `context`, `project`, `timeline get/apply`, `media list`, `ui *`.

**UI pieces.** ⌘K popover, context chip, ◆ badges, undo toast.

**Workspace side** (done by an agent working in the workspace):

- add a "BashCut projects" section to `CLAUDE.md`;
- add `AGENTS.md` and `.agents/skills`;
- create the `nolan-bashcut` skill.

**Done when:**

- You select a clip, press ⌘K and type "trim to 4 s". Claude makes the edit, the ◆ badge
  appears, and ⌘Z reverts it.
- The same flow works with Codex.

## M3: Text, captions, export (≈ 2–3 weeks)

This milestone produces **the first vlog made entirely in the app**.

- Text with the Bold Outline and Cinematic Serif presets, inline editing, the TikTok safe area.
- Auto Captions with WhisperKit (after checking Vietnamese accuracy) and `.srt` export.
- Export: TikTok and YouTube presets, queue, post-export numbers.
- Import from `edl.json`.

**Done when:**

- a new video is cut and exported entirely in BashCut, ready to publish;
- importing `lau-bo-noi-dat` matches 48 cuts and 109.81 s.

## M4: Audio and voice (≈ 2–3 weeks)

- Music/SFX library with BPM, loudness and license badges.
- Ducking, and −14 LUFS normalization with libebur128.
- Voice tab: generate 3 takes, score them, insert into Voiceover. Clone New Voice wizard.
- Warning when the voiceover overlaps real speech.
- Beat detection, beat snapping, automatic change framing.

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
- Signing, notarization, DMG, Sparkle. Only needed if BashCut gets distributed.

## Reserved: Apply to DaVinci Resolve (no date)

Built only when there is a real need, for example finishing a video in Resolve or handing it to
someone who uses Resolve. The design is in `03-architecture.md` §7, and the data rules in
`02-project-format.md` §5 keep it possible without a migration.

Planned steps:

1. `ResolveExporter.plan`: classify every property as native in Resolve or rendered by BashCut,
   and show the plan.
2. Render the artifacts: an alpha overlay, pre-rendered transition/speed clips and four audio
   stems, written to `resolve-media/b<HHMMSS>/`.
3. Generate a bridge task and run it through `bridge_run.py --project`. Map exit codes 2/3/4 to
   GUI instructions.
4. Verify with numbers (clips per track, offline count, V1 gaps, duration), then store the Resolve
   IDs in `interop.resolve`.

## Risks

| Risk | Mitigation |
|---|---|
| Compositor/timeline performance on 4K or HEVC DJI footage | M0 spike, automatic proxies, `BashCutPerfTests` with thresholds |
| Preview drifting from export | one composition for both; golden-frame tests |
| NLE scope creep | stick to P0/P1/P2; leave to the agent anything a skill already does |
| Claude/Codex CLI flags change | all flags in `Agent/Providers/`; interactive TUI depends on few flags; the `bashcut` CLI works even if MCP breaks |
| Agent and user editing at the same time | `rev` + `baseRev`, one undo step per request, wait for in-progress drags |
| WhisperKit is weaker than mlx-whisper on noisy Vietnamese audio | compare in M3. If needed, `TranscribeTool` keeps a second implementation that calls the workspace's mlx-whisper |
| ML venvs missing or broken | Doctor, features disable themselves with install hints; editing still works |
| Vietnamese fonts and emoji in captions | Core Text plus diacritics in golden tests |
| A future Resolve export is blocked by a data decision | Resolve-ready rules (`02-project-format.md` §5) are enforced in `.claude/rules/project-model.md` and reviewed on every schema change |

## Decisions (2026-10-02)

| Topic | Decision |
|---|---|
| Render engine | AVFoundation + Core Image/Metal for preview and export; ffmpeg only as an optional helper |
| macOS minimum | 14.0 |
| Codex | On par with Claude from M2 (workspace gets `AGENTS.md` + `.agents/skills`) |
| Repo | Separate repo in `bash-cut/` |
| UI language | English by default, Vietnamese localization |
| DaVinci Resolve | Not built now; data model stays Resolve-ready; "Apply to Resolve" reserved |

## Open questions

The defaults below apply unless Nolan says otherwise.

1. **Keyframes and speed ramps.** Default: M6. The reference videos mostly use hard cuts and
   reframes.
2. **WhisperKit as the in-app default.** Default: yes, pending the M3 accuracy check against
   mlx-whisper.
3. **Distribution.** Default: Nolan's machine only, so no signing, notarization or Sparkle until
   that changes.
