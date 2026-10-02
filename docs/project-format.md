# Project format

Canonical schema v1: [specification](specs/02-project-format.md). JSON uses sorted keys and preserves unknown fields at every nesting level. Load/save validates the document before publishing it.

The project model implements Project, Track, Media, Item, rational FPS, dynamic layers, beat grids, stable section markers and validated edit operations. Main-track overlaps are rejected; gaps are allowed. Time is integer frames. Trim targets, section boundaries and split positions are absolute timeline frames. Video media with embedded sound is inserted as reciprocal picture/Dialogue items. Move, trim, split, slip, roll and delete update both linked items atomically; unlinking is an explicit undoable operation. Ripple shifts the edited track and its linked counterpart track.

A video item may store `freezeFrame` as an integer source frame. The engine holds that single source image for the item's timeline duration while any linked Dialogue item continues with its normal source range. Setting the property to JSON `null` through `setProperties` removes the freeze.

A Music track opts into automatic ducking with `duckUnderSpeechDb`; `duckingEnabled` can suspend it without discarding the configured level. Optional `duckAttackFrames` and `duckReleaseFrames` shape the ramp. Voiceover items always define speech regions, while Dialogue items do so when they or their linked video carry `tag.role: "speech"`. Clip gain, fades and ducking become one frame-based envelope shared by preview and export.

The top-level `audio` object stores `targetLUFS`, `normalizeEnabled` and optional `mixGainDb`. After a normalized export it can also store `measuredLUFS`, `truePeakDbTP`, `loudnessRangeLU`, `measurementVerified` and `measuredBy` plugin provenance. Mix gain is part of the shared frame-based envelope, so the preview matches the normalized export after the undoable settings edit is applied. Target, gain and measurements are bounded during validation; unknown audio fields still round-trip.

Shared media paths use `@assets/...` and resolve beneath the configured workspace's `assets` directory. Missing workspace configuration, unknown `@` namespaces, traversal and symlinks escaping that directory are rejected before composition.

Operation batches validate atomically and increment rev once. Inverse snapshots preserve exact pre-edit data, including unrecognized fields; applying an inverse still increments rev. Snapshot inverses consume more memory than compact inverse operations. Undo/redo checkpoints persist in .bashcut/history.jsonl on save; autosave includes the unsaved history. The current journal is a single JSONL checkpoint, not yet a compact append-only log. A journal that does not match the saved project is ignored. The autosave is offered only if its baseline matches the current disk bytes, so stale recovery cannot replace an external edit.

The synthesized Codable EditOperation representation is internal, not the public M2 wire format. The CLI format in the spec will get its own adapter.
