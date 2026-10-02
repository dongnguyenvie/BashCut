# 02 — Project format and workspace relationship

Where a BashCut project lives, what `project.bashcut.json` contains and why, how outside edits and legacy
`edl.json` projects are handled, and which data rules keep a later "Apply to Resolve" possible. The behavior of
the current build, field by field, is in the [project format reference](../reference/project-format.md).

## 1. Where projects live

A project is a folder at `nolan-video-workspace/projects/<video-name>/`. Folder names follow the workspace
convention: lowercase, no diacritics, hyphen-separated. Keeping projects there means:

- footage is still symlinked from `viddeo-sources/`, as it is today;
- an agent running in the workspace sees the project without extra setup;
- the workspace's git ignore rules for media already apply.

```text
projects/<video-name>/
├── project.bashcut.json                     # timeline + settings (the app's source of truth)
├── footage/ -> ../../viddeo-sources/<shoot> # symlink, read-only
├── luts/                                    # imported .cube files listed in the project's LUT catalog
├── media/                                   # project-only files (images, downloaded clips, stickers)
├── voiceover/                               # generated/ (TTS takes), recordings/ (microphone)
├── khao-sat/                                # survey: thong_so.json, transcript.json, contact sheets (unchanged)
├── subtitles/                               # exported .srt; generated/ holds transcription output
├── render/                                  # exported videos (not in git)
└── .bashcut/                                # cache and runtime data
    ├── history.jsonl                        # undo/redo checkpoint
    ├── autosave/                            # crash recovery
    ├── proxies/                             # preview proxies, <media id>.mov
    └── plugins/                             # optional project-scoped plugins
```

BashCut can also open a project outside the workspace. Features that depend on the workspace (shared `@assets`
media, cloned voices, skills) are then unavailable, and the app says why.

## 2. `project.bashcut.json`

The file is indented JSON with sorted keys, which keeps git diffs readable and the file easy for agents to read.
The example below shows the implemented shape plus the reserved fields; `//` comments are for this document
only.

```jsonc
{
  "schema": "bashcut.project/2",
  "id": "8f0c…",
  "name": "Lau bo noi dat",
  "rev": 142,                       // +1 on every applied edit; optimistic concurrency
  "format": {"width": 1080, "height": 1920, "fps": [30000, 1001], "sampleRate": 48000},
  "style": "food-review",           // food-review | cinematic | custom
  "contentLanguage": "vi",          // language of speech and captions (BCP 47); independent of the UI language
  "media": [
    {"id": "m-0449", "path": "footage/DJI_20260830194937_0449_D.MP4",
     "kind": "video", "fps": [30000, 1001], "frames": 236,
     "width": 1080, "height": 1920, "hasAudio": true}
  ],
  "tracks": [                       // back to front: visual tracks first, then audio tracks
    {"id": "v1", "kind": "video", "role": "main", "name": "Main", "magnetic": true, "items": [
      {"id": "c-01", "media": "m-0449",
       "in": 0,                     // source frame (media fps)
       "dur": 61,                   // timeline frames
       "at": 0,                     // timeline frame
       "tag": {"role": "speech", "section": "hook"},
       "transform": {"zoom": 1.0, "pan": 0, "tilt": 0},
       "speed": 1.0, "color": {"lut": "lut-quinn-matte", "lutStrength": 1.0},
       "linkedAudio": "a1-01",
       "interop": {}}               // reserved for external IDs (Resolve, OTIO); preserved
    ]},
    {"id": "v2", "kind": "video", "role": "overlay", "name": "Overlay", "items": []},
    {"id": "t1", "kind": "text", "role": "captions", "name": "Captions", "items": [
      {"id": "s-01", "at": 0, "dur": 61, "text": "Top 10 món nên ăn\nở Buôn Ma Thuột",
       "style": "bold-outline", "textStyle": {"size": 0.062, "positionY": 0.8}}
    ]},
    {"id": "a1", "kind": "audio", "role": "dialogue", "name": "Dialogue", "items": [
      {"id": "a1-01", "media": "m-0449", "in": 0, "dur": 61, "at": 0, "linkedVideo": "c-01"}
    ]},
    {"id": "a2", "kind": "audio", "role": "voiceover", "name": "Voiceover", "items": []},
    {"id": "a3", "kind": "audio", "role": "music", "name": "Music", "items": [],
     "duckUnderSpeechDb": -14, "duckingEnabled": true, "duckAttackFrames": 3, "duckReleaseFrames": 8},
    {"id": "a4", "kind": "audio", "role": "sfx", "name": "SFX", "items": []}
  ],
  "transitions": [{"id": "tr-01", "kind": "whip", "from": "c-03", "to": "c-04", "duration": 12}],
  "markers": [{"id": "sec-hook", "at": 0, "kind": "section", "label": "hook"}],
  "beatGrid": {"media": "m-music-1", "bpm": 117.5, "frames": [0, 15, 31],
               "generatedBy": {"plugin": "…", "provider": "…", "version": "…"}},
  "luts": [{"id": "lut-quinn-matte", "name": "Quinn Matte", "path": "luts/quinn-matte.cube", "size": 33}],
  "providers": {
    "voice.synthesize": "local.vieneu.default",
    "captions.transcribe": "local.whisper.vi",
    "audio.beats": "workspace.beatgrid",
    "audio.loudness": "local.ebur128"
  },
  "audio": {"targetLUFS": -14, "normalizeEnabled": true},
  "targets": {}                     // reserved: per-target settings (resolve, otio), see §5
}
```

### Rules

**Time is in integer frames, never float seconds.** Float seconds drift by a frame at 29.97 fps.

- `in` is a source frame, counted at the media's own `fps`.
- `dur` and `at` are timeline frames, counted at `format.fps`.
- Seconds appear only in the UI, in the agent text form and in command arguments.

**Media paths are relative** to the project folder. A file inside a top-level folder link (`footage/`) is stored
through the link (`footage/<file>`), never as a path into its target. Shared assets are written as
`@assets/nhac/…` and resolve under the workspace's `assets` folder.

**Item IDs are stable.** An item keeps its ID when it is trimmed or moved. A split keeps the ID on the left half
and gives the right half a new ID.

**Unknown fields are preserved** on save, so an agent or a future version can add fields without losing them.

**Provider preferences are ordinary project data.** `providers` maps a stable capability to a stable provider ID
and changes through an undoable `EditOperation`. It is a preference, not a hard dependency: if that provider is
unavailable, the resolver may use another healthy one. Vendor SDK types, model paths and credentials never enter
the project schema.

**Generated results keep provenance, not a live plugin dependency.** Generated media, captions and beat grids may
carry `generatedBy: {plugin, provider, version}`; loudness measurements use `audio.measuredBy`. The generated
items and measurements stay usable when the plugin is removed or replaced, and unknown provenance fields
round-trip unchanged.

**Tracks are ordered, dynamic layers.** Array order is the visual stacking order, back to front. A project may
have as many video, text and audio tracks as it needs; `role` is a repeatable semantic hint, not a fixed slot.
Track IDs stay stable, and schema-v1 projects are upgraded in memory when opened.

**Layer rules** are enforced by `Project.validate()`, so UI, CLI, MCP and model APIs share them:

- Visual tracks (`video`, `text`) come first, back to front; audio tracks follow and are mixed, so their order is
  only for display. A track cannot move across that boundary.
- There is exactly one `main` video track, and it cannot be deleted.
- Items never overlap on one track; overlapping content lives on separate tracks.
- Audio media never sits on a visual track. Audio tracks take audio media, or video media with sound.
- Placement (`media place`, timeline drags, imports) spills an occupied range onto the next free track with the
  same kind and role, or onto a new track right next to the target, as CapCut does. The `main` track spills onto
  `overlay` tracks, and overlapping SRT cues stack onto extra caption tracks.
- Raw `insert` and `move` operations that would overlap are rejected rather than silently relocated.

Projects saved before these rules are repaired when opened, without a schema bump: tracks are reordered into the
two bands, a missing `main` track is added and extra ones become `overlay`, and overlapping items move onto new
tracks next to their original track. Valid projects are unchanged.

**`contentLanguage` is separate from the UI language.** The UI can be English while the footage and captions are
Vietnamese. Transcription and voice providers receive it as a language hint. New projects default to `vi`, which
the New Project wizard can change.

- **Planned:** a default content language in Settings, and voice text normalization and caption line-length rules
  that read it.

**Clip role values** in `tag.role` are `speech`, `broll` and `underVO`. **Planned:** the `edl.json` importer maps
the workspace's `noi`, `broll` and `vo` to these; today it copies the role unchanged.

**Writes are atomic:** write a temp file, then rename. Autosave goes to `.bashcut/autosave/` every 30 seconds and
whenever the app loses focus.

**Undo survives a reopen.** Each save writes the undo/redo history (up to 200 steps) to `.bashcut/history.jsonl`.
**Planned:** a compact append-only operation log instead of a single checkpoint.

## 3. Changes from outside the app

An agent or a person may edit `project.bashcut.json` directly. The recommended path is still `timeline apply`
(see [05 — Agent integration](05-agent-integration.md)).

BashCut watches the project folder while it is open, and checks again when the app becomes active:

| App state | Behavior |
|---|---|
| No unsaved changes | Reload, and record an "External change (file)" undo step so it can be reverted |
| Unsaved changes | Ask: keep the app's version, load the version on disk, or show the differences |
| Broken file (bad JSON, missing fields) | Do not load. Report the error per field and keep the in-app version |

Saving never overwrites a file that changed on disk since BashCut last read or wrote it.

## 4. Importing old projects (`edl.json`)

**[Import from edl.json…]** reads `projects/<video>/timeline/edl.json`, or a variant such as `edl-b.json`, and
writes a new `project.bashcut.json`. The old files are untouched, so the old Resolve pipeline keeps working.

| `edl.json` | BashCut | Status |
|---|---|---|
| `fps`, `total_frames` | `format.fps`; `total_frames` is compared with the imported duration | Implemented |
| Frame size | Defaults to 1080×1920. **Planned:** read it from `resolve_build_task.py`, or ask (9:16 / 16:9) | Partial |
| `clips[]` (or `v1[]` if present) | Main items: `in = src_in_frame`, `dur = so_frame`, `at = rec_frame`, `tag.role`, `tag.section` | Implemented |
| `zoom`/`pan`/`tilt` | `transform` | Implemented |
| `vpath ≠ path` (`pic`) | The Main item takes its picture from `vpath`; the Dialogue item takes its sound from `path`; the two are unlinked | Implemented |
| `path` with sound | Reciprocal linked Main and Dialogue items | Implemented |
| `sub` containing `\|t\|` | Split into several caption items at second `t` of the clip | Implemented |
| `vo[]` | A Voiceover item at `t`, plus its caption on Captions | Implemented |
| `sec` changes | Section markers | Implemented |
| `fx`, `transitions`, `over`, `sfx` | Listed as "requires manual review" in the import report. **Planned:** map them to item `fx`, `transitions`, Overlay items and SFX items | Planned |
| Stems in `audio-mix/*.wav` | **Planned:** optionally import the stems as-is onto the audio tracks to keep the old mix exactly | Planned |
| Absolute paths | Rewritten as relative paths. **Planned:** when a file is gone, replace the old prefix with the current workspace root | Partial |

**Acceptance:** total duration and cut count must match. For example, `lau-bo-noi-dat` has 48 cuts, 109.81 s and
5 voiceovers. After the import the app shows a comparison report (source against imported counts, a mismatch
note and warnings).

## 5. Designed for "Apply to Resolve" later

**Reserved.** Resolve is not part of v1. The data model still follows the rules below, so that a later
`ResolveExporter` can rebuild the timeline in DaVinci Resolve through the workspace's existing bridge
(`bridge_run.py` + `resolve_bridge`) without a migration.

| Rule | Why it matters for Resolve |
|---|---|
| Items always reference the **original media file**, never a proxy or a render | `mediapool.ImportMedia` and `AppendToTimeline` need the real file |
| `in` is in **source frames**; `dur` and `at` are in **timeline frames**; fps is a rational number on both the project and each media item | Maps 1:1 onto `AppendToTimeline({startFrame, endFrame, recordFrame, trackIndex})`. A mismatched project fps is detected before the first timeline is created; a workspace lesson, since `SetSetting("timelineFrameRate")` silently fails once a timeline exists |
| Track IDs and order are stable; roles are repeatable semantic hints | The exporter maps ordered tracks to Resolve indices and keeps their roles. The data never stores Resolve indices |
| Effects, captions, transitions, speed and volume are **parameters, never baked** | The exporter decides per property: *native* in Resolve Free (cut, zoom/pan/tilt, opacity, LUT via `SetLUT`, markers, clip color) or *rendered by BashCut* (captions and animated overlays → one ProRes 4444 alpha overlay; transitions and speed changes → pre-rendered clips; volume and ducking → four premixed stems). These are the artifacts `build.sh` produces today |
| Every item has a stable `id` and a reserved `interop` object | After applying, the exporter stores `{"interop": {"resolve": {"timelineItemId": …}}}`, which makes later re-sync or diff possible |
| Reserved `targets.resolve` on the project | Holds `{"project": "lau-bo-noi-dat", "timeline": "Lau Bo Noi Dat v1", "trackMap": …}` |
| Rendered artifacts go into a **new folder per apply** (`resolve-media/b<HHMMSS>/`) | Resolve caches media by path; overwriting a file breaks decoding. A workspace lesson |

OTIO export follows the same rules and needs no extra data.

## 6. Suggested workspace changes

| Change | Reason |
|---|---|
| `CLAUDE.md`: add a "BashCut projects" section. Projects with `project.bashcut.json` are edited through `bashcut`/MCP and exported by BashCut; the "render only through Resolve" rule applies only to legacy pipeline projects (`edl.py` + `build.sh`) | So agents don't apply the wrong rule |
| `.gitignore`: add `projects/*/.bashcut/` and `projects/*/media/*.mp4` | Cache and media stay out of git |
| `AGENTS.md` (a symlink to `CLAUDE.md` or shared content); `scripts/link-skills.sh` also links into `.agents/skills/` | Lets Codex use the `nolan-*` skills like Claude |
| Wrap `doc.py`, `clone_voice.py`, `beatgrid.py` and other optional engines in `bashcut.plugin/1` entrypoints | The app calls one versioned JSON process protocol instead of coupling feature code to workspace scripts |
| A new `nolan-bashcut` skill: how to read and edit a BashCut project, the timeline text form, the `bashcut` commands | Agents learn the app without long prompts |
