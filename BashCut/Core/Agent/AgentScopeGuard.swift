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
/// - Ripple shifts are position-only side effects and are not checked.
public enum AgentScopeGuard {
    public static func check(
        _ operation: EditOperation, scope: [AgentScopeItem], extra: Set<String> = [], in project: Project
    ) -> AgentScopeCheck {
        var walker = Walker(project: project, scope: scope, extra: extra)
        walker.walk(operation)
        return walker.result
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
            case .delete(let id, _), .trim(let id, _, _, _), .move(let id, _, _), .reorder(let id, _),
                .slip(let id, _), .setSpeed(let id, _, _), .setSpeedCurve(let id, _, _), .setSource(let id, _, _, _),
                .setProperties(let id, _):
                touch(id)
            case .split(let id, _, let newID):
                touch(id)
                allowed.formUnion([newID, newID + "-linked"])
            case .roll(let id, let edge, _):
                touch(id)
                if let neighbour = neighbour(of: id, at: edge) { touch(neighbour) }
            case .setLinkedAudio(let video, let audio):
                touch(video)
                if let audio { touch(audio) }
            case .upsertTransition(_, _, let from, let to, _, _):
                if !allowed.contains(from), !allowed.contains(to) { touch(from) }
            case .deleteTransition(let id):
                if let transition = project.transitions.first(where: { $0.id == id }),
                    !allowed.contains(transition.fromItemID), !allowed.contains(transition.toItemID)
                {
                    touch(transition.fromItemID)
                }
            case .addMedia, .addColorLUT, .setBeatGrid, .setMediaDescription, .setMediaRights:
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
            case .upsertSection, .deleteSection:
                wide("sections")
            case .deleteColorLUT:
                wide("colour LUTs")
            case .restore:
                wide("the whole project")
            }
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
