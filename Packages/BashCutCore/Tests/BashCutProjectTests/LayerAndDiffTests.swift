import Foundation
import Testing

@testable import BashCutProject

struct LayerAndDiffTests {
    @Test("Dynamic layers can repeat roles, reorder and preserve schema-1 projects")
    func dynamicLayers() throws {
        var project = Project(name: "Layers")
        var layer = Track(id: "v3", kind: "video", role: "overlay")
        layer.name = "Product closeups"
        project = try project.applying(.addTrack(track: layer, atIndex: 2)).project
        #expect(project.tracks[2].id == "v3")
        #expect(project.tracks.filter { $0.role == "overlay" }.count == 2)

        project = try project.applying(.moveTrack(track: "v3", toIndex: 0)).project
        #expect(project.tracks[0].name == "Product closeups")
        project = try project.applying(
            .setTrackProperties(track: "v3", patch: ["name": .string("Hero")])
        ).project
        #expect(project.tracks[0].name == "Hero")
        project = try project.applying(.deleteTrack(track: "v3")).project
        #expect(!project.tracks.contains { $0.id == "v3" })

        var legacy = Project(name: "Legacy")
        legacy["schema"] = .string("bashcut.project/1")
        for index in legacy.tracks.indices { legacy.tracks[index]["name"] = nil }
        let migrated = try Project.decode(try JSONEncoder().encode(legacy))
        #expect(migrated["schema"] == .string("bashcut.project/2"))
        #expect(migrated.tracks.allSatisfy { !$0.name.isEmpty })
    }

    @Test("A nonempty layer cannot be removed")
    func nonemptyLayer() throws {
        var project = Project(name: "Protected")
        let text = Item(fields: [
            "id": .string("title"), "at": .integer(0), "dur": .integer(10),
            "text": .string("Title"),
        ])
        project = try project.applying(.insert(track: "t1", item: text)).project
        #expect(throws: ProjectError.self) { try project.applying(.deleteTrack(track: "t1")) }
    }

    @Test("Provider preferences are undoable project data")
    func providerPreference() throws {
        let original = Project(name: "Providers")
        let result = try original.applying(
            .setProviderPreference(capability: "voice.synthesize", provider: "local.voice"))
        #expect(result.project.preferredProvider(for: "voice.synthesize") == "local.voice")
        let restored = try result.project.applying(result.inverse).project
        #expect(restored.preferredProvider(for: "voice.synthesize") == nil)
    }

    @Test("Section markers use stable IDs, integer frames and undoable edits")
    func sectionMarkers() throws {
        var project = Project(name: "Sections")
        project = try project.applying(
            .upsertSection(id: "hook", label: "  Hook  ", atFrame: 0)
        ).project
        #expect(project.sectionMarkers.map(\.id) == ["hook"])
        #expect(project.sectionMarkers.map(\.label) == ["Hook"])
        let renamed = try project.applying(
            .upsertSection(id: "hook", label: "Opening", atFrame: 0))
        #expect(renamed.project.sectionMarkers.first?.label == "Opening")
        #expect(try renamed.project.applying(renamed.inverse).project.sectionMarkers == project.sectionMarkers)
        let removed = try project.applying(.deleteSection(id: "hook"))
        #expect(removed.project.sectionMarkers.isEmpty)
        #expect(try removed.project.applying(removed.inverse).project.sectionMarkers == project.sectionMarkers)
        #expect(throws: ProjectError.self) {
            try project.applying(.upsertSection(id: "other", label: "Duplicate", atFrame: 0))
        }
    }

    @Test("Optional source metadata is validated without becoming required")
    func sourceMetadata() throws {
        let media = Media(fields: [
            "id": .string("clip"), "path": .string("footage/clip.mp4"),
            "kind": .string("video"), "fps": FrameRate().json, "frames": .integer(300),
            "width": .integer(1920), "height": .integer(1080), "hasAudio": .bool(true),
        ])
        let project = try Project(name: "Metadata").applying(.addMedia(media)).project
        #expect(project.media.first?.width == 1920)
        #expect(project.media.first?.height == 1080)
        #expect(project.media.first?.hasAudio == true)
        var invalid = project
        invalid.media[0]["width"] = .integer(0)
        #expect(throws: ProjectError.self) { try invalid.validate() }
    }

    @Test("Item diff reports additions, removals, property edits and track moves in stable order")
    func itemDiff() throws {
        var before = Project(name: "Diff")
        let first = Item(fields: [
            "id": .string("a"), "at": .integer(20), "dur": .integer(10),
            "text": .string("Before"), "future": .string("old"),
        ])
        let removed = Item(fields: [
            "id": .string("b"), "at": .integer(40), "dur": .integer(10), "text": .string("Remove"),
        ])
        before = try before.applying(
            .group(label: "Seed", author: .user, ops: [
                .insert(track: "t1", item: first), .insert(track: "t1", item: removed),
            ])
        ).project
        var secondText = Track(id: "t2", kind: "text", role: "captions")
        secondText.name = "Titles"
        var after = try before.applying(.addTrack(track: secondText, atIndex: 3)).project
        after = try after.applying(
            .group(label: "Edit", author: .codex, ops: [
                .move(item: "a", toTrack: "t2", atFrame: 5),
                .setProperties(item: "a", patch: ["future": .string("new")]),
                .delete(item: "b", ripple: false),
                .insert(
                    track: "t1",
                    item: Item(fields: [
                        "id": .string("c"), "at": .integer(30), "dur": .integer(10),
                        "text": .string("Added"),
                    ])),
            ])
        ).project

        let changes = after.itemChanges(from: before)
        #expect(changes.map(\.itemID) == ["a", "c", "b"])
        #expect(changes.map(\.kind) == [.modified, .added, .removed])
        #expect(changes[0].beforeTrackID == "t1")
        #expect(changes[0].afterTrackID == "t2")
        #expect(changes[0].changedKeys.contains("future"))
    }

    @Test("Project diff includes document, media and track property changes")
    func projectDiff() {
        let before = Project(name: "Before")
        var after = before
        after.fields["style"] = .string("cinematic")
        var tracks = after.tracks
        tracks[0].name = "Primary story"
        after.tracks = tracks
        after.media = [
            Media(fields: [
                "id": .string("m"), "path": .string("media/a.mov"),
                "fps": FrameRate(30, 1).json, "frames": .integer(30),
            ])
        ]
        let changes = after.changes(from: before)
        #expect(changes.projectKeys == ["style"])
        #expect(changes.mediaIDs == ["m"])
        #expect(changes.trackIDs == ["v1"])
        #expect(changes.items.isEmpty)
        #expect(!changes.isEmpty)
    }
}
