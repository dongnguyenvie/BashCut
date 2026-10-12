import BashCutProjectFixtures
import Testing

@testable import BashCutProject

struct LinkedEditingTests {
    private func fixture() throws -> Project {
        try ProjectFixtures.linkedPair()
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

    @Test("Deleting a clip's linked sound keeps its picture, unlinked; deleting the picture still takes its sound")
    func deleteLinkedSound() throws {
        let project = try fixture()
        let result = try project.applying(.delete(item: "a", ripple: true))
        let items = result.project.tracks.flatMap(\.items)
        #expect(items.first { $0.id == "a" } == nil)
        let video = try #require(items.first { $0.id == "v" })
        #expect(video.linkedItemID == nil && video.at == 0 && video.duration == 60)
        #expect(throws: Never.self) { try result.project.validate() }
        var restored = try result.project.applying(result.inverse).project
        restored.revision = project.revision
        #expect(restored == project)
        let both = try project.applying(.delete(item: "v", ripple: false)).project
        #expect(both.tracks.allSatisfy { $0.items.isEmpty })
    }

    /// A silent clip "s" then the linked pair "v"/"a" on Main, with the pair's sound alone on the dialogue layer, or
    /// on another sound layer.
    private func stillThenPair(soundTrack: String = "a1") throws -> Project {
        var project = try fixture()
        var operations: [EditOperation] = [.addMedia(Media(fields: [
            "id": .string("silent"), "path": .string("silent.mov"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
            "frames": .integer(300), "hasAudio": .bool(false),
        ]))]
        if soundTrack != "a1" {
            var track = Track(id: soundTrack, kind: "audio", role: TrackRole.dialogue)
            track.name = "Dialogue 2"
            operations.append(.addTrack(track: track, atIndex: project.tracks.count))
        }
        operations += [
            .move(item: "v", toTrack: "v1", atFrame: 30),
            .insert(track: "v1", item: Item(id: "s", media: "silent", at: 0, duration: 30)),
        ]
        project = try project.applying(.group(label: "Setup", author: .user, ops: operations)).project
        if soundTrack != "a1" { project = try project.applying(.move(item: "a", toTrack: soundTrack, atFrame: 30)).project }
        return project
    }

    @Test("A ripple on Main carries the linked sound of the clips it moves, on whichever layer it is")
    func rippleCarriesOtherClipsSound() throws {
        for layer in ["a1", "a9"] {
            let project = try stillThenPair(soundTrack: layer)
            let items = { (project: Project) in Dictionary(uniqueKeysWithValues: project.tracks.flatMap(\.items).map { ($0.id, $0) }) }
            #expect(items(project)["a"]?.at == 30)
            let deleted = try project.applying(.delete(item: "s", ripple: true)).project
            #expect(items(deleted)["v"]?.at == 0 && items(deleted)["a"]?.at == 0, "layer \(layer)")
            #expect(throws: Never.self) { try deleted.validate() }
            let trimmed = try project.applying(.trim(item: "s", edge: .end, toFrame: 20, ripple: true)).project
            #expect(items(trimmed)["v"]?.at == 20 && items(trimmed)["a"]?.at == 20, "layer \(layer)")
            let result = try project.applying(.delete(item: "s", ripple: true))
            var restored = try result.project.applying(result.inverse).project
            restored.revision = project.revision
            #expect(restored == project)
        }
    }

    @Test("Ripple-deleting a linked pair moves a later pair and its sound once, not twice")
    func ripplePairOnce() throws {
        var project = try fixture()
        var later = Item(id: "v2", media: "m", at: 60, duration: 30)
        later.fields["linkedAudio"] = .string("a2")
        var sound = Item(id: "a2", media: "m", at: 60, duration: 30)
        sound.fields["linkedVideo"] = .string("v2")
        project = try project.applying(.group(label: "More", author: .user, ops: [
            .insert(track: "a1", item: sound), .insert(track: "v1", item: later),
        ])).project
        let after = try project.applying(.delete(item: "v", ripple: true)).project
        let items = Dictionary(uniqueKeysWithValues: after.tracks.flatMap(\.items).map { ($0.id, $0) })
        #expect(items["v2"]?.at == 0 && items["a2"]?.at == 0)
        let slowed = try project.applying(.setSpeed(item: "v", speed: 2, keepDuration: false)).project
        let moved = Dictionary(uniqueKeysWithValues: slowed.tracks.flatMap(\.items).map { ($0.id, $0) })
        #expect(moved["v2"]?.at == 30 && moved["a2"]?.at == 30)
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
