import BashCutAgent
import BashCutProject
import Foundation
import Testing

struct AgentScopeGuardTests {
    /// A 30 fps project: `w` (0–360), picture `v` (360–540) linked to its sound `a` on Dialogue, and `x` (540–720).
    /// The scope is `v`.
    private func setup() throws -> (Project, [AgentScopeItem]) {
        var video = Item(id: "v", media: "m", at: 360, duration: 180)
        video.fields["linkedAudio"] = .string("a")
        var audio = Item(id: "a", media: "m", at: 360, duration: 180)
        audio.fields["linkedVideo"] = .string("v")
        let media = Media(fields: [
            "id": .string("m"), "path": .string("footage/beach.mov"), "frames": .integer(3600),
            "fps": FrameRate(30, 1).json, "kind": .string("video"), "hasAudio": .bool(true),
        ])
        let project = try Project(name: "Guard", fps: FrameRate(30, 1)).applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: Item(id: "w", media: "m", at: 0, duration: 360)),
            .insert(track: "a1", item: audio), .insert(track: "v1", item: video),
            .insert(track: "v1", item: Item(id: "x", media: "m", at: 540, duration: 180)),
        ])).project
        return (project, AgentScope.items(["v"], in: project))
    }

    private func check(_ ops: [EditOperation], extra: Set<String> = []) throws -> AgentScopeCheck {
        let (project, scope) = try setup()
        return AgentScopeGuard.check(.group(label: "Edit", author: .agent, ops: ops), scope: scope, extra: extra, in: project)
    }

    @Test("Edits to scope items, their linked partners and halves they split off stay in scope")
    func inScope() throws {
        #expect(try check([
            .setProperties(item: "v", patch: ["opacity": .number(0.5)]),
            .trim(item: "a", edge: .end, toFrame: 500, ripple: false),
            .split(item: "v", atFrame: 450, newID: "s"),
            .setProperties(item: "s", patch: ["volume": .number(0.5)]),
            .setProperties(item: "s-linked", patch: ["volume": .number(0.5)]),
            .upsertTransition(id: "t", kind: "dissolve", from: "w", to: "v", duration: 10),
        ]).isInScope)
    }

    @Test("Edits to other items name them; a roll also touches the clip on the other side of the cut")
    func outOfScope() throws {
        let (project, _) = try setup()
        let check = try check([
            .setProperties(item: "w", patch: ["opacity": .number(0.5)]),
            .delete(item: "w", ripple: true),
            .roll(item: "v", edge: .end, toFrame: 560),
        ])
        #expect(check.items == ["w", "x"])
        #expect(check.projectWide.isEmpty)
        #expect(check.summary(in: project) == "beach.mov (w), beach.mov (x)")
        #expect(check.json == .object([
            "outOfScope": .array([.string("w"), .string("x")]), "projectWide": .array([]),
        ]))
        #expect(try self.check([.upsertTransition(id: "t", kind: "dissolve", from: "x", to: "y", duration: 10)]).items == ["x"])
    }

    @Test("New items count as in scope inside the scope's span only, and are asked about once")
    func newItems() throws {
        let inside = Item(id: "title", at: 400, duration: 100)
        let outside = Item(id: "late", at: 600, duration: 100)
        #expect(try check([
            .insert(track: "v1", item: inside), .setProperties(item: "title", patch: ["text": .string("Hi")]),
        ]).isInScope)
        let check = try check([
            .insert(track: "v1", item: outside), .setProperties(item: "late", patch: ["text": .string("Hi")]),
        ])
        #expect(check.items == ["late"])
        #expect(try self.check([.setProperties(item: "w", patch: [:])], extra: ["w"]).isInScope)
    }

    @Test("Project-wide edits are always outside; media, LUT imports and new layers never are")
    func projectWide() throws {
        let check = try check([
            .setProjectProperties(patch: ["looks": .array([])]),
            .setTrackProperties(track: "a1", patch: ["muted": .bool(true)]),
            .setFormat(width: 1080, height: 1920),
            .upsertSection(id: "s", label: "Intro", atFrame: 0),
        ])
        #expect(check.items.isEmpty)
        #expect(check.projectWide == ["project settings", "layer Dialogue", "project format", "sections"])
        let track = Track(fields: ["id": .string("new"), "kind": .string("video"), "name": .string("B-roll"), "items": .array([])])
        #expect(try self.check([
            .addTrack(track: track, atIndex: 0), .setTrackProperties(track: "new", patch: ["muted": .bool(true)]),
            .addColorLUT(ColorLUT(name: "Warm", path: "luts/warm.cube", size: 33)),
        ]).isInScope)
    }

    @Test("The span follows the scope items where they are now")
    func span() throws {
        var (project, scope) = try setup()
        #expect(AgentScopeGuard.span(scope, in: project) == 360..<540)
        project = try project.applying(.move(item: "v", toTrack: "v1", atFrame: 900)).project
        #expect(AgentScopeGuard.span(scope, in: project) == 900..<1080)
        scope[0].id = "gone"
        #expect(AgentScopeGuard.span(scope, in: project) == 360..<540)
    }
}
