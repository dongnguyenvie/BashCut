import Testing

@testable import BashCutProject

struct LinkedEditingTests {
    private func fixture() throws -> Project {
        let media = Media(fields: [
            "id": .string("m"), "path": .string("source.mov"), "kind": .string("video"),
            "frames": .integer(600), "fps": FrameRate(30, 1).json, "hasAudio": .bool(true),
        ])
        var video = Item(id: "v", media: "m", at: 0, duration: 60)
        video.fields["linkedAudio"] = .string("a")
        var audio = Item(id: "a", media: "m", at: 0, duration: 60)
        audio.fields["linkedVideo"] = .string("v")
        return try Project(name: "Linked", fps: FrameRate(30, 1)).applying(
            .group(
                label: "Setup", author: .user,
                ops: [.addMedia(media), .insert(track: "a1", item: audio), .insert(track: "v1", item: video)]
            )
        ).project
    }

    @Test("Move, trim and slip keep linked picture and sound aligned")
    func linkedMutations() throws {
        var project = try fixture()
        project = try project.applying(.move(item: "v", toTrack: "v1", atFrame: 10)).project
        project = try project.applying(.trim(item: "a", edge: .end, toFrame: 50, ripple: false)).project
        project = try project.applying(.slip(item: "v", sourceIn: 12)).project
        let video = try #require(project.tracks.flatMap(\.items).first { $0.id == "v" })
        let audio = try #require(project.tracks.flatMap(\.items).first { $0.id == "a" })
        #expect(video.at == audio.at)
        #expect(video.duration == audio.duration)
        #expect(video.sourceIn == audio.sourceIn)
    }

    @Test("Split creates a second reciprocal linked pair and undo restores the project")
    func linkedSplitAndUndo() throws {
        let project = try fixture()
        let result = try project.applying(.split(item: "v", atFrame: 30, newID: "right"))
        let items = result.project.tracks.flatMap(\.items)
        let video = try #require(items.first { $0.id == "right" })
        let audio = try #require(items.first { $0.id == "right-linked" })
        #expect(video.linkedItemID == audio.id)
        #expect(audio.linkedItemID == video.id)
        #expect(video.at == 30 && audio.at == 30)
        var restored = try result.project.applying(result.inverse).project
        restored.revision = project.revision
        #expect(restored == project)
    }

    @Test("Unlink stops edit propagation")
    func unlink() throws {
        var project = try fixture()
        project = try project.applying(.setLinkedAudio(video: "v", audio: nil)).project
        project = try project.applying(.move(item: "v", toTrack: "v1", atFrame: 20)).project
        let items = project.tracks.flatMap(\.items)
        #expect(items.first { $0.id == "v" }?.at == 20)
        #expect(items.first { $0.id == "a" }?.at == 0)
        #expect(items.first { $0.id == "v" }?.linkedItemID == nil)
        #expect(items.first { $0.id == "a" }?.linkedItemID == nil)
    }

    @Test("Validation rejects one-way links and freeform linkage patches")
    func invalidLinks() throws {
        var project = try fixture()
        project.tracks[3].items[0].fields.removeValue(forKey: "linkedVideo")
        #expect(throws: ProjectError.self) { try project.validate() }
        let valid = try fixture()
        #expect(throws: ProjectError.self) {
            try valid.applying(.setProperties(item: "v", patch: ["linkedAudio": .string("other")]))
        }
    }

    @Test("Source insertion creates linked dialogue for video media with sound")
    func sourceInsertion() throws {
        let project = try fixture()
        let edit = try project.sourceEdit(
            mediaID: "m", sourceRange: 100..<130, at: 60, trackID: "v1", mode: .insert,
            itemID: "inserted")
        let result = try project.applying(edit).project
        let items = result.tracks.flatMap(\.items)
        #expect(items.first { $0.id == "inserted" }?.linkedItemID == "inserted-audio")
        #expect(items.first { $0.id == "inserted-audio" }?.linkedItemID == "inserted")
    }

    @Test("Magnetic reorder compacts Main and keeps Dialogue pairs aligned")
    func magneticReorder() throws {
        var project = try fixture()
        var video = Item(id: "v2", media: "m", at: 60, duration: 30, sourceIn: 60)
        video.fields["linkedAudio"] = .string("a2")
        var audio = Item(id: "a2", media: "m", at: 60, duration: 30, sourceIn: 60)
        audio.fields["linkedVideo"] = .string("v2")
        project = try project.applying(
            .group(
                label: "Second pair", author: .user,
                ops: [.insert(track: "a1", item: audio), .insert(track: "v1", item: video)]
            )
        ).project
        project = try project.applying(.reorder(item: "v2", before: "v")).project
        let main = try #require(project.tracks.first { $0.id == "v1" })
        let dialogue = try #require(project.tracks.first { $0.id == "a1" })
        #expect(main.items.map(\.id) == ["v2", "v"])
        #expect(main.items.map(\.at) == [0, 30])
        #expect(dialogue.items.first { $0.id == "a2" }?.at == 0)
        #expect(dialogue.items.first { $0.id == "a" }?.at == 30)
    }
}
