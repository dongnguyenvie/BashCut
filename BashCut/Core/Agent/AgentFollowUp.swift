import BashCutProject
import Foundation

/// A one-click request on the selected clips (#449), next to Send to Agent. Each one goes to the open agent with the
/// clips as its scope and ends with a review of that range.
public enum QuickEdit: String, CaseIterable, Sendable {
    case faster
    case remove
    case musicLower = "music-lower"
    case caption
    case punchIn = "punch-in"
    case custom

    /// What the agent is asked to do; the scope block before it names the clips. No numbers: the agent measures
    /// and picks them from its skills.
    var ask: String {
        switch self {
        case .faster:
            "Make this part faster: tighten the pauses and trims inside it and speed up slow stretches where that "
                + "still reads well. Keep every word that carries the meaning."
        case .remove:
            "Remove this part from the edit without leaving a gap, and smooth the join it leaves in picture and sound."
        case .musicLower:
            "Lower the music under this part so the voice and the sounds in it come through clearly. Measure the mix "
                + "here before and after (audio mix-measure)."
        case .caption:
            "Add captions for this part: the words spoken, or one short title if nothing is said, in the project's "
                + "caption style."
        case .punchIn:
            "Add more punch-ins in this part: reframe within the zoom headroom each clip has, so consecutive shots "
                + "do not look the same."
        case .custom: ""
        }
    }
}

/// The requests BashCut words for an agent from a button: quick edits on the selection and the run result card's
/// follow-ups (#448, #449). They name commands and checks, never editorial numbers.
public enum AgentFollowUp {
    /// The timeline frames `[start, end)` the items cover together; nil without items.
    public static func range(_ items: [AgentScopeItem]) -> ClosedRange<Int>? {
        guard let start = items.map(\.start).min(), let end = items.map(\.end).max(), end > start else { return nil }
        return start...end
    }

    /// The music items under `range`: Lower music is about the bed under the clips, so it joins the scope.
    public static func musicItems(under range: ClosedRange<Int>, in project: Project) -> [String] {
        project.tracks.filter { $0.role == TrackRole.music }.flatMap(\.items)
            .filter { $0.at < range.upperBound && $0.end > range.lowerBound }.map(\.id)
    }

    /// A quick edit's request: the ask (or the user's text for custom, else added after the ask), then a review of
    /// just that range. Throws when custom has no text or there is no range.
    public static func quickEdit(_ kind: QuickEdit, text: String?, items: [AgentScopeItem]) throws -> String {
        let note = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let range = range(items) else { throw ProjectError.invalid("Select the clips the quick edit is about") }
        let ask: String
        switch kind {
        case .custom:
            guard !note.isEmpty else { throw ProjectError.invalid("Write what to change") }
            ask = note
        default: ask = note.isEmpty ? kind.ask : kind.ask + "\nAlso: " + note
        }
        return ask + "\n\n" + reviewRange(range)
    }

    /// The review that ends every quick edit: the range's issues only, each fix proven, a short answer.
    static func reviewRange(_ range: ClosedRange<Int>) -> String {
        "Then review only this range: review run --summary --from \(range.lowerBound) --to \(range.upperBound). Fix "
            + "what it finds there, prove each fix with review verify, and answer in one or two lines with what changed."
    }

    /// Fix remaining issues on the result card: what is left and the loop to close it, then the same export again.
    public static func fixIssues(errors: Int, warnings: Int, output: String?) -> String {
        let exported = output.map { "The export is done (\($0)). " } ?? ""
        return exported + "The review still shows \(errors) errors and \(warnings) warnings on the current timeline. "
            + "Fix them: review run --summary, one labelled edit per issue, prove each with review verify, and accept "
            + "with a reason only what cannot be fixed. Then export again with the same settings and say in two lines "
            + "what changed."
    }

    /// Try another recipe on the result card: keep this version, then make a new one with `recipe` or a recipe
    /// other than `current` that fits the footage and brief.
    public static func anotherRecipe(current: String?, recipe: String?) -> String {
        let pick: String
        if let recipe, !recipe.isEmpty {
            pick = "Make another version of this video with the recipe \(recipe) (skills get \(recipe))."
        } else if let current {
            pick = "Make another version of this video with a different recipe than \(current): pick the one that "
                + "best fits the footage and the brief, and say why in one line."
        } else {
            pick = "Make another version of this video with a recipe: pick the one that best fits the footage and "
                + "the brief, and say why in one line."
        }
        return pick + " Keep this version as it is (project derive for the new one), plan the new version from the "
            + "recipe, edit, review and export it like this one."
    }
}
