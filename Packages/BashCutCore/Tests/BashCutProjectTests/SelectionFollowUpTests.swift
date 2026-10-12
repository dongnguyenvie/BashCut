import BashCutProjectFixtures
import Foundation
import Testing
@testable import BashCutProject

/// #357 follow-ups: a block move on the magnetic layer, multi-edit patches and the pasteboard clipboard.
struct SelectionFollowUpTests {
    /// Four 30-frame clips a, b, c, d on the magnetic main layer at 0, 30, 60, 90.
    private func mainClips() throws -> Project {
        let project = Project(name: "Main", fps: FrameRate(30, 1))
        return try project.applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(ProjectFixtures.media()),
        ] + ["a", "b", "c", "d"].enumerated().map { index, id in
            .insert(track: "v1", item: Item(id: id, media: "m", at: index * 30, duration: 30, sourceIn: index * 60))
        })).project
    }

    private func order(_ project: Project) -> [String] {
        (project.track(id: "v1")?.items ?? []).sorted { $0.at < $1.at }.map(\.id)
    }

    @Test("Selected clips on the magnetic layer move as one block, in order; one undo restores them")
    func blockReorder() throws {
        let project = try mainClips()
        let ops = try SelectionEdits.reorder(["c", "a"], on: "v1", before: "d", in: project)
        var history = ProjectHistory(project: project)
        try history.apply(.group(label: "Move", author: .user, ops: ops), label: "Move", author: .user)
        #expect(order(history.project) == ["b", "a", "c", "d"])
        #expect(history.project.track(id: "v1")?.items.map(\.at).sorted() == [0, 30, 60, 90])
        try history.undo()
        #expect(order(history.project) == ["a", "b", "c", "d"])
        let end = try project.applying(.group(
            label: "Move", author: .user, ops: try SelectionEdits.reorder(["a", "b"], on: "v1", before: nil, in: project))).project
        #expect(order(end) == ["c", "d", "a", "b"])
        #expect(try SelectionEdits.reorder(["a", "b"], on: "v1", before: "c", in: project).isEmpty)
        #expect(throws: ProjectError.self) { try SelectionEdits.reorder(["a", "b"], on: "v1", before: "b", in: project) }
    }

    @Test("A dropped block goes before the first clip outside it whose middle is after the drop")
    func anchor() throws {
        let project = try mainClips()
        #expect(SelectionEdits.anchor(["a", "b"], on: "v1", at: 80, in: project) == "d")
        #expect(SelectionEdits.anchor(["a", "b"], on: "v1", at: 200, in: project) == nil)
        #expect(SelectionEdits.anchor(["c"], on: "v1", at: 0, in: project) == "a")
    }

    @Test("Multi-edit sets a property on every selected item it applies to and merges into groups")
    func patch() throws {
        var project = try mainClips()
        project = try project.applying(.setProperties(item: "a", patch: ["transform": .object(["pan": .number(40)])])).project
        var caption = Item(id: "t", at: 0, duration: 30)
        caption["text"] = .string("Hi")
        project = try project.applying(.insert(track: "t1", item: caption)).project
        let zoom = SelectionEdits.patch(["a", "b", "t"], key: "zoom", group: "transform", value: .number(1.2), in: project)
        #expect(zoom.count == 2)
        project = try project.applying(.group(label: "Zoom", author: .user, ops: zoom)).project
        let a = try #require(project.tracks.flatMap(\.items).first { $0.id == "a" })
        #expect(a["transform"] == .object(["pan": .number(40), "zoom": .number(1.2)]))
        #expect(SelectionEdits.patch(["a", "t"], key: "opacity", value: .number(0.5), in: project).count == 2)
        #expect(SelectionEdits.patch(["t"], key: "volumeDb", value: .number(-6), in: project).isEmpty)
    }

    @Test("Pasteboard JSON pastes into another project: media added with a path from there, timing converted")
    func pasteboard() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: base) }
        let first = base.appendingPathComponent("one"), second = base.appendingPathComponent("two")
        var source = try mainClips()
        source = try source.applying(.setProperties(item: "b", patch: [
            "keyframes": ItemMotion(keys: ["opacity": [.init(frame: 0, value: 0), .init(frame: 29, value: 1)]]).json,
        ])).project
        let copied = try #require(TimelineClipboard(copying: ["b", "c"], from: source))
        let json = copied.pasteboardJSON(from: source, projectRoot: first)
        #expect(json.object["media"]?.array.first?.object["absolutePath"] == .string(first.appendingPathComponent("clip.mov").path))
        let data = try JSONEncoder().encode(json)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        // Another project at 60 fps that already has a different media under the ID "m".
        var target = Project(name: "Other", fps: FrameRate(60, 1))
        target = try target.applying(.addMedia(ProjectFixtures.media("m", path: "other.mov"))).project
        let read = try TimelineClipboard.fromPasteboard(decoded, into: target, projectRoot: second)
        #expect(read.addMedia.count == 1)
        guard case .addMedia(let added) = read.addMedia[0] else { throw ProjectError.invalid("expected addMedia") }
        #expect(added.id != "m" && added.path == "../one/clip.mov")
        let staged = try target.applying(.group(label: "Paste", author: .user, ops: read.addMedia)).project
        let pasted = try read.clipboard.paste(at: 0, in: staged)
        let result = try staged.applying(.group(label: "Paste", author: .user, ops: pasted.operations)).project
        let items = result.tracks.flatMap(\.items).filter { pasted.ids.contains($0.id) }.sorted { $0.at < $1.at }
        #expect(items.count == 2 && items.allSatisfy { $0.mediaID == added.id })
        #expect(items.map(\.duration) == [60, 60] && items.map(\.at) == [0, 60])
        #expect(items[0].motion?.keys["opacity"]?.map(\.frame) == [0, 58])

        // Pasting back into the first project reuses its media.
        let back = try TimelineClipboard.fromPasteboard(decoded, into: source, projectRoot: first)
        #expect(back.addMedia.isEmpty && back.clipboard.entries.allSatisfy { $0.item.mediaID == "m" })
        #expect(throws: ProjectError.self) {
            try TimelineClipboard.fromPasteboard(.object(["version": .integer(99)]), into: source, projectRoot: first)
        }
    }
}
