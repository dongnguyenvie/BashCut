# Project format reference

How `project.bashcut.json`, its cache folder and edits behave in the current build. The design rationale and the
full field sketch are in [02 — Project format](../specs/02-project-format.md); this page records what the code in
`Packages/BashCutCore/Sources/BashCutProject` actually enforces.

## Files and history

| Path | Contents |
|---|---|
| `project.bashcut.json` | The project: indented JSON, sorted keys, schema `bashcut.project/1`; the full field list is [project.schema.json](project.schema.json) |
| `.bashcut/history.jsonl` | Undo/redo checkpoint written on every save |
| `.bashcut/autosave/latest.json` | Unsaved history plus the disk bytes it was based on |
| `.bashcut/proxies/<media id>.mov` | Preview proxies (see [Media paths](#media-paths)) |
| `.bashcut/plugins/` | Project-scoped plugins, which override user and bundled ones |

A project file with another name (for example a test fixture) gets its own cache folder, `.bashcut-<file name>/`.

- **Validated on load and on save.** `Project.decode` runs any `ProjectMigration` steps (none yet), repairs layers (see
  [Tracks and layers](#tracks-and-layers)) and then validates; `Project.data()` validates before encoding. An
  invalid project is never written.
- **Unknown fields round-trip** at every nesting level, so agents and future versions can add data.
- **Saves are atomic and conflict-checked.** The journal and then the project are written with atomic renames. A
  save is refused when the file on disk no longer matches the bytes BashCut last read or wrote.
- **Autosave** runs every 30 seconds and when the app loses focus. On open, the autosave is offered only if its
  baseline equals the current disk bytes, so a stale recovery cannot overwrite an external edit.
- **History** is restored on open only when the journal's project equals the saved project; otherwise it is
  ignored. The journal is a single checkpoint today, not a compact append-only log.

## Timing and IDs

All times are integers. Seconds appear only in the UI, in the agent text form and in command arguments.

| Field | Unit |
|---|---|
| `format.fps`, `media[].fps` | Rational `[numerator, denominator]`, for example `[30000, 1001]` |
| `item.in` | Source frame, at the media's own fps |
| `item.at`, `item.dur` | Timeline frames, at `format.fps` |
| Trim targets, split positions, section markers, beat-grid frames | Absolute timeline frames |
| `fadeIn`, `fadeOut`, `duckAttackFrames`, `duckReleaseFrames` | Timeline frames |

- `rev` increases by one on every applied edit. A request that carries a `baseRev` different from the current
  `rev` fails with `staleRevision`.
- Item IDs are stable across trims and moves. A split keeps the ID on the left half and gives the right half the
  requested new ID; a linked partner's right half gets `<newID>-linked`.
- Section markers have stable IDs; at most one section starts on a given frame.

## Tracks and layers

`tracks` is an ordered list of layers. Kinds are `video`, `adjustment`, `text` and `audio`; `role` is a repeatable
semantic hint (`main`, `overlay`, `adjustment`, `captions`, `dialogue`, `voiceover`, `music`, `sfx`). Features look tracks up by role,
never by fixed IDs such as `v1`. New projects start with seven tracks: Main, Overlay, Captions, Dialogue,
Voiceover, Music and SFX.

`Project.validate()` enforces these layer rules, so UI, CLI, MCP and model APIs share them:

| Rule | Detail |
|---|---|
| Two bands | Visual tracks (`video`, `adjustment`, `text`) come first, back to front; audio tracks follow and are mixed. A track cannot move across the boundary |
| One main track | Exactly one `main` video track, which cannot be deleted |
| No overlaps | Items never overlap on one track; gaps are allowed, including on the main track |
| Media fits the track | Audio media never sits on a visual track; audio tracks take audio media or video media with sound |

**Placement spills, raw operations fail.** Placing media (`media place`, timeline drags, imports, the library)
moves an occupied range onto the next free track with the same kind and role, or onto a new track right next to
the target. The main track spills onto `overlay` tracks, and overlapping SRT cues stack onto extra caption
tracks. A raw `insert` or `move` that would overlap is rejected.

**Older projects are repaired on open**, without a schema bump: tracks are reordered into the two bands, a
missing main track is added and extra ones become `overlay`, and overlapping items move onto new tracks next to
their original track. Valid projects are unchanged.

A magnetic track (`magnetic: true`, the main track by default) appends inserts after its last item, and dragging
within it reorders and compacts the track.

## Adjustment layers

An `adjustment` track works like an adjustment layer in CapCut or Premiere. Its items have `id`, `at` and `dur`
but no `media` or `text`, and carry a `color` object with the same keys as a clip (`exposure`, `contrast`,
`saturation`, `lut`, `lutStrength`). While an item is on screen, its grade applies to everything composited below
it, in preview and export alike; layers above it, such as captions, are not graded. Hiding the track bypasses it.

New adjustment tracks (ID prefix `fx`) go above the video tracks and below text. `adjustment add` places an item
on the first adjustment track, adding one when needed, and spills overlaps onto another adjustment track.

A style kit (`style apply`) is not stored as a setting. Applying one is a single undoable edit: it deletes
adjustment items an earlier kit added (marked `styleKit: "<kit id>"`), adds a full-length adjustment item with
the kit's look, and sets the kit's `captionPreset` as the `textPreset` of every caption on a `captions` text track
that has no preset or another kit's caption preset (titles, place cards and other presets keep theirs).

**Looks and style kits** come built in (looks `original`, `vivid`, `muted-film`, `black-white`; kits
`food-review`, `cinematic`) or from the project. Custom ones are stored in the top-level `looks`
(`{id, title, color}`) and `styleKits` (`{id, title, look, captionPreset}`) arrays, managed with `looks save`,
`looks delete`, `style save` and `style delete`. IDs are lowercase letters, digits and hyphens, unique across
built-in and custom entries. A kit's look must exist, and a look cannot be deleted while a custom kit uses it.
Deleting a LUT removes it from clips, adjustments and custom looks alike.

```json
{"id": "fx1", "kind": "adjustment", "role": "adjustment", "name": "Adjustment 1", "items": [
  {"id": "grade-1", "at": 0, "dur": 900, "in": 0, "styleKit": "cinematic",
   "color": {"saturation": 0.8, "contrast": 0.9}}
]}
```

## Schema and versioning

[project.schema.json](project.schema.json) is a JSON Schema (draft 2020-12) of the whole file. It is generated,
never edited by hand: `ProjectSchema` builds it from the same declarations validation uses (`TrackKind`,
`ItemProperty`, `ColorGrade`, `TextPreset`, the look and kit catalogs). Agents read it with `schema get`. Fields
it does not declare are still allowed, because unknown fields round-trip; rules that span several fields (layer
bands, overlaps, links, transitions) are enforced by `Project.validate()` and described in the schema text.

To change the format:

1. Declare the field in `ItemProperty.all` (item properties) or `ProjectSchema` (anything else). Validation
   picks up `ItemProperty` entries automatically.
2. Run `scripts/update-schema.sh`; `ProjectSchemaTests` fails while the published file is out of date.
3. For a breaking change, bump `Project.schema` and append a `ProjectMigration.Step` from the previous version,
   with a test. Additive optional fields need neither.

## Speed ramps and reversed clips

- `speedCurve` (optional) is a speed ramp: 2–16 points `{"t": …, "speed": …}` with `t` from 0 (clip start) to 1
  (clip end), speed linear between them, 0.1×–16×. `speed` then holds the curve's average (validation checks it), so
  `dur × speed` is still the source the clip uses. Split and trim keep each part's share of the ramp on the same
  source; lengthening holds the end speed. `setSpeed` removes a ramp; `setSpeedCurve` with no points keeps the clip
  at its average speed.
- `reversed` (optional) marks a clip pointed at a reversed copy (`reversed/<file>-reversed-<in>-<frames>.mov`, media with
  `reverseOf`): `{"media": original ID, "in": original in-point, "frames": frames used}`. `setSource` changes a
  clip's media and in-point (with its linked partner); reversing again restores the original.

## Linked audio and video

Video media with embedded sound is inserted as a reciprocal pair: the picture item stores `linkedAudio`, the
Dialogue item stores `linkedVideo`. Validation requires both links to point at each other and the pair to share
media, `at`, `dur`, `in` and `speed`.

- Move, trim, split, slip, roll and delete update both items in one atomic edit.
- Ripple shifts the edited track and its linked counterpart's track; unrelated tracks do not ripple.
- Unlinking is an explicit, undoable `setLinkedAudio` operation.

**Freeze frame.** A video item may store `freezeFrame` as an integer source frame. The engine holds that one
image for the item's timeline duration while the linked Dialogue item keeps its normal source range. Setting
`freezeFrame` to JSON `null` through `setProperties` removes it.

## Audio

### Ducking

Only a Music audio track may carry ducking fields.

| Field | Meaning | Range |
|---|---|---|
| `duckUnderSpeechDb` | Level under speech; its presence opts the track in | −60 … 0 dB |
| `duckingEnabled` | Suspends ducking without discarding the level | Boolean |
| `duckAttackFrames`, `duckReleaseFrames` | Ramp length | 0 … 10 000 frames |

Voiceover items always count as speech. Dialogue items count when they, or their linked video, carry
`tag.role: "speech"`. Clip gain, fades, ducking and mix gain become one frame-based envelope shared by preview
and export.

### Loudness

The top-level `audio` object holds the mix settings and, after a normalized export, the measurement.

| Field | Meaning | Range |
|---|---|---|
| `targetLUFS` | Normalization target | −30 … −5 |
| `normalizeEnabled` | Run two-pass normalization on export | Boolean |
| `mixGainDb` | Master gain, part of the shared envelope | −60 … 24 dB |
| `measuredLUFS`, `truePeakDbTP`, `loudnessRangeLU` | Last measurement | Bounded |
| `measurementVerified` | Whether the final file was re-measured | Boolean |
| `measuredBy` | Plugin provenance of the measurement | Object |

Because mix gain is in the shared envelope, the preview matches the normalized export once the undoable settings
edit is applied. Unknown `audio` fields still round-trip.

## Media paths

Media paths are relative to the project folder; absolute paths are rejected.

- **Linked folders.** A file inside a top-level folder link (such as `footage/`) is stored through the link as
  `footage/<file>`. Older `../…` paths into a linked folder are rewritten on open as one undoable "Relink media
  paths" edit.
- **Shared assets.** `@assets/<path>` resolves beneath the configured workspace's `assets` folder. A missing
  workspace, an unknown `@` namespace, `.`/`..` components and symlinks that escape `assets` are rejected before
  composition.
- **Proxies.** Items always reference the original file. For preview, `ProxyMediaSource` reads
  `.bashcut/proxies/<media id>.mov` (or `.mp4`) when it exists; export always reads the original. Proxies keep
  the original frame timing, so no item changes.
- **LUTs.** The project catalog `luts` lists `.cube` files under `luts/` with an ID, name and size; an item's
  `color.lut` must name a catalog entry.

## Edit operations and undo

Every change is an `EditOperation` applied by `Project.applying(_:baseRevision:)`, which validates the project
before and after the edit and returns the new project with its inverse.

- **One serialized form.** Operations are JSON objects keyed by `op`, for example
  `{"op": "split", "item": "c1", "atFrame": 30}`. Agents, model APIs and the history journal all use this codec
  (`EditOperationCodec.swift`). The internal `group` and `restore` operations are accepted only from trusted
  sources such as the journal.
- **Batches are atomic.** A `group` validates as a whole and increments `rev` once.
- **Item properties go through `setProperties`.** It cannot change `id`, `media`, `at`, `dur`, `in` or the link
  fields; timing changes use timeline operations.
- **Inverses are snapshots.** Each inverse is a `restore` of the exact pre-edit project, unknown fields included.
  Applying an inverse also increments `rev`. Snapshots cost more memory than compact inverse operations.
- **Undo depth** is capped at 200 steps. Continuous input on one field (slider drags, typing) by the same author
  within a second merges into one step.
- **Transitions** that no longer sit on an adjacent cut after an edit are removed as part of that edit.
