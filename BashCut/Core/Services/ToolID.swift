import Foundation

/// The ids of the built-in tools in the Tools panel (`ui action panel captions`, `ui view` reports the shown `tool`).
/// A plugin's tool view is `<plugin>/<view>` and its tool action is the action id; `ui action panel` takes those too.
public enum ToolID {
    public static let captions = "captions"
    public static let voice = "voice"
    public static let beats = "beats"
    /// The built-in tools in list order.
    public static let builtIn = [captions, voice, beats]
}

/// What a tool card's Run acts on (P1-4). Each tool lists the ones it supports.
public enum ToolTarget: String, CaseIterable, Identifiable, Sendable {
    case selectedClip = "selection"
    case wholeTimeline = "timeline"
    case project

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .selectedClip: String(localized: "Selected clip")
        case .wholeTimeline: String(localized: "Whole timeline")
        case .project: String(localized: "This project")
        }
    }

    /// The targets a built-in tool supports, first is the default.
    public static func supported(by tool: String) -> [ToolTarget] {
        switch tool {
        case ToolID.captions, ToolID.beats: [.selectedClip, .project]
        default: [.project]
        }
    }

    /// The targets a plugin action supports, from what its `when` condition and `context` ask for: an action that needs
    /// a selection runs on the selected clip, one that reads the timeline on the whole timeline, any other on the project.
    public static func supported(whenCondition: String?, readsTimeline: Bool) -> [ToolTarget] {
        let clauses = (whenCondition ?? "").split(separator: "&&").map { $0.trimmingCharacters(in: .whitespaces) }
        if clauses.contains(where: { $0 == "selection" || $0.hasPrefix("selection.") || $0.hasPrefix("selection ") }) {
            return [.selectedClip]
        }
        return readsTimeline ? [.wholeTimeline] : [.project]
    }
}
