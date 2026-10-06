import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

@Suite("Transition presets and easing (#77)")
struct TransitionPresetTests {
    /// A one-second sound effect at the project rate, as the app makes it from a library audio file.
    private static func whoosh(_ id: String = "whoosh", library: String? = "user:whoosh") -> Media {
        var fields: [String: JSONValue] = [
            "id": .string(id), "path": .string("sfx/user-whoosh-v1.wav"), "kind": .string("audio"),
            "fps": FrameRate(30, 1).json, "frames": .integer(30), "hasAudio": .bool(true),
        ]
        if let library { fields[TransitionPreset.soundLibraryField] = .string(library) }
        return Media(fields: fields)
    }

    /// The whole plan as the app commits it: one operation, or one group.
    private static func operation(_ planner: LayerPlanner) -> EditOperation {
        planner.operations.count == 1 ? planner.operations[0] : .group(label: "Preset", author: .user, ops: planner.operations)
    }

    @Test("A preset checks its kind, duration, easing and sound")
    func validation() throws {
        let preset = try TransitionPreset(params: [
            "kind": .string("dissolve"), "duration": .integer(12), "easing": .string("inOut"), "sfx": .string("user:whoosh"),
        ])
        #expect(preset == TransitionPreset(kind: "dissolve", duration: 12, easing: "inOut", sfx: "user:whoosh"))
        #expect(try TransitionPreset(params: preset.params) == preset)
        #expect(TransitionPreset(kind: "whip", easing: "linear").params == ["kind": .string("whip")])
        let bad: [([String: JSONValue], String)] = [
            ([:], "params.kind"),
            (["kind": .string("dissolve"), "easing": .string("bounce")], "params.easing"),
            (["kind": .string("dissolve"), "easing": .integer(1)], "params.easing"),
            (["kind": .string("dissolve"), "duration": .integer(0)], "params.duration"),
            (["kind": .string("dissolve"), "duration": .number(1.5)], "params.duration"),
            (["kind": .string("dissolve"), "sfx": .string("Bad ID")], "params.sfx"),
        ]
        for (params, message) in bad {
            let item = LibraryItem(id: "p", kind: .transitionPreset, name: "P", params: params)
            #expect(throws: ProjectError.self) { try item.validate() }
            do { try item.validate() } catch { #expect(error.localizedDescription.contains(message)) }
        }
        for item in LibraryBuiltIns.transitions { try item.validate() }
    }

    @Test("Transitions store an easing that the tween honors; linear stays the default")
    func easing() throws {
        let project = try ProjectFixtures.twoClips("a", "b")
        let eased = try project.applying(
            .upsertTransition(id: "t", kind: "dissolve", from: "a", to: "b", duration: 12, easing: "in")).project
        #expect(eased.transitions.first?.easing == "in")
        #expect(eased.transitions.first?.fields["easing"] == .string("in"))
        let linear = try eased.applying(
            .upsertTransition(id: "t", kind: "dissolve", from: "a", to: "b", duration: 12, easing: "linear")).project
        #expect(linear.transitions.first?.fields["easing"] == nil)
        #expect(throws: ProjectError.self) {
            try project.applying(.upsertTransition(id: "t", kind: "dissolve", from: "a", to: "b", duration: 12, easing: "x"))
        }
        // The codec carries easing, and an op without it decodes as before.
        let op = EditOperation.upsertTransition(id: "t", kind: "wipe", from: "a", to: "b", duration: 9, easing: "inOut")
        #expect(try EditOperation(json: op.json) == op)
        #expect(try EditOperation(json: EditOperation.upsertTransition(
            id: "t", kind: "wipe", from: "a", to: "b", duration: 9).json).json.object["easing"] == nil)
        // A stored easing BashCut does not know fails validation instead of rendering wrong.
        var invalid = eased
        invalid["transitions"] = .array([.object(eased.transitions[0].fields.merging(["easing": .string("x")]) { $1 })])
        #expect(throws: ProjectError.self) { try invalid.validate() }
        // Unknown fields survive replacing the transition.
        var future = eased
        future["transitions"] = .array([.object(eased.transitions[0].fields.merging(["glow": .bool(true)]) { $1 })])
        let replaced = try future.applying(
            .upsertTransition(id: "t", kind: "zoom", from: "a", to: "b", duration: 6)).project
        #expect(replaced.transitions.first?.fields["glow"] == .bool(true))
        #expect(replaced.transitions.first?.easing == "linear")
        // The curve: linear is unchanged, the others bend it but keep both ends.
        #expect(TimelineTransition.eased(0.25, easing: "linear") == 0.25)
        #expect(TimelineTransition.eased(1.5, easing: "linear") == 1)
        #expect(TimelineTransition.eased(0.25, easing: "in") < 0.25)
        #expect(TimelineTransition.eased(0.25, easing: "out") > 0.25)
        for easing in TimelineTransition.easings {
            #expect(TimelineTransition.eased(0, easing: easing) == 0)
            #expect(TimelineTransition.eased(1, easing: easing) == 1)
        }
    }

    @Test("Applying a preset sets kind, duration and easing at the cut, at most the shorter clip")
    func applyWithEasing() throws {
        let project = try ProjectFixtures.twoClips("a", "b")
        let planner = try project.transitionPresetPlan(
            TransitionPreset(kind: "whip", duration: 90, easing: "out"), at: "b")
        let applied = try project.applying(Self.operation(planner)).project
        let transition = try #require(applied.transitions.first)
        #expect(transition.kind == "whip")
        #expect(transition.duration == 60)
        #expect(transition.easing == "out")
        #expect(transition.fromItemID == "a" && transition.toItemID == "b")
        // Without a duration the preset keeps the cut's current length.
        let again = try applied.transitionPresetPlan(TransitionPreset(kind: "dissolve"), at: "a")
        let kept = try applied.applying(Self.operation(again)).project
        #expect(kept.transitions.count == 1)
        #expect(kept.transitions.first?.duration == 60)
        #expect(kept.transitions.first?.easing == "linear")
        #expect(throws: ProjectError.self) { try project.transitionPresetPlan(TransitionPreset(kind: "page-curl"), at: "a") }
    }

    @Test("A preset with a sound is one undo step, and applying it again replaces the sound")
    func applyWithSound() throws {
        let project = try ProjectFixtures.twoClips("a", "b")
        let preset = TransitionPreset(kind: "dissolve", duration: 10, easing: "inOut", sfx: "user:whoosh")
        let planner = try project.transitionPresetPlan(preset, at: "a", sound: Self.whoosh())
        var history = ProjectHistory(project: project)
        try history.apply(Self.operation(planner), label: "Soft whoosh")
        #expect(history.undoEntries.count == 1)
        let applied = history.project
        #expect(applied.transitions.first?.easing == "inOut")
        let sound = try #require(applied.transitionSound(for: "transition-a-b"))
        #expect(sound.item.at == 60)
        #expect(sound.item.duration == 30)
        #expect(sound.media.id == "whoosh")
        #expect(applied.tracks.first { $0.items.contains { $0.id == sound.item.id } }?.role == TrackRole.sfx)
        try history.undo()
        var undone = history.project
        undone["rev"] = project["rev"]  // revisions only move forward
        #expect(undone == project)
        #expect(!history.canUndo)

        // Again at the same cut: still one sound, and the media is not added twice.
        let second = try applied.transitionPresetPlan(preset, at: "b", sound: Self.whoosh())
        let replaced = try applied.applying(Self.operation(second)).project
        let items = replaced.tracks.flatMap(\.items).filter { $0[TransitionPreset.soundField] != nil }
        #expect(items.count == 1)
        #expect(replaced.media.filter { $0.id == "whoosh" }.count == 1)
    }

    @Test("A project without an SFX layer gets one for the sound; picture is refused as a sound")
    func soundLayer() throws {
        var project = try ProjectFixtures.twoClips("a", "b")
        project = try project.applying(.deleteTrack(track: try project.requireTrack(role: TrackRole.sfx).id)).project
        let planner = try project.transitionPresetPlan(TransitionPreset(kind: "zoom"), at: "a", sound: Self.whoosh())
        let applied = try project.applying(Self.operation(planner)).project
        let layer = try #require(applied.track(role: TrackRole.sfx, kind: "audio"))
        #expect(layer.items.count == 1)
        #expect(throws: ProjectError.self) {
            try project.transitionPresetPlan(TransitionPreset(kind: "zoom"), at: "a", sound: ProjectFixtures.media(kind: "video"))
        }
    }

    @Test("Save selection keeps easing and the sound's library item, and round-trips through a store")
    func saveSelectionRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("transition-presets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = try ProjectFixtures.twoClips("a", "b")
        let preset = TransitionPreset(kind: "spin", duration: 14, easing: "out", sfx: "user:whoosh")
        let applied = try project.applying(
            Self.operation(try project.transitionPresetPlan(preset, at: "a", sound: Self.whoosh()))).project
        let transition = try #require(applied.transitions.first)
        let sound = applied.transitionSound(for: transition.id)?.media
        let params = try LibrarySelection.params(.transitionPreset, item: nil, transition: transition, sound: sound)
        #expect(try TransitionPreset(params: params) == preset)
        // A sound that came from no audio item is not named; the app copies its file in instead.
        let unnamed = try LibrarySelection.params(
            .transitionPreset, item: nil, transition: transition, sound: Self.whoosh(library: nil))
        #expect(unnamed["sfx"] == nil)
        #expect(unnamed["easing"] == .string("out"))

        let catalog = LibraryCatalog(
            builtIn: [], user: .user(applicationSupport: folder.appendingPathComponent("support")),
            project: .project(root: folder.appendingPathComponent("project")))
        let saved = try catalog.add(
            LibraryItem(id: "spin-whoosh", kind: .transitionPreset, name: "Spin whoosh", params: params), into: .project)
        let read = try catalog.item("project:spin-whoosh")
        #expect(read.version == saved.version)
        #expect(try TransitionPreset(params: read.params) == preset)
        // Applying what was saved gives the same transition.
        let reapplied = try project.applying(
            Self.operation(try project.transitionPresetPlan(TransitionPreset(params: read.params), at: "b"))).project
        #expect(reapplied.transitions.first?.fields == transition.fields)
    }

    @Test("Editing a preset can drop its own file for a library sound")
    func editDropsFile() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("transition-presets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("whoosh.wav")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("RIFF".utf8).write(to: source)
        let store = LibraryStore.project(root: folder.appendingPathComponent("project"))
        let catalog = LibraryCatalog(builtIn: [], user: nil, project: store)
        try catalog.add(
            LibraryItem(id: "whoosh-cut", kind: .transitionPreset, name: "Whoosh cut", params: ["kind": .string("whip")]),
            into: .project, file: source)
        let original = try catalog.item("whoosh-cut")
        #expect(original.file != nil)
        let createdBy = LibraryItem.creator(author: .user)
        #expect(try catalog.copy(original, as: "whoosh-keep", into: .project, changes: [:], createdBy: createdBy).file != nil)
        let copy = try catalog.copy(original, as: "whoosh-copy", into: .project, changes: ["file": .null], createdBy: createdBy)
        #expect(copy.file == nil)
        let edited = try store.update(
            "whoosh-cut", changes: ["params": .object(["kind": .string("whip"), "sfx": .string("user:whoosh")]), "file": .null])
        #expect(edited.file == nil)
        #expect(edited.version == 2)
        #expect(edited.history.last?.object["file"] != nil)
    }
}
