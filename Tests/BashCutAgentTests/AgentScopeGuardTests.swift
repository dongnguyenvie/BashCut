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

    @Test("Ripple shifts of later clips are not checked: ripple delete or trim of a scope clip, closing its gap")
    func rippleShifts() throws {
        #expect(try check([.delete(item: "v", ripple: true)]).isInScope)
        #expect(try check([.trim(item: "v", edge: .end, toFrame: 500, ripple: true)]).isInScope)
        // Rippling an outside clip names only that clip, not the scope clips it shifts.
        #expect(try check([.delete(item: "w", ripple: true)]).items == ["w"])
        // Lift the scope clip, then close the gap it left: the tail moves together across the span.
        var (project, scope) = try setup()
        project.markers = [TimelineMarker(at: 540, kind: "section", label: "End")]
        project = try project.applying(.delete(item: "v", ripple: false)).project
        let close = try project.closingGap(on: "v1", containing: 400)
        #expect(AgentScopeGuard.check(close, scope: scope, in: project).isInScope)
        // Moving the last clip away from the scope is no ripple: it is checked.
        let away = EditOperation.group(label: "Move", author: .agent, ops: [.move(item: "x", toTrack: "v1", atFrame: 900)])
        #expect(AgentScopeGuard.check(away, scope: scope, in: project).items == ["x"])
        // Moving one clip of a tail is checked too.
        let (whole, _) = try setup()
        let one = EditOperation.group(label: "Move", author: .agent, ops: [.move(item: "w", toTrack: "v1", atFrame: 10)])
        #expect(AgentScopeGuard.check(one, scope: scope, in: whole).items == ["w"])
    }

    @Test("Undo and redo are checked as the change between the two states")
    func undoRedo() throws {
        let (project, scope) = try setup()
        var history = ProjectHistory(project: project)
        let check = { (undo: Bool) -> AgentScopeCheck in
            let target = try #require((undo ? history.lastUndo : history.redoEntries.last)?.before)
            return AgentScopeGuard.check(from: history.project, to: target, scope: scope)
        }
        // Undoing an in-scope ripple delete brings the clip back and shifts the tail: in scope; so is its redo.
        try history.apply(.delete(item: "v", ripple: true), label: "Delete", author: .agent)
        #expect(try check(true).isInScope)
        try history.undo()
        #expect(try check(false).isInScope)
        try history.redo()
        try history.undo()
        // Undoing the user's change to another clip, or a project setting, reaches outside.
        try history.apply(.setProperties(item: "w", patch: ["opacity": .number(0.5)]), label: "Fade", author: .user)
        #expect(try check(true).items == ["w"])
        try history.undo()
        #expect(try check(false).items == ["w"])
        try history.redo()
        try history.apply(.setProjectProperties(patch: ["looks": .array([])]), label: "Looks", author: .user)
        #expect(try check(true).projectWide == ["project settings"])
        try history.undo()
        try history.undo()
        // A title the agent added inside the span goes away on undo: in scope only when it was made in scope.
        var late = Item(id: "late", at: 900, duration: 30)
        late["text"] = .string("Hi")
        try history.apply(.insert(track: "t1", item: late), label: "Add", author: .agent)
        #expect(try check(true).items == ["late"])
        #expect(AgentScopeGuard.check(
            from: history.project, to: try #require(history.lastUndo?.before), scope: scope, extra: ["late"]).isInScope)
        // A new empty layer coming or going is never held; a layer's settings are project-wide.
        try history.apply(.addTrack(track: Track(id: "t9", kind: "text", role: "titles"), atIndex: 0), label: "Layer", author: .agent)
        #expect(try check(true).isInScope)
        try history.apply(.setTrackProperties(track: "a1", patch: ["muted": .bool(true)]), label: "Mute", author: .user)
        #expect(try check(true).projectWide == ["layer Dialogue"])
    }

    @Test("A dry run's check is the apply's: the same parts outside, every time")
    func dryRun() throws {
        let (project, scope) = try setup()
        let operation = EditOperation.group(label: "Edit", author: .agent, ops: [
            .setProperties(item: "x", patch: ["opacity": .number(0.5)]), .setFormat(width: 1080, height: 1920),
        ])
        let first = AgentScopeGuard.check(operation, scope: scope, in: project)
        #expect(first.items == ["x"] && first.projectWide == ["project format"])
        #expect(AgentScopeGuard.check(operation, scope: scope, in: project) == first)
    }
}
