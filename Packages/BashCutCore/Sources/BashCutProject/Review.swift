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

    public static func run(_ project: Project) -> [ReviewIssue] {
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
}
