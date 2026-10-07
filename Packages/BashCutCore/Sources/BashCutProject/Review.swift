import Foundation

/// How much a review issue matters: an error spoils the export, a warning hurts it, info is a note.
public enum ReviewSeverity: String, Sendable, CaseIterable, Comparable {
    case error, warning, info

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    /// More severe first: `.error < .warning`.
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// A suggested fix: a command with its arguments, or only a hint when no single command fixes the issue.
public struct ReviewFix: Sendable, Equatable {
    public let command: String?
    public let arguments: [String: JSONValue]
    public let hint: String?

    public init(command: String? = nil, arguments: [String: JSONValue] = [:], hint: String? = nil) {
        self.command = command
        self.arguments = arguments
        self.hint = hint
    }

    public var json: JSONValue {
        var fields: [String: JSONValue] = [:]
        if let command { fields["command"] = .string(command) }
        if !arguments.isEmpty { fields["arguments"] = .object(arguments) }
        if let hint { fields["hint"] = .string(hint) }
        return .object(fields)
    }
}

public struct ReviewIssue: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let frame: Int
    /// Where the problem ends (exclusive), for issues that span a range of the timeline.
    public let endFrame: Int?
    public let severity: ReviewSeverity
    public let fix: ReviewFix?
    /// The plugin whose `review.check` reported the issue; nil for built-in checks.
    public let source: String?
    /// Why the project keeps this warning or note (`review.accepted`, P1-E2); accepted issues are not counted.
    public var accepted: String?

    public init(
        id: String, title: String, detail: String, frame: Int, endFrame: Int? = nil, severity: ReviewSeverity = .warning,
        fix: ReviewFix? = nil, source: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.frame = frame
        self.endFrame = endFrame
        self.severity = severity
        self.fix = fix
        self.source = source
    }

    public var json: JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string(id), "title": .string(title), "detail": .string(detail), "frame": .integer(frame),
            "severity": .string(severity.rawValue),
        ]
        if let endFrame { fields["endFrame"] = .integer(endFrame) }
        if let fix { fields["fix"] = fix.json }
        if let source { fields["source"] = .string(source) }
        if let accepted { fields["accepted"] = .object(["reason": .string(accepted)]) }
        return .object(fields)
    }
}

/// What `review.run` reports besides the issues: counts per severity and whether nothing blocks an export.
public struct ReviewSummary: Sendable, Equatable {
    public let errors: Int
    public let warnings: Int
    public let infos: Int
    /// Warnings and notes the project accepted with a reason; not in the other counts.
    public let accepted: Int
    public var passed: Bool { errors == 0 }

    public init(_ issues: [ReviewIssue]) {
        let open = issues.filter { $0.accepted == nil }
        errors = open.filter { $0.severity == .error }.count
        warnings = open.filter { $0.severity == .warning }.count
        infos = open.filter { $0.severity == .info }.count
        accepted = issues.count - open.count
    }

    public var json: JSONValue {
        .object([
            "errors": .integer(errors), "warnings": .integer(warnings), "infos": .integer(infos),
            "accepted": .integer(accepted), "passed": .bool(passed),
        ])
    }
}

public enum TimelineReview {
    public static func speechCoverage(_ project: Project) -> Double {
        guard project.duration > 0 else { return 0 }
        let voiceover = project.tracks.filter { $0.role == "voiceover" }.flatMap(\.items)
        let speech = project.tracks
            .filter { $0.role != "voiceover" }
            .flatMap(\.items)
            .filter { $0["tag"]?.object["role"]?.string == "speech" }
        let regions = (speech + voiceover).sorted { $0.at < $1.at }
        var covered = 0
        var lastEnd = 0
        for region in regions {
            covered += max(0, min(project.duration, region.end) - max(lastEnd, region.at))
            lastEnd = max(lastEnd, region.end)
        }
        return Double(covered) / Double(project.duration)
    }

    /// `fontAvailable` says whether a `textStyle.font` name draws on this Mac (the app passes
    /// `ProjectFonts.isAvailable`); a missing font is flagged once, at its first item.
    public static func run(_ project: Project, fontAvailable: @escaping (String) -> Bool = { _ in true }) -> [ReviewIssue] {
        run(project, context: ReviewContext(fontAvailable: fontAvailable))
    }

    /// Every check, errors first. Mechanical problems (gaps, missing fonts, black picture) and platform facts are
    /// errors; editorial checks run on the project's `review` profile (#466) and are info without it (#470).
    public static func run(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        let main = project.tracks.first { $0.role == "main" }?.items.sorted { $0.at < $1.at } ?? []
        let voiceover = project.tracks.filter { $0.role == "voiceover" }.flatMap(\.items)
        let speech = project.tracks
            .filter { $0.role != "voiceover" }
            .flatMap(\.items)
            .filter { $0["tag"]?.object["role"]?.string == "speech" }
        var end = 0
        for clip in main {
            if clip.at > end {
                issues.append(
                    ReviewIssue(
                        id: "gap-" + clip.id, title: "Gap on Main",
                        detail: "No picture between frames \(end) and \(clip.at).", frame: end, severity: .error,
                        fix: ReviewFix(command: "timeline.close-gap", arguments: ["atFrame": .integer(end)])))
            }
            end = clip.end
        }
        // Sound or text running on after Main's last clip plays over no picture, like a gap.
        if !main.isEmpty, end < project.duration {
            issues.append(
                ReviewIssue(
                    id: "gap-end", title: "Main ends before the edit",
                    detail: "No picture between frames \(end) and \(project.duration), while other layers go on.",
                    frame: end, endFrame: project.duration, severity: .error,
                    fix: ReviewFix(hint: "Extend or add a clip on Main, or trim what runs past its end.")))
        }
        let profile = ReviewProfile(project)
        for (left, right) in zip(main, main.dropFirst())
        where left.mediaID == right.mediaID && left["transform"] == right["transform"] {
            issues.append(
                ReviewIssue(
                    id: "framing-" + right.id, title: "Repeated framing",
                    detail: "Adjacent cuts use the same source and transform.", frame: right.at, severity: .info,
                    fix: ReviewFix(hint: "Change the framing of one side, put another shot between them, or keep it on purpose.")))
        }
        issues += voiceoverIssues(project, voiceover: voiceover, speech: speech, profile: profile)
        if let limit = profile["captionLineChars"].map({ Int($0) }) {
            for text in project.tracks.filter({ $0.kind == "text" }).flatMap(\.items)
            where text.text.split(separator: "\n").contains(where: { $0.count > limit }) {
                issues.append(
                    ReviewIssue(
                        id: "caption-" + text.id, title: "Long caption line",
                        detail: "A line is longer than the project's \(limit) characters (review.captionLineChars).",
                        frame: text.at, fix: ReviewFix(hint: "Split the text with a line break or into two captions.")))
            }
        }
        issues += missingFonts(project, fontAvailable: context.fontAvailable)
        issues += glyphIssues(project, missing: context.missingGlyphs)
        issues += wordCutIssues(project, transcripts: context.transcripts)
        issues += textIssues(project, context: context)
        issues += hookIssues(project, context: context)
        issues += audioIssues(project, context: context)
        issues += pictureIssues(project, context: context)
        issues += outputIssues(project, context: context)
        issues += planIssues(project)
        issues += mustKeepIssues(project)
        issues += unreliableIssues(project, context: context)
        issues += deliveredIssues(project, delivered: context.delivered)
        if let plugins = context.pluginIssues, plugins.revision == project.revision { issues += plugins.issues }
        for caption in project.tracks.filter({ $0.kind == "text" && $0.role == "captions" }).flatMap(\.items)
        where isRecognitionLoop(caption, fps: project.fps.value) {
            issues.append(
                ReviewIssue(
                    id: "loop-" + caption.id, title: "Possible recognition loop",
                    detail: "A caption over 10 seconds or one word repeated many times: speech recognition looped and "
                        + "its timings are smeared. Do not cut on it; transcribe the stretch again "
                        + "(captions generate --from/--to, about 20 s at a time).",
                    frame: caption.at, severity: .info, fix: ReviewFix(command: "captions.generate", hint: "Use --from/--to around this caption.")))
        }
        if project.duration > 0 {
            let coverage = speechCoverage(project)
            let minimum = profile["minSpeechCoverage"]
            if minimum.map({ coverage < $0 }) ?? true {
                issues.append(
                    ReviewIssue(
                        id: "coverage", title: "Tagged speech coverage",
                        detail: String(format: "%.0f%% of the edit from clip roles and voiceover timing", coverage * 100)
                            + (minimum.map { String(format: "; the project asks for %.0f%%.", $0 * 100) } ?? "."),
                        frame: 0, severity: minimum == nil ? .info : .warning))
            }
        }
        return sorted(accepting(applyingSeverities(issues, project: project), project: project))
    }

    /// Warnings and notes the project accepted (`review.accepted`), with their reasons. Errors are never accepted:
    /// they are fixed, or their severity is changed in `review.severities` for a stated reason.
    static func accepting(_ issues: [ReviewIssue], project: Project) -> [ReviewIssue] {
        let accepted = project["review"]?.object["accepted"]?.object ?? [:]
        guard !accepted.isEmpty else { return issues }
        return issues.map { issue in
            guard issue.severity != .error, let reason = accepted[issue.id]?.object["reason"]?.string else { return issue }
            var copy = issue
            copy.accepted = reason
            return copy
        }
    }

    /// Errors first, then warnings, then info; issues of one severity keep the order the checks found them in.
    static func sorted(_ issues: [ReviewIssue]) -> [ReviewIssue] {
        issues.enumerated().sorted { ($0.element.severity.rank, $0.offset) < ($1.element.severity.rank, $1.offset) }
            .map(\.element)
    }

    /// One issue per `textStyle.font` that does not draw on this Mac, at its first text item.
    static func missingFonts(_ project: Project, fontAvailable: (String) -> Bool) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        var checkedFonts: Set<String> = []
        for text in project.tracks.filter({ $0.kind == "text" }).flatMap(\.items).sorted(by: { $0.at < $1.at }) {
            guard let font = text["textStyle"]?.object["font"]?.string, checkedFonts.insert(font).inserted,
                !fontAvailable(font)
            else { continue }
            issues.append(
                ReviewIssue(
                    id: "font-" + text.id, title: "Missing font",
                    detail: "\(font) is not installed and not in the project's fonts folder, so it draws as Helvetica. "
                        + "Add it with fonts import, or pick another (fonts list).",
                    frame: text.at, severity: .error, fix: ReviewFix(command: "fonts.import")))
        }
        return issues
    }

    /// A caption longer than 10 s, or one where a word comes 4 times in a row or makes up half of 6+ words.
    static func isRecognitionLoop(_ caption: Item, fps: Double) -> Bool {
        if Double(caption.duration) > 10 * fps { return true }
        let words = caption.text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var run = 1
        for (previous, word) in zip(words, words.dropFirst()) {
            run = previous == word ? run + 1 : 1
            if run >= 4 { return true }
        }
        guard words.count >= 6 else { return false }
        let most = Dictionary(grouping: words, by: { $0 }).values.map(\.count).max() ?? 0
        return most * 2 >= words.count
    }
}

extension TimelineReview {
    /// Voiceover over tagged speech: with `review.voiceoverMarginSeconds`, closer than that (warning); without it,
    /// only actual overlap, as info.
    static func voiceoverIssues(_ project: Project, voiceover: [Item], speech: [Item], profile: ReviewProfile) -> [ReviewIssue] {
        let marginSeconds = profile["voiceoverMarginSeconds"]
        let margin = Int(((marginSeconds ?? 0) * project.fps.value).rounded(.up))
        return voiceover.filter { voice in
            speech.contains { voice.at < $0.end + margin && voice.end > $0.at - margin }
        }.map { voice in
            ReviewIssue(
                id: "overlap-" + voice.id, title: "Voiceover over real speech",
                detail: marginSeconds.map { String(format: "Closer than the project's %.1f s to tagged speech.", $0) }
                    ?? "It plays over tagged speech.",
                frame: voice.at, severity: marginSeconds == nil ? .info : .warning,
                fix: ReviewFix(hint: "Move the voiceover or mute the speech under it."))
        }
    }
}
