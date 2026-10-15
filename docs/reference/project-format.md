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
| `.bashcut/cache/proxies/<media id>.mov` | Preview proxies (see [Media paths](#media-paths)) |
| `.bashcut/plugins/` | Project-scoped plugins, which override user and bundled ones |
| `.bashcut/.gitignore` | Lists the folders BashCut can make again (see [Storage on disk](#storage-on-disk)) |
| `.bashcut/export-history.json` | The export ledger: each finished export with its ID, revision, fingerprint and post links |
| `.bashcut/exports/<id>.json` | The sections and caption words of an export, for `outcomes map` |
| `.bashcut/outcomes/<id>.json` | An export's imported retention curve and totals |
| `.bashcut/knowledge/verdicts.jsonl` | The user's verdicts on agents' changes (`knowledge verdicts`) |

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
  ignored. The journal is a single checkpoint, not an append-only log. Each undo and redo step is stored as a
  delta against the next newer state: changed project fields, and for each changed layer its fields plus runs of
  unchanged items (`[start, count]`) and the changed items in full. Journals written with full `restore`
  snapshots still load.

## Storage on disk

What BashCut keeps where, by how safe it is to delete. Settings › Storage and `bashcut storage get` show the sizes
of the clearable parts, with each plugin's folder, data and cache added up to one total, largest first, and the
shared plugin runtimes and downloads as their own rows.

| Kind | Where | Contents |
|---|---|---|
| Project data | `<project>/project.bashcut.json`, `.bashcut/history.jsonl`, `.bashcut/autosave/`, `.bashcut/library/`, `.bashcut/plugins/`, `.bashcut/skills/`, `.bashcut/agent-memory.md`, `.bashcut/knowledge/`, `.bashcut/chat/`, `.bashcut/export-history.json`, `.bashcut/exports/`, `.bashcut/outcomes/` | The edit and what belongs to this project; keep and sync it |
| Project cache | `.bashcut/cache/`: `proxies/`, `waveforms/`, `ramp-audio/`, `stills/`, `loudness/`, `agent-context/`, `analysis/`, `transcripts/`, `review-packets/`, `review-measurements/` (the review's picture and loudness measurements, `<content key>-picture.json` / `-loudness.json`, keyed by the project without its revision number and the media files' size and date, so a restart keeps them and any edit misses them) | Made again on demand; listed in `.bashcut/.gitignore` and excluded from Time Machine |
| User config | `~/Library/Application Support/BashCut/`: `Plugins/`, `PluginData/<id>/`, `PluginData/_shared/` (runtimes such as Python, shared by plugins), `plugin-trust.json`, `Library/`, `Knowledge/`, `agent-workspace*/`, `audit.jsonl`, `automation.sock` | Installed plugins, their settings and environments, trust grants, the user library and knowledge for every project (memo, lessons, preferences) |
| User cache | `~/Library/Caches/BashCut/`: `PluginData/<id>/` (downloaded models), `PluginData/_shared/` (package caches shared by plugins), `Registry/` (the plugin catalog copy) | Fetched again when missing; not backed up by Time Machine |
| Logs | `~/Library/Logs/BashCut/debug.log` | Shared by the app, CLI and MCP bridge |

- **One cache folder.** Everything BashCut can make again is under `.bashcut/cache/`. Before, each cache had its own
  folder in `.bashcut/` (`proxies/`, `ramp-audio/`, `stills/`, `loudness/`, `agent-context/`); opening a project moves
  them in (a rename, so gigabytes of proxies move at once) and marks `.bashcut/cache/` as excluded from backups.
- **`.bashcut/.gitignore`** is written when a project is created or saved and has none, so a project folder in git
  leaves the project cache out. BashCut never rewrites an existing one, so edits stay.
- **The plugin registry copy moved to Caches** (#101). Before, it was `Application Support/BashCut/Registry/`; the
  first time the Plugins sheet needs the registry, an old copy is moved over and the old folder is removed.

## Timing and IDs

All times are integers. Seconds appear only in the UI, in the agent text form and in command arguments.

| Field | Unit |
|---|---|
| `format.fps`, `media[].fps` | Rational `[numerator, denominator]`, for example `[30000, 1001]` |
| `item.in` | Source frame, at the media's own fps |
| `item.at`, `item.dur` | Timeline frames, at `format.fps` |
| Trim targets, split positions, section markers, beat-grid frames | Absolute timeline frames |
| `fadeIn`, `fadeOut`, `duckAttackFrames`, `duckReleaseFrames`, `duckMinGapFrames` | Timeline frames |

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

`Project.validate()` enforces these layer rules, so UI, CLI and MCP share them:

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

**Looks** are library `look` items (built-in `original`, `vivid`, `muted-film`, `black-white`, `bright-airy`,
`moody`, or saved in the project or user library); there is no project-level look catalog and no style kit.
Projects saved before this keep their top-level `looks` and `styleKits` arrays as unknown fields; opening one copies
each of its `looks` into the project library once. Deleting a LUT removes it from clips and adjustments.

```json
{"id": "fx1", "kind": "adjustment", "role": "adjustment", "name": "Adjustment 1", "items": [
  {"id": "grade-1", "at": 0, "dur": 900, "in": 0, "styleKit": "cinematic",
   "color": {"saturation": 0.8, "contrast": 0.9}}
]}
```

## Framing

A clip's base size is its source scaled to the canvas: **fit** shows the whole picture, using the scale of its
longest side against the frame (bars on the other sides), **fill** covers the frame and crops. The item field
`fill` chooses for one clip; without it the project's `clipFill` decides. New projects write `clipFill: false`
(fit); a project without the field fills, as every project did before it existed, so older zoom values keep their
look. `transform.zoom` scales from that base size, and `pan` / `tilt` move it in output pixels.

A fitted picture leaves bars; the item's optional `backdrop` fills them instead of black: `{"kind": "blur"}` draws a
blurred copy of the same frame scaled to fill (`blur`: radius as a share of the frame's short side, default 0.05),
`{"kind": "color", "color": "#RRGGBB"}` a colour; `dim` (0–1) darkens either. The backdrop belongs to the clip:
transitions, grade and opacity apply to it too (`clip backdrop`, Inspector › Video › Backdrop).

## Motion and style as data

An item that is not part of a video cut (text, a sticker, a graphic, an overlay clip) may have `enter` and `exit`:
`{"kind", "duration", "easing"?, "motion"?}` like a transition, played on the item alone inside its own frame
(`enter`: the kind's incoming side over its first frames; `exit`: its outgoing side over its last, a kind that
leaves the outgoing picture in place running its incoming side backwards; a side that does not hide the item fades
it). Each is clamped to the item, and a cut transition at the same clip edge wins. Video and text items only; other
fields inside are kept.

- **Ease.** Keyframe `ease` and transition `easing` are one type: `linear`, `in`, `out`, `inOut` (keyframes also
  `hold`) or `"cubic-bezier(x1,y1,x2,y2)"` with x1 and x2 in 0…1.
- **Keyframes** animate `zoom`, `pan`, `tilt`, `rotation`, `opacity`, `volume` and numeric style fields as
  `group.field` paths: `color.exposure`, `color.contrast`, `color.saturation`, `color.lutStrength` on clips and
  adjustment layers; `textStyle.size`, `positionX`, `positionY`, `strokeWidth`, `lineHeight`, `tracking` on text;
  `crop.left`, `crop.right`, `crop.top`, `crop.bottom` and `crop.radius` (rounded corners) on clips and images.
- **Transitions** keep `kind`, `duration`, optional `easing` and optional `motion`
  `{"outgoing": {property: [values]}, "incoming": {…}}`. Properties: `zoom`, `panX`/`panY` (share of the frame,
  right/up), `rotation` (degrees, counterclockwise), `opacity`, `exposure` (EV), `scaleX`, `reveal` (share of
  the width shown from the left), `swing` (degrees about the left edge in perspective), `rgbSplit` (red/blue offset
  as a share of the width), `halftone` (dot spacing as a share of the width), `blur` (soft blur radius),
  `blurX`/`blurY` (motion blur along an axis; both as a share of the width), `revealFromRight`, `revealFromTop`,
  `revealFromBottom`, `revealCenter`, `iris` and `diamond` (share of the frame shown), `zoomBlur` (share of the
  width), `hue` (degrees), `saturation` and `kaleidoscope` (0–1); 2–16 values spread evenly
  over the eased tween. The built-in kinds (`dissolve`, `blink`, `flash`, `dip-black`, `double-exposure`, `whip`, `whip-right`, `whip-up`, `whip-down`,
  `wipe`, `wipe-right`, `wipe-up`, `wipe-down`, `barn-door`, `shutter`, `slide`, `slide-up`, `iris`, `diamond`, `zoom`,
  `crash-zoom`, `crash-out`, `spin`, `roll`, `roll-right`, `swing`, `arc`, `arc-right`, `infinite-zoom`,
  `infinite-out`, `screen-in`, `screen-out`, `blur`, `seamless-zoom`, `glitch`, `halftone`, `flicker`,
  `color-shift`, `kaleidoscope`) are rows of the same table; any other kind
  needs `motion`.
- **Text style** is open: besides the declared `textStyle` fields, the renderer reads `background {color, opacity,
  padding, radius}`, `shadow {color, opacity, blur, dx, dy}` and `accentBars [{side left|right|top|bottom, color,
  opacity, thickness, gap, length, radius}]` (thickness and gap in font sizes, defaults 0.12 and 0.2; length a share
  of the side; bars sit beside the text block or its plate). A background or accent bars replace the preset's own
  plates and bars. `emphasis {line, fill, scale, plate {color, opacity, padding, radius}}` draws one line `scale`
  times larger in its own colour (`line` from the top, negative from the bottom; without it the last of two lines or
  the middle one), optionally on its own plate; it is fitted to the frame on its own, the other lines without it.
  `hook-title` emphasises by default once it has two lines; `false` turns it off. `lineFills [colors]` colours the
  lines in turn. `lines [{font, scale, fill, stroke} | null]` gives each line, in reading order, its own font
  (PostScript name, so family and weight), size (`scale` × the block's, 0.2–5, after the emphasis scale) and colours:
  two fonts in one title. A line with its own font or scale is fitted on its own; `null` and lines past the list keep
  the block's look (`text line-style`). A block taller than the frame allows is moved back inside it, as a wide line
  shrinks to fit.
- **Text templates** are built-in library text presets named by their look, not their use (`stacked-keyword`,
  `headline-subline`, `boxed-keyword`, `two-tone-pop`): a renderer preset plus a full `textStyle`. The same template
  serves as a hook, a call to action or a label; the agent picks it for the video.
- **Brand kit** (#453): the project's optional `brand` holds the applied kit — `palette` {accent, background, text,
  secondary} `#RRGGBB`, `fonts` {heading, body}, `logo` and `mascot` {pose: id} sticker library references, `voice`
  {provider, voice}, `disclosure`, plus `library` and `name` of the item it came from. A text item's optional
  `brandRoles` {textStyle path: role} ties `fill`, `stroke`, `highlight`, `background.color`, `shadow.color` or
  `accentBars.color` to a colour role and `font` to a font role; applying a kit rewrites those values, so the stored
  `textStyle` always holds plain colours and fonts that every reader understands.

## Schema and versioning

[project.schema.json](project.schema.json) is a JSON Schema (draft 2020-12) of the whole file. It is generated,
never edited by hand: `ProjectSchema` builds it from the same declarations validation uses (`TrackKind`,
`ItemProperty`, `ColorGrade`, `TextPreset`, `ItemMotion`, `TransitionMotion`). Agents read it with `schema get`. Fields
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
| `duckMinGapFrames` | Hold: a gap between speech shorter than this keeps the music down; unset is 2.5 s, 0 rises in every gap | 0 … 10 000 frames |

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
  `.bashcut/cache/proxies/<media id>.mov` (or `.mp4`) when it exists; export always reads the original. Proxies keep
  the original frame timing, so no item changes.
- **LUTs.** The project catalog `luts` lists `.cube` files under `luts/` with an ID, name and size; an item's
  `color.lut` must name a catalog entry.

## Edit operations and undo

Every change is an `EditOperation` applied by `Project.applying(_:baseRevision:)`, which validates the project
before and after the edit and returns the new project with its inverse.

- **One serialized form.** Operations are JSON objects keyed by `op`, for example
  `{"op": "split", "item": "c1", "atFrame": 30}`. Agents and the history journal both use this codec
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
