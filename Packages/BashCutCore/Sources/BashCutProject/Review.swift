import Foundation

public struct ReviewIssue: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let frame: Int
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
    public static func run(_ project: Project, fontAvailable: (String) -> Bool = { _ in true }) -> [ReviewIssue] {
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
                        detail: "No picture between frames \(end) and \(clip.at).", frame: end))
            }
            end = clip.end
        }
        for (left, right) in zip(main, main.dropFirst())
        where left.mediaID == right.mediaID && left["transform"] == right["transform"] {
            issues.append(
                ReviewIssue(
                    id: "framing-" + right.id, title: "Repeated framing",
                    detail: "Adjacent cuts use the same source and transform.", frame: right.at))
        }
        for voice in voiceover {
            let margin = Int((0.3 * project.fps.value).rounded(.up))
            if speech.contains(where: { voice.at < $0.end + margin && voice.end > $0.at - margin }) {
                issues.append(
                    ReviewIssue(
                        id: "overlap-" + voice.id, title: "Voiceover near real speech",
                        detail: "Keep at least 0.3 seconds between voiceover and tagged speech.",
                        frame: voice.at))
            }
        }
        for text in project.tracks.filter({ $0.kind == "text" }).flatMap(\.items)
        where text.text.split(separator: "\n").contains(where: { $0.count > 42 }) {
            issues.append(
                ReviewIssue(
                    id: "caption-" + text.id, title: "Long caption line",
                    detail: "Consider splitting lines longer than 42 characters.", frame: text.at))
        }
        issues += missingFonts(project, fontAvailable: fontAvailable)
        for caption in project.tracks.filter({ $0.kind == "text" && $0.role == "captions" }).flatMap(\.items)
        where isRecognitionLoop(caption, fps: project.fps.value) {
            issues.append(
                ReviewIssue(
                    id: "loop-" + caption.id, title: "Possible recognition loop",
                    detail: "A caption over 10 seconds or one word repeated many times: speech recognition looped and "
                        + "its timings are smeared. Do not cut on it; transcribe the stretch again "
                        + "(captions generate --from/--to, about 20 s at a time).",
                    frame: caption.at))
        }
        if project.duration > 0 {
            let coverage = speechCoverage(project)
            if coverage < 0.9 {
                issues.append(
                    ReviewIssue(
                        id: "coverage", title: "Tagged speech coverage below 90%",
                        detail: String(
                            format:
                                "%.0f%% from clip roles and voiceover timing. Audio has not been transcribed or measured.",
                            coverage * 100), frame: 0))
            }
        }
        return issues
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
                    frame: text.at))
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
