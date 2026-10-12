import BashCutProject
import Foundation

/// The result card of an agent run that exported (#448): every file the run exported (newest first, from the
/// project's export history since the run started), the newest one's duration, loudness and cuts, and the review
/// issues still open on the current timeline. Raw facts only; what to do about them is the agent's call.
public struct RunResult: Equatable, Sendable {
    public let run: Int
    /// The run's exports, newest first.
    public let outputs: [StoredExportMetrics]
    /// Open review issues of the current revision (accepted ones are not counted).
    public let errors: Int
    public let warnings: Int
    public let accepted: Int
    /// The plan's recipe skill, when it names one.
    public let recipe: String?
    /// A still of the newest output, once written.
    public var thumbnail: URL?

    public init(
        run: Int, outputs: [StoredExportMetrics], errors: Int, warnings: Int, accepted: Int, recipe: String?,
        thumbnail: URL? = nil
    ) {
        self.run = run
        self.outputs = outputs
        self.errors = errors
        self.warnings = warnings
        self.accepted = accepted
        self.recipe = recipe
        self.thumbnail = thumbnail
    }

    /// The run's result: the exports finished since `since` (newest first, one row per path), or nil when the
    /// run exported nothing. `review` is the current `ReviewSummary`.
    public static func make(
        run: Int, since: Date?, history: [StoredExportMetrics], review: ReviewSummary, recipe: String?
    ) -> RunResult? {
        // History dates are whole seconds; the run log's too, so an export in the run's first second still counts.
        let start = since.map { $0.addingTimeInterval(-1) } ?? .distantPast
        var seen = Set<String>()
        let outputs = history.filter { $0.completedAt >= start }.reversed().filter { seen.insert($0.path).inserted }
        guard !outputs.isEmpty else { return nil }
        return RunResult(
            run: run, outputs: Array(outputs), errors: review.errors, warnings: review.warnings,
            accepted: review.accepted, recipe: recipe)
    }

    /// The newest export, the card's main file.
    public var main: StoredExportMetrics { outputs[0] }
    /// Joins between clips on Main in the newest export (its stored count is clips).
    public var cuts: Int { max(0, main.cutCount - 1) }
    /// Issues a Fix remaining issues request is about.
    public var issuesLeft: Int { errors + warnings }

    /// `run.status`'s `result`.
    public var json: JSONValue {
        let formatter = ISO8601DateFormatter()
        let files = outputs.map { output -> JSONValue in
            .object([
                "path": .string(output.path), "preset": .string(output.preset),
                "duration": .number((output.duration * 100).rounded() / 100), "bytes": .integer(Int(output.bytes)),
                "exists": .bool(FileManager.default.fileExists(atPath: output.path)),
                "completedAt": .string(formatter.string(from: output.completedAt)),
            ])
        }
        var result: [String: JSONValue] = [
            "run": .integer(run), "path": .string(main.path), "duration": .number((main.duration * 100).rounded() / 100),
            "cuts": .integer(cuts), "lufs": main.integratedLUFS.map(JSONValue.number) ?? .null,
            "truePeakDbTP": main.truePeakDbTP.map(JSONValue.number) ?? .null,
            "loudnessVerified": .bool(main.loudnessVerified),
            "review": .object([
                "errors": .integer(errors), "warnings": .integer(warnings), "accepted": .integer(accepted),
            ]),
            "outputs": .array(files), "recipe": recipe.map(JSONValue.string) ?? .null,
        ]
        result["thumbnail"] = thumbnail.map { .string($0.path) } ?? .null
        return .object(result)
    }
}
