import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

@Suite("Audio library (#78)")
struct LibraryAudioTests {
    /// A sound at the project rate of `seconds`, as the app makes it from a library audio file.
    private static func sound(_ id: String = "song", seconds: Int = 4, path: String = "music/library-abc.wav") -> Media {
        Media(fields: [
            "id": .string(id), "path": .string(path), "kind": .string("audio"), "fps": FrameRate(30, 1).json,
            "frames": .integer(seconds * 30), "hasAudio": .bool(true),
            TransitionPreset.soundLibraryField: .string("user:\(id)"),
        ])
    }

    private static func operation(_ planner: LayerPlanner) -> EditOperation {
        planner.operations.count == 1 ? planner.operations[0] : .group(label: "Place", author: .user, ops: planner.operations)
    }

    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("audio-library-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Audio params check role, length, tempo, loudness and loop, and keep other keys")
    func validation() throws {
        let params: [String: JSONValue] = [
            "role": .string("ambience"), "seconds": .number(12.5), "bpm": .integer(120), "loopable": .bool(true),
            "lufs": .number(-14.2), "truePeak": .number(-1.5), "key": .string("A minor"),
        ]
        let audio = try LibraryAudio(params: params)
        #expect(audio == LibraryAudio(role: "ambience", seconds: 12.5, bpm: 120, loopable: true, lufs: -14.2, truePeak: -1.5))
        #expect(audio.params(merging: params) == params)
        #expect(try LibraryAudio(params: [:]) == LibraryAudio())
        let bad: [([String: JSONValue], String)] = [
            (["role": .string("voice")], "params.role"),
            (["seconds": .integer(0)], "params.seconds"),
            (["bpm": .integer(900)], "params.bpm"),
            (["bpm": .string("fast")], "params.bpm"),
            (["lufs": .integer(30)], "params.lufs"),
            (["truePeak": .integer(-200)], "params.truePeak"),
            (["loopable": .string("yes")], "params.loopable"),
        ]
        for (params, message) in bad {
            let item = LibraryItem(id: "a", kind: .audio, name: "A", params: params)
            var withFile = item
            withFile["file"] = .string("files/a/v1/a.wav")
            #expect(throws: ProjectError.self) { try withFile.validate() }
            do { try withFile.validate() } catch { #expect(error.localizedDescription.contains(message)) }
        }
        // An audio item needs its file.
        #expect(throws: ProjectError.self) { try LibraryItem(id: "a", kind: .audio, name: "A").validate() }
        // Without a role, a short sound is a sound effect and a long one music.
        #expect(LibraryAudio().placementRole(seconds: 2) == "sfx")
        #expect(LibraryAudio().placementRole(seconds: 30) == "music")
        #expect(LibraryAudio(role: "ambience").placementRole(seconds: 2) == "ambience")
        #expect(LibraryAudio.trackRole("ambience") == TrackRole.music)
        #expect(LibraryAudio.projectFolder("sfx") == "sfx" && LibraryAudio.projectFolder("ambience") == "music")
    }

    @Test("Music and ambience go on the Music layer, sound effects on the SFX layer, as one undo step")
    func placeByRole() throws {
        let project = try ProjectFixtures.twoClips("a", "b")
        for (role, layer) in [("music", TrackRole.music), ("ambience", TrackRole.music), ("sfx", TrackRole.sfx)] {
            let placed = try project.audioPlacePlan(Self.sound(), role: role, at: 15)
            var history = ProjectHistory(project: project)
            try history.apply(Self.operation(placed.planner), label: "Song")
            #expect(history.undoEntries.count == 1)
            let applied = history.project
            let track = try #require(applied.track(id: placed.trackID))
            #expect(track.role == layer)
            let item = try #require(track.items.first { $0.id == placed.itemIDs.first })
            #expect(item.at == 15 && item.duration == 120 && item.mediaID == "song")
            #expect(applied.media.contains { $0.id == "song" })
            try history.undo()
            var undone = history.project
            undone["rev"] = project["rev"]  // revisions only move forward
            #expect(undone == project)
        }
        // A trim, an explicit layer, and sounds already in the project are not added again.
        let withMedia = try project.applying(.addMedia(Self.sound())).project
        let trimmed = try withMedia.audioPlacePlan(Self.sound(), role: "music", at: 0, duration: 45, trackID: "a2")
        let applied = try withMedia.applying(Self.operation(trimmed.planner)).project
        #expect(trimmed.trackID == "a2" && trimmed.duration == 45 && !trimmed.looped && !trimmed.shortened)
        #expect(applied.media.filter { $0.id == "song" }.count == 1)
        #expect(throws: ProjectError.self) { try project.audioPlacePlan(Self.sound(), role: "music", at: 0, trackID: "v1") }
        #expect(throws: ProjectError.self) {
            try project.audioPlacePlan(ProjectFixtures.media(kind: "video"), role: "music", at: 0)
        }
    }

    @Test("A missing Music or SFX layer is added in the same step; a busy one spills onto a free layer")
    func addsLayer() throws {
        var project = try ProjectFixtures.twoClips("a", "b")
        for role in [TrackRole.music, TrackRole.sfx] {
            project = try project.applying(.deleteTrack(track: try project.requireTrack(role: role).id)).project
        }
        let music = try project.audioPlacePlan(Self.sound(), role: "music", at: 0)
        var history = ProjectHistory(project: project)
        try history.apply(Self.operation(music.planner), label: "Song")
        #expect(history.undoEntries.count == 1)
        let layer = try #require(history.project.track(role: TrackRole.music, kind: "audio"))
        #expect(layer.id == music.trackID && layer.items.count == 1 && layer.name == "Music")
        #expect(layer["duckingEnabled"] == .bool(true))
        let sfx = try project.audioPlacePlan(Self.sound("hit", seconds: 1), role: "sfx", at: 0)
        let withSFX = try project.applying(Self.operation(sfx.planner)).project
        #expect(withSFX.track(role: TrackRole.sfx, kind: "audio")?.items.count == 1)
        // Placing over the first sound goes on another music layer.
        let again = try history.project.audioPlacePlan(Self.sound("other"), role: "music", at: 30)
        #expect(again.trackID != music.trackID)
        #expect(try history.project.applying(Self.operation(again.planner)).project.tracks
            .filter { $0.role == TrackRole.music }.count == 2)
    }

    @Test("A loopable sound repeats to fill a longer duration; another plays once and says so")
    func loops() throws {
        let project = try ProjectFixtures.twoClips("a", "b")
        let looped = try project.audioPlacePlan(Self.sound(), role: "music", loopable: true, at: 10, duration: 300)
        let applied = try project.applying(Self.operation(looped.planner)).project
        let items = try #require(applied.track(id: looped.trackID)).items.sorted { $0.at < $1.at }
        #expect(looped.looped && !looped.shortened && looped.duration == 300)
        #expect(items.map(\.at) == [10, 130, 250])
        #expect(items.map(\.duration) == [120, 120, 60])
        #expect(looped.itemIDs == items.map(\.id))
        let once = try project.audioPlacePlan(Self.sound(), role: "music", loopable: false, at: 10, duration: 300)
        #expect(!once.looped && once.shortened && once.duration == 120 && once.itemIDs.count == 1)
        #expect(throws: ProjectError.self) {
            try project.audioPlacePlan(Self.sound(seconds: 1), role: "sfx", loopable: true, at: 0, duration: 30 * 1000)
        }
    }

    @Test("Library sounds are copied into the project once per content")
    func projectCopies() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("project", isDirectory: true)
        let outside = folder.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let first = outside.appendingPathComponent("song.WAV")
        let same = outside.appendingPathComponent("same-song.wav")
        let other = outside.appendingPathComponent("other.wav")
        try Data("RIFF-song".utf8).write(to: first)
        try Data("RIFF-song".utf8).write(to: same)
        try Data("RIFF-other".utf8).write(to: other)

        let copy = try LibraryAudio.projectCopy(of: first, root: root, folder: "music")
        #expect(copy.deletingLastPathComponent().lastPathComponent == "music")
        #expect(copy.lastPathComponent.hasPrefix("library-") && copy.pathExtension == "wav")
        #expect(try Data(contentsOf: copy) == Data("RIFF-song".utf8))
        // The same content from another file, or asked for as a sound effect, reuses the copy.
        #expect(try LibraryAudio.projectCopy(of: same, root: root, folder: "music") == copy)
        #expect(try LibraryAudio.projectCopy(of: same, root: root, folder: "sfx") == copy)
        let digest = try LibraryStore.sha256(of: first)
        #expect(try LibraryAudio.projectCopy(of: first, root: root, folder: "music", sha256: digest) == copy)
        // Other content gets its own copy; a file already in the project is used where it is.
        let otherCopy = try LibraryAudio.projectCopy(of: other, root: root, folder: "sfx")
        #expect(otherCopy != copy && otherCopy.deletingLastPathComponent().lastPathComponent == "sfx")
        #expect(try LibraryAudio.projectCopy(of: copy, root: root, folder: "sfx") == copy)
        let music = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("music").path)
        #expect(music.count == 1)
    }

    @Test("Analysis saves length, tempo and loudness as a new version and keeps the rest")
    func analysis() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("bed.wav")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("RIFF".utf8).write(to: file)
        let store = LibraryStore.user(applicationSupport: folder.appendingPathComponent("support"))
        let catalog = LibraryCatalog(builtIn: [], user: store, project: nil)
        try catalog.add(
            LibraryItem(
                id: "bed", kind: .audio, name: "Bed", tags: ["calm"],
                params: ["role": .string("music"), "loopable": .bool(true), "key": .string("C")]),
            into: .user, file: file)
        let item = try catalog.item("user:bed")
        let measured = LibraryAudio(seconds: 31.4159, bpm: 96.04, lufs: -18.26, truePeak: -2.04)
        let updated = try store.update("bed", changes: try LibraryAudio.analysisChanges(item, measured: measured))
        #expect(updated.version == 2)
        let audio = try LibraryAudio(params: updated.params)
        #expect(audio == LibraryAudio(role: "music", seconds: 31.416, bpm: 96, loopable: true, lufs: -18.3, truePeak: -2))
        #expect(updated.params["key"] == .string("C"))
        #expect(updated.tags == ["calm"] && updated.file != nil)
        #expect(updated.history.count == 1)
        // A value a provider could not measure stays as it was.
        let partial = try store.update(
            "bed", changes: try LibraryAudio.analysisChanges(updated, measured: LibraryAudio(seconds: 31)))
        #expect(try LibraryAudio(params: partial.params).bpm == 96)
        #expect(try LibraryAudio(params: partial.params).seconds == 31)
    }

    @Test("Project audio saved to the library round-trips with its file, length and layer role")
    func saveSelectionRoundTrip() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("whoosh.wav")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("RIFF-whoosh".utf8).write(to: file)
        let media = Self.sound("whoosh", seconds: 2, path: "sfx/whoosh.wav")
        let params = try LibrarySelection.audio(media, trackRole: TrackRole.sfx)
        #expect(try LibraryAudio(params: params) == LibraryAudio(role: "sfx", seconds: 2))
        #expect(try LibrarySelection.audio(media, trackRole: TrackRole.music)["role"] == .string("music"))
        #expect(try LibrarySelection.audio(media, trackRole: TrackRole.voiceover)["role"] == nil)
        #expect(try LibrarySelection.params(.audio, item: nil, sound: media)["seconds"] == .integer(2))
        #expect(LibrarySelection.kinds.contains(.audio))
        #expect(throws: ProjectError.self) { try LibrarySelection.params(.audio, item: nil) }
        #expect(throws: ProjectError.self) { try LibrarySelection.audio(ProjectFixtures.media(kind: "video"), trackRole: nil) }

        let catalog = LibraryCatalog(
            builtIn: [], user: nil, project: .project(root: folder.appendingPathComponent("project")))
        try catalog.add(LibraryItem(id: "whoosh", kind: .audio, name: "Whoosh", params: params), into: .project, file: file)
        let read = try catalog.item("project:whoosh")
        #expect(try LibraryAudio(params: read.params) == LibraryAudio(role: "sfx", seconds: 2))
        let stored = try #require(catalog.fileURL(of: read))
        #expect(try Data(contentsOf: stored) == Data("RIFF-whoosh".utf8))
        #expect(read["fileSHA256"]?.string == (try LibraryStore.sha256(of: file)))
        // Placing what was saved puts it back on the SFX layer.
        let project = try ProjectFixtures.twoClips("a", "b")
        let audio = try LibraryAudio(params: read.params)
        let placed = try project.audioPlacePlan(
            Self.sound("whoosh", seconds: 2), role: audio.placementRole(seconds: nil), at: 0)
        #expect(project.track(id: placed.trackID)?.role == TrackRole.sfx)
    }
}
