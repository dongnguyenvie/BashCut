import BashCutProject
import Foundation

/// What happens when an agent with an attached scope edits something outside it (#356). Settings › Agents.
public enum AgentScopeMode: String, CaseIterable, Codable, Sendable {
    /// Hold the edit and ask the user: Allow once, Allow for this request, or Reject.
    case ask
    /// Reject the edit without asking.
    case block
    /// Allow every edit; the scope only tells the agent what the request is about.
    case off
}

/// The parts of one edit that lie outside an attached scope. Empty when the edit stays inside it.
public struct AgentScopeCheck: Equatable, Sendable {
    /// Existing timeline items the edit changes that are not in the scope, in the order the edit touches them.
    public var items: [String] = []
    /// Project-wide changes the edit makes, such as `project settings` or `layer Music`.
    public var projectWide: [String] = []

    public init(items: [String] = [], projectWide: [String] = []) {
        self.items = items
        self.projectWide = projectWide
    }

    public var isInScope: Bool { items.isEmpty && projectWide.isEmpty }

    /// One line naming what lies outside: `Music.m4a (a3f…), layer Music, project settings`.
    public func summary(in project: Project) -> String {
        let names = items.map { id in
            project.tracks.lazy.compactMap { track in
                track.items.first { $0.id == id }.map { AgentScope.name($0, track: track, in: project) + " (\(id))" }
            }.first ?? id
        }
        return (names + projectWide).joined(separator: ", ")
    }

    /// The error data agents read: the item IDs and project-wide changes outside the scope.
    public var json: JSONValue {
        .object(["outOfScope": .array(items.map(JSONValue.string)), "projectWide": .array(projectWide.map(JSONValue.string))])
    }
}

/// Checks an edit against an attached scope (#356). Pure: the app decides what to do with the result.
///
/// - Item operations must target a scope item, its linked partner, or an item made inside the scope (`extra`).
/// - `insert` is in scope when the new item lies inside the scope's span (first start to last end).
/// - A transition is in scope when either of its clips is.
/// - Media, LUT imports, beat grids and new layers (and changes to a layer the same edit adds) are never held.
/// - Other layer changes, project settings, format, sections, LUT deletes and `restore` are project-wide.
/// - Ripple shifts are position-only side effects and are not checked: those inside a ripple delete or trim, and
///   moves that shift a layer's whole tail by one amount across the scope's span (closing a gap the scope left),
///   with the section markers they carry.
/// - An undo or redo is checked as the change between the two states (`check(from:to:)`).
public enum AgentScopeGuard {
    public static func check(
        _ operation: EditOperation, scope: [AgentScopeItem], extra: Set<String> = [], in project: Project
    ) -> AgentScopeCheck {
        var walker = Walker(project: project, scope: scope, extra: extra)
        walker.shifts = walker.span.map { tailShifts(operation, in: project, near: $0) } ?? ([], [])
        walker.walk(operation)
        return walker.result
    }

    /// Checks the jump from `before` (the project now) to `after` (what an undo or redo restores) against a scope.
    /// Items that differ only in position on the same layer are ripple shifts and pass; an item that comes back is
    /// in scope inside the scope's span, like an insert; an item that goes away must be in scope. Layers added or
    /// removed empty, media, LUT imports and the revision are never held; other layer, project and section changes
    /// are project-wide.
    public static func check(
        from before: Project, to after: Project, scope: [AgentScopeItem], extra: Set<String> = []
    ) -> AgentScopeCheck {
        var walker = Walker(project: before, scope: scope, extra: extra)
        for item in after.tracks.flatMap(\.items) where item.linkedItemID.map(walker.allowed.contains) == true {
            walker.allowed.insert(item.id)
        }
        walker.compare(before, after)
        return walker.result
    }

    /// Moves in `operation` that shift every item of a layer from some frame on by one amount, where the frames the
    /// tail's head crosses overlap `span` (a gap closed or opened at the scope), keyed by item ID, and the amounts
    /// (for section markers moved with them).
    static func tailShifts(
        _ operation: EditOperation, in project: Project, near span: Range<Int>
    ) -> (items: Set<String>, deltas: Set<Int>) {
        var moves: [String: (track: String, at: Int)] = [:]
        func collect(_ operation: EditOperation) {
            switch operation {
            case .group(_, _, let operations): operations.forEach(collect)
            case .move(let id, let track, let at): moves[id] = (track, at)
            default: break
            }
        }
        collect(operation)
        var items: Set<String> = []
        var deltas: Set<Int> = []
        for track in project.tracks {
            let moved = track.items.filter { moves[$0.id]?.track == track.id }
            guard let from = moved.map(\.at).min() else { continue }
            let amounts = Set(moved.compactMap { item in moves[item.id].map { $0.at - item.at } })
            guard amounts.count == 1, let delta = amounts.first, delta != 0,
                min(from, from + delta) < span.upperBound, max(from, from + delta) > span.lowerBound,
                track.items.filter({ $0.at >= from }).allSatisfy({ moves[$0.id]?.track == track.id })
            else { continue }
            items.formUnion(moved.map(\.id))
            deltas.insert(delta)
        }
        return (items, deltas)
    }

    /// The scope's span on the timeline: its items' current positions, or where they were when attached.
    public static func span(_ scope: [AgentScopeItem], in project: Project) -> Range<Int>? {
        let items = project.tracks.flatMap(\.items)
        let ranges = scope.map { attached in
            items.first { $0.id == attached.id }.map { $0.at..<$0.end } ?? attached.start..<attached.end
        }
        guard let start = ranges.map(\.lowerBound).min(), let end = ranges.map(\.upperBound).max(), start < end
        else { return nil }
        return start..<end
    }

    private struct Walker {
        let project: Project
        let span: Range<Int>?
        var allowed: Set<String>
        /// Layers added earlier in the same edit.
        var newTracks: Set<String> = []
        /// Ripple shifts in the edit (`tailShifts`): not checked.
        var shifts: (items: Set<String>, deltas: Set<Int>) = ([], [])
        var result = AgentScopeCheck()

        init(project: Project, scope: [AgentScopeItem], extra: Set<String>) {
            self.project = project
            span = AgentScopeGuard.span(scope, in: project)
            var allowed = extra.union(scope.map(\.id)).union(scope.compactMap(\.linked))
            for item in project.tracks.flatMap(\.items) where item.linkedItemID.map(allowed.contains) == true {
                allowed.insert(item.id)
            }
            self.allowed = allowed
        }

        // One exhaustive case per operation, like `EditOperation.perform`, so a new operation must be classified.
        // swiftlint:disable:next cyclomatic_complexity
        mutating func walk(_ operation: EditOperation) {
            switch operation {
            case .group(_, _, let operations):
                for operation in operations { walk(operation) }
            case .insert(_, let item):
                // An item the edit adds counts as in scope afterwards, so later ops on it are not asked twice.
                if let span, span.lowerBound <= item.at, item.end <= span.upperBound {
                    allowed.insert(item.id)
                } else {
                    flag(item.id)
                    allowed.insert(item.id)
                }
            case .move(let id, _, _):
                if !shifts.items.contains(id) { touch(id) }
            case .delete(let id, _), .trim(let id, _, _, _), .reorder(let id, _),
                .slip(let id, _), .setSpeed(let id, _, _), .setSpeedCurve(let id, _, _), .setSource(let id, _, _, _),
                .setProperties(let id, _):
                touch(id)
            case .split(let id, _, let newID):
                touch(id)
                allowed.formUnion([newID, newID + "-linked"])
            case .rippleDeleteRange(let from, let to, let scope, _):
                // What the cut removes or trims is checked; what only moves left is a ripple shift, as for trims.
                for track in project.tracks where scope?.contains(track.id) ?? true {
                    for item in track.items where item.at < to && item.end > from { touch(item.id) }
                }
            case .roll(let id, let edge, _):
                touch(id)
                if let neighbour = neighbour(of: id, at: edge) { touch(neighbour) }
            case .setLinkedAudio(let video, let audio):
                touch(video)
                if let audio { touch(audio) }
            case .upsertTransition(_, _, let from, let to, _, _, _):
                if !allowed.contains(from), !allowed.contains(to) { touch(from) }
            case .deleteTransition(let id):
                if let transition = project.transitions.first(where: { $0.id == id }),
                    !allowed.contains(transition.fromItemID), !allowed.contains(transition.toItemID)
                {
                    touch(transition.fromItemID)
                }
            case .addMedia, .addColorLUT, .setBeatGrid, .setMediaDescription, .setMediaRights,
                .setMediaData:
                break
            case .addTrack(let track, _):
                newTracks.insert(track.id)
            case .deleteTrack(let id), .moveTrack(let id, _), .setTrackProperties(let id, _):
                if !newTracks.contains(id) { wide("layer " + (project.tracks.first { $0.id == id }?.name ?? id)) }
            case .setProjectProperties:
                wide("project settings")
            case .setFormat:
                wide("project format")
            case .setProviderPreference:
                wide("provider preference")
            case .upsertSection(let id, let label, let at):
                // A section carried along by a ripple shift keeps its label and moves by the shift's amount.
                let current = project.markers.first { $0.id == id && $0.kind == "section" }
                if let current, current.label == label, shifts.deltas.contains(at - current.at) { break }
                wide("sections")
            case .deleteSection:
                wide("sections")
            case .deleteColorLUT:
                wide("colour LUTs")
            case .restore:
                wide("the whole project")
            }
        }

        /// The undo/redo check: what differs between the two states.
        mutating func compare(_ before: Project, _ after: Project) {
            func placed(_ project: Project) -> [String: (track: String, item: Item)] {
                var placed: [String: (track: String, item: Item)] = [:]
                for track in project.tracks { for item in track.items { placed[item.id] = (track.id, item) } }
                return placed
            }
            let old = placed(before), new = placed(after)
            for item in before.tracks.flatMap(\.items) {
                guard let now = new[item.id] else {
                    touch(item.id)
                    continue
                }
                guard now.track != old[item.id]?.track || !Self.samePlace(item, now.item) else { continue }
                touch(item.id)
            }
            for item in after.tracks.flatMap(\.items) where old[item.id] == nil {
                if let span, span.lowerBound <= item.at, item.end <= span.upperBound { continue }
                touch(item.id)
            }
            compareTransitions(before, after)
            compareLayers(before, after)
            let sections = { (project: Project) in project.sectionMarkers.map { [$0.id, $0.label] } }
            if sections(before) != sections(after) { wide("sections") }
            let ignored: Set<String> = ["tracks", "rev", "media", "transitions", "markers", "luts"]
            let keys = Set(before.fields.keys).union(after.fields.keys).subtracting(ignored)
            if keys.contains(where: { before[$0] != after[$0] }) { wide("project settings") }
            if Set(before.colorLUTs.map(\.id)).subtracting(after.colorLUTs.map(\.id)).isEmpty == false { wide("colour LUTs") }
        }

        /// Transitions that change, come or go between clips outside the scope.
        private mutating func compareTransitions(_ before: Project, _ after: Project) {
            let transitions = Dictionary(before.transitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let restored = Dictionary(after.transitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for id in Set(transitions.keys).union(restored.keys).sorted() where transitions[id] != restored[id] {
                guard let transition = transitions[id] ?? restored[id] else { continue }
                if !allowed.contains(transition.fromItemID), !allowed.contains(transition.toItemID) { touch(transition.fromItemID) }
            }
        }

        /// Layers whose settings change, that go away holding items, or that change order.
        private mutating func compareLayers(_ before: Project, _ after: Project) {
            let restored = Dictionary(after.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for track in before.tracks {
                if let now = restored[track.id] {
                    if !track.sameSettings(as: now) { wide("layer " + track.name) }
                } else if !track.items.isEmpty {
                    wide("layer " + track.name)
                }
            }
            let kept = Set(before.tracks.map(\.id)).intersection(restored.keys)
            if before.tracks.map(\.id).filter(kept.contains) != after.tracks.map(\.id).filter(kept.contains) {
                wide("layer order")
            }
        }

        /// Whether two states of an item differ at most in where they start.
        private static func samePlace(_ lhs: Item, _ rhs: Item) -> Bool {
            var lhs = lhs.fields, rhs = rhs.fields
            lhs["at"] = nil
            rhs["at"] = nil
            return lhs == rhs
        }

        private mutating func touch(_ id: String) {
            if !allowed.contains(id) { flag(id) }
        }

        private mutating func flag(_ id: String) {
            if !result.items.contains(id) { result.items.append(id) }
        }

        private mutating func wide(_ change: String) {
            if !result.projectWide.contains(change) { result.projectWide.append(change) }
        }

        /// The clip that shares the cut a roll moves.
        private func neighbour(of id: String, at edge: Edge) -> String? {
            guard let track = project.tracks.first(where: { $0.items.contains { $0.id == id } }),
                let item = track.items.first(where: { $0.id == id })
            else { return nil }
            return track.items.first { edge == .end ? $0.at == item.end : $0.end == item.at }?.id
        }
    }
}
