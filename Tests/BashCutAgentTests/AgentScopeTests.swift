import BashCutAgent
import BashCutProject
import Foundation
import Testing

struct AgentScopeTests {
    /// A 30 fps project: picture `v` (360–540) on Main linked to its sound `a` on Dialogue, and `w` after it.
    private func project() throws -> Project {
        var video = Item(id: "v", media: "m", at: 360, duration: 180)
        video.fields["linkedAudio"] = .string("a")
        var audio = Item(id: "a", media: "m", at: 360, duration: 180)
        audio.fields["linkedVideo"] = .string("v")
        let media = Media(fields: [
            "id": .string("m"), "path": .string("footage/beach.mov"), "frames": .integer(3600),
            "fps": FrameRate(30, 1).json, "kind": .string("video"), "hasAudio": .bool(true),
        ])
        return try Project(name: "Scope", fps: FrameRate(30, 1)).applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: Item(id: "w", media: "m", at: 0, duration: 360)),
            .insert(track: "a1", item: audio), .insert(track: "v1", item: video),
        ])).project
    }

    @Test("A linked pair is one scope item named after its file, with layer and range")
    func items() throws {
        let project = try project()
        let items = AgentScope.items(["a", "v"], in: project)
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.id == "v" && item.linked == "a")
        #expect(item.layer == "Main" && item.track == "v1")
        #expect(item.start == 360 && item.end == 540)
        #expect(AgentScope.label(item, fps: project.fps) == "beach.mov · Main · 00:12–00:18")
        #expect(AgentScope.items(["missing"], in: project).isEmpty)
    }

    @Test("Merging skips items already attached, also as a linked partner")
    func merge() throws {
        let project = try project()
        let first = AgentScope.items(["v"], in: project)
        let merged = AgentScope.merge(first, AgentScope.items(["a", "w"], in: project))
        #expect(merged.map(\.id) == ["v", "w"])
    }

    @Test("The scope text lists the IDs and the rule; a terminal paste puts it before the request")
    func text() throws {
        let project = try project()
        let items = AgentScope.items(["v", "w"], in: project)
        let text = AgentScope.text(items, fps: project.fps)
        #expect(text == """
            [Scope: timeline items this request is about]
            - w: beach.mov, layer Main, frames 0-360 (beach.mov · Main · 00:00–00:12)
            - v (linked a): beach.mov, layer Main, frames 360-540 (beach.mov · Main · 00:12–00:18)
            Edit only these items; ask before changing anything else.
            [/Scope]
            """)
        #expect(AgentScope.text([], fps: project.fps).isEmpty)
        #expect(AgentRequest.paste("Brighten it", scope: text) == text + "\nBrighten it\n")
        #expect(AgentRequest.paste("", scope: text) == text + "\n")
    }

    @Test("An item keeps its JSON shape for context get and the chat transcript")
    func json() {
        let item = AgentScopeItem(id: "t", track: "t1", layer: "Text", name: "Hello", start: 0, end: 30)
        #expect(item.json == .object([
            "id": .string("t"), "track": .string("t1"), "layer": .string("Text"), "name": .string("Hello"),
            "start": .integer(0), "end": .integer(30),
        ]))
    }
}
