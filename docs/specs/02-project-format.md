# 02 — Project format and workspace relationship

## 1. Where projects live

A project is a folder at `nolan-video-workspace/projects/<video-name>/`. Folder names follow the
workspace convention: lowercase, no diacritics, hyphen-separated. Keeping projects there means:

- footage is still symlinked from `viddeo-sources/`, as it is today;
- an agent running in the workspace sees the project without any extra setup;
- the workspace's git ignore rules for media already apply.

```
projects/<video-name>/
├── project.bashcut.json      # timeline + settings (the app's source of truth)
├── footage/ -> ../../viddeo-sources/<shoot>   # symlink, read-only
├── media/                    # project-only files (images, downloaded clips, custom stickers)
├── voiceover/                # TTS takes: <slug>-t1.wav, -t2.wav, -t3.wav + takes.json
├── khao-sat/                 # survey: thong_so.json, transcript.json, contact sheets (format unchanged)
├── subtitles/                # exported .srt
├── render/                   # exported videos (not in git)
└── .bashcut/                 # cache/runtime data: autosave, history, waveforms, agent context
    └── plugins/              # optional project-scoped provider overrides
```

BashCut can also open a project outside the workspace. Features that depend on the workspace
(cloned voices, shared music library, skills) are then disabled, and the app shows why.

## 2. `project.bashcut.json`

The file is indented JSON with stable key order. That keeps git diffs readable and makes the
file easy for agents to read.

```jsonc
{
  "schema": "bashcut.project/2",
  "id": "8f0c…",
  "name": "Lau bo noi dat",
  "rev": 142,                                   // +1 on every change; optimistic concurrency
  "format": {"width": 1080, "height": 1920, "fps": [30000, 1001], "sampleRate": 48000},
  "style": "food-review",                       // food-review | cinematic | custom
  "contentLanguage": "vi",                      // language of the speech/captions (BCP 47); independent of the UI language
  "media": [
    {"id": "m-0449", "path": "footage/DJI_20260830194937_0449_D.MP4",
     "kind": "video", "fps": [30000, 1001], "frames": 236,
     "hasSpeech": true, "static": false}
  ],
  "tracks": [
    {"id": "v1", "kind": "video", "role": "main", "magnetic": true, "items": [
      {"id": "c-01", "media": "m-0449",
       "in": 0,                                  // source frame (media fps)
       "dur": 61,                                // timeline frames
       "at": 0,                                  // timeline frame
       "tag": {"role": "speech", "section": "hook"},
       "transform": {"zoom": 1.0, "pan": 0, "tilt": 0},
       "speed": 1.0, "color": {"lut": "quinn-matte"},
       "linkedAudio": "a1-01",
       "fx": [{"type": "zoom", "z1": 1.3, "anim": 0.35, "ease": "out"}],
       "interop": {}}                            // reserved for external IDs (Resolve, OTIO); preserved
    ]},
    {"id": "v2", "kind": "video", "role": "overlay", "items": []},
    {"id": "t1", "kind": "text", "role": "captions", "items": [
      {"id": "s-01", "at": 0, "dur": 61, "text": "Top 10 món nên ăn\nở Buôn Ma Thuột", "style": "bold-outline"}
    ]},
    {"id": "a1", "kind": "audio", "role": "dialogue", "items": []},
    {"id": "a2", "kind": "audio", "role": "voiceover", "items": []},
    {"id": "a3", "kind": "audio", "role": "music", "items": [], "duckUnderSpeechDb": -14},
    {"id": "a4", "kind": "audio", "role": "sfx", "items": []}
  ],
  "transitions": [{"from": "c-03", "to": "c-04", "type": "whip", "dur": 12, "dir": "left"}],
  "markers": [{"at": 0, "kind": "section", "label": "hook"}],
  "beatGrid": {"media": "m-music-1", "bpm": 117.5, "phase": 0.0},
  "providers": {
    "voice.synthesize": "local.vieneu.default",
    "captions.transcribe": "local.whisper.vi",
    "audio.beats": "workspace.beatgrid",
    "audio.loudness": "local.ebur128"
  },
  "textStyles": {"bold-outline": {"font": "…", "size": 0.062, "fill": "#FFFFFF", "stroke": "#000000", "strokeWidth": 0.12}},
  "audio": {"targetLUFS": -14},
  "export": {"lastPreset": "tiktok-9x16"},
  "targets": {}                                 // reserved: per-target settings (resolve, otio), see §5
}
```

### Rules

**Time is in integer frames, never float seconds.** Float seconds drift by a frame at 29.97 fps.

- `in` is a source frame, counted at the media's own `fps`.
- `dur` and `at` are timeline frames, counted at `format.fps`.
- Seconds appear only in the UI, in the agent text form, and in command arguments.

**Media paths are relative** to the project folder. A file inside a top-level folder link
(`footage/`) is stored through the link (`footage/<file>`), never as a path into its target.
Shared assets are written as `@assets/nhac/…`, which means relative to the workspace root.

**Item IDs are stable.** An item keeps its ID when it is trimmed or moved. A split keeps the ID
on the left half and gives the right half a new ID.

**Unknown fields are preserved** on save. An agent or a future version can add fields without
losing them.

**Provider preferences are ordinary project data.** `providers` maps a stable capability to a
stable provider ID and changes through an undoable `EditOperation`. It is a preference rather than
a hard dependency: if that provider is unavailable, the resolver may use another healthy provider.
Vendor SDK types, model paths and credentials never enter the project schema.

**Generated results keep provenance, not a live plugin dependency.** Generated media and captions
may contain `generatedBy: {plugin, provider, version}`; loudness measurements use the equivalent
`audio.measuredBy`. The rendered WAV/SRT-derived items and measurements remain usable when the
plugin is removed or replaced. Unknown future provenance fields round-trip unchanged.

**Tracks are ordered, dynamic layers.** Their array order is the visual stacking order from back
to front. Projects may add as many video/image, text and audio tracks as needed; `role` is a
repeatable semantic hint rather than a fixed slot. Track IDs remain stable, and schema-v1 projects
are upgraded in memory when opened.

**Layer rules** (enforced by `Project.validate()`, so UI, CLI, MCP and model APIs share them):

- Visual tracks (`video`, `text`) come first in `tracks`, back to front; audio tracks follow and are
  mixed, so their order is only for display. A track cannot move across that boundary.
- There is exactly one `main` video track. It cannot be deleted.
- Items never overlap on one track; overlapping content lives on separate tracks.
- Audio media never sits on a visual track. Audio tracks take audio media, or video media with sound.
- Placement (`media place`, timeline drags, imports) spills an occupied range onto the next free track
  with the same kind and role, or onto a new track right next to the target, as CapCut does. The
  `main` track spills onto `overlay` tracks. Overlapping SRT cues stack onto extra caption tracks.
- Raw `insert`/`move` operations that would overlap are rejected rather than silently relocated.

Projects saved before these rules are repaired when opened, without a schema bump: tracks are
reordered into the two bands, a missing `main` track is added and extra ones become `overlay`, and
overlapping items move onto new tracks next to their original track. Valid projects are unchanged.

**`contentLanguage` is separate from the UI language.** The UI can be English while the footage
and captions are Vietnamese. Transcription providers receive it as a language hint; voice text
normalization and caption line-length rules also read it. New projects default to the value in
Settings (`vi` on Nolan's machine).

**Clip role values** are `speech`, `broll` and `underVO`. The importer maps the workspace's
`noi`, `broll` and `vo` to these.

**Writes are atomic:** write a temp file, then `rename`. Autosave goes to
`.bashcut/autosave/` every 30 s and whenever the app loses focus.

**Undo survives a reopen.** The operation log is kept in `.bashcut/history.jsonl`.

## 3. Changes from outside the app

An agent or a person may edit `project.bashcut.json` directly. The recommended path is still
`timeline apply` (see `05-agent-integration.md`).

When the file changes while the app is open (detected through FSEvents):

| App state | Behavior |
|---|---|
| No unsaved changes | Reload, and record an "External change (file)" undo step so it can be reverted |
| Unsaved changes | Ask: keep the app's version / load the version on disk / show differences |
| Broken file (bad JSON, missing fields) | Do not load. Report the error per field and keep the in-app version |

## 4. Importing old projects (`edl.json`)

**[Import from edl.json…]** reads `projects/<video>/timeline/edl.json`, plus variants such as
`edl-b.json`. It writes `project.bashcut.json` next to them. The old files are untouched, so the
old Resolve pipeline still works.

| `edl.json` | BashCut |
|---|---|
| `fps`, `total_frames` | `format.fps`. The frame size is read from `resolve_build_task.py`, or the app asks (9:16 / 16:9) |
| `clips[]` (or `v1[]` if present) | Main items: `in = src_in_frame`, `dur = so_frame`, `at = rec_frame`, `tag.role`, `tag.section` |
| `zoom/pan/tilt` | `transform` |
| `vpath ≠ path` (`pic`) | Main item takes its picture from `vpath`; the Dialogue item takes its sound from `path`; the two are unlinked |
| `sub` containing `\|t\|` | split into several caption items at second `t` of the clip |
| `vo[]` | Voiceover item at `t`, plus its caption on Captions |
| `fx.clip/trans/over/sfx` | `fx` on items / `transitions` / Overlay items / SFX items. Unsupported types are listed in a "not imported" report |
| `sec` changes | section markers |
| stems in `audio-mix/*.wav` | optional: import the stems as-is onto the four audio tracks, to keep the old mix exactly |
| absolute paths | rewritten as relative. If a file is gone, the old prefix is replaced with the current workspace root |

**Acceptance:** total duration and cut count must match. For example, `lau-bo-noi-dat` has
48 cuts, 109.81 s and 5 voiceovers. The app shows a comparison table after the import.

## 5. Designed for "Apply to Resolve" later

Resolve is **not** part of v1. The data model still follows the rules below, so that a later
`ResolveExporter` can rebuild the timeline in DaVinci Resolve through the workspace's existing
bridge (`bridge_run.py` + `resolve_bridge`) without a migration.

| Rule | Why it matters for Resolve |
|---|---|
| Items always reference the **original media file**, never a proxy or a render | `mediapool.ImportMedia` and `AppendToTimeline` need the real file |
| `in` is in **source frames**; `dur` and `at` are in **timeline frames**; fps is stored as a rational number on both the project and each media item | Maps 1:1 onto `AppendToTimeline({startFrame, endFrame, recordFrame, trackIndex})`. A mismatched project fps can be detected before the first timeline is created; this is a workspace lesson, since `SetSetting("timelineFrameRate")` silently fails once a timeline exists |
| Track IDs and order are stable; roles are repeatable semantic hints | The exporter maps ordered tracks to Resolve indices while retaining their roles. The data never stores Resolve indices |
| Effects, captions, transitions, speed and volume are **parameters, never baked** | The exporter decides per property: *native* in Resolve Free (cut, zoom/pan/tilt, opacity, LUT via `SetLUT`, markers, clip color) or *rendered by BashCut* (captions and animated overlays → one ProRes 4444 alpha overlay; transitions and speed changes → pre-rendered clips; volume and ducking → four premixed stems). These are the same artifacts `build.sh` produces today |
| Every item has stable `id` + reserved `interop` object | After applying, the exporter stores `{"interop": {"resolve": {"timelineItemId": …}}}`, which makes later re-sync or diff possible |
| Reserved `targets.resolve` on the project | Holds `{"project": "lau-bo-noi-dat", "timeline": "Lau Bo Noi Dat v1", "trackMap": …}` |
| Rendered artifacts go into a **new folder per apply** (`resolve-media/b<HHMMSS>/`) | Resolve caches media by path; overwriting a file breaks decoding. This is a workspace lesson |

OTIO export (`.otio` is JSON) follows the same rules and needs no extra data.

## 6. Suggested workspace changes

| Change | Reason |
|---|---|
| `CLAUDE.md`: add a "BashCut projects" section. Projects with `project.bashcut.json` are edited through `bashcut`/MCP and exported by BashCut. The "render only through Resolve" rule applies only to legacy pipeline projects (`edl.py` + `build.sh`) | So agents don't apply the wrong rule |
| `.gitignore`: add `projects/*/.bashcut/` and `projects/*/media/*.mp4` | Cache and media |
| `AGENTS.md` (symlink to `CLAUDE.md` or shared content), and `scripts/link-skills.sh` also links into `.agents/skills/` | Lets Codex use the `nolan-*` skills like Claude |
| Wrap `doc.py`, `clone_voice.py`, `beatgrid.py` or other optional engines in `bashcut.plugin/1` entrypoints | The app calls one versioned JSON process protocol instead of coupling feature code to workspace scripts |
| New skill `nolan-bashcut`: how to read and edit a BashCut project, the timeline text form, the `bashcut` commands | Agents learn the app without long prompts |
