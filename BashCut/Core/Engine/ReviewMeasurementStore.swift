import BashCutProject
import CryptoKit
import Foundation

/// Keeps the review's picture (`review.measure`) and loudness (a normalized export) measurements and the issues the
/// plugins' `review.check` reported in the project's cache, so they outlive the app session. Each record is keyed by
/// a fingerprint of what it measured: the project without its revision number, and the size, date and inode of every
/// media file it plays. Any edit, a replaced media
/// file or another format gives a new key, so a stale record is never found; an undo back to measured content finds
/// it again. Records live in `.bashcut/cache/review-measurements/<key>-<kind>.json`, and the oldest are pruned.
public enum ReviewMeasurementStore {
    /// Records kept per project; older ones are removed when a new one is stored.
    public static let limit = 24

    /// The fingerprint of `project`'s content for the measurements (its revision number left out).
    public static func key(for project: Project, projectRoot: URL, workspace: URL? = nil) -> String {
        var hasher = SHA256()
        var copy = project
        copy.revision = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        hasher.update(data: (try? encoder.encode(copy)) ?? Data(project.name.utf8))
        let manager = FileManager.default
        for media in project.media.sorted(by: { $0.id < $1.id }) {
            var stamp = "\(media.id)|missing"
            if let url = try? MediaPathResolver.resolve(media.path, projectRoot: projectRoot, workspaceRoot: workspace),
                let attributes = try? manager.attributesOfItem(atPath: url.path) {
                let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
                stamp = "\(media.id)|\((attributes[.size] as? NSNumber)?.int64Value ?? -1)|\(modified)|"
                    + "\(attributes[.systemFileNumber] ?? 0)"
            }
            hasher.update(data: Data(stamp.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Stores the picture measured for `project` (the snapshot the measurement rendered).
    public static func store(_ picture: ReviewPicture, for project: Project, projectRoot: URL, workspace: URL? = nil) throws {
        try write(
            StoredPicture(picture), kind: "picture", key: key(for: project, projectRoot: projectRoot, workspace: workspace),
            projectRoot: projectRoot)
    }

    /// Stores the loudness a normalized export of `project` measured.
    public static func store(
        _ loudness: ReviewLoudness, for project: Project, projectRoot: URL, workspace: URL? = nil
    ) throws {
        try write(
            StoredLoudness(loudness), kind: "loudness",
            key: key(for: project, projectRoot: projectRoot, workspace: workspace), projectRoot: projectRoot)
    }

    /// Stores the issues the plugins' `review.check` reported for `project` (an empty list too: the checks ran and
    /// found nothing).
    public static func store(
        pluginIssues issues: [ReviewIssue], for project: Project, projectRoot: URL, workspace: URL? = nil
    ) throws {
        try write(
            StoredPluginIssues(issues), kind: "plugins",
            key: key(for: project, projectRoot: projectRoot, workspace: workspace), projectRoot: projectRoot)
    }

    /// The stored measurements and plugin issues of content equal to `project`, given `project`'s revision.
    public static func load(
        for project: Project, projectRoot: URL, workspace: URL? = nil
    ) -> (picture: ReviewPicture?, loudness: ReviewLoudness?, pluginIssues: ReviewPluginIssues?) {
        let key = key(for: project, projectRoot: projectRoot, workspace: workspace)
        let picture = ProjectCache.record(StoredPicture.self, .reviewMeasurements, key: key + "-picture", projectRoot: projectRoot)
        let loudness = ProjectCache.record(StoredLoudness.self, .reviewMeasurements, key: key + "-loudness", projectRoot: projectRoot)
        let plugins = ProjectCache.record(StoredPluginIssues.self, .reviewMeasurements, key: key + "-plugins", projectRoot: projectRoot)
        return (
            picture?.value(revision: project.revision), loudness?.value(revision: project.revision),
            plugins?.value(revision: project.revision)
        )
    }

    private static func write<Record: Encodable>(_ record: Record, kind: String, key: String, projectRoot: URL) throws {
        try ProjectCache.store(record, .reviewMeasurements, key: key + "-" + kind, projectRoot: projectRoot)
        prune(projectRoot: projectRoot, keeping: key)
    }

    /// Removes the oldest records over `limit`, never those of `key` (written just now).
    private static func prune(projectRoot: URL, keeping key: String) {
        let folder = ProjectCache.url(.reviewMeasurements, projectRoot: projectRoot)
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]),
            files.count > limit
        else { return }
        let dated = files.map { url in
            (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        let older = dated.filter { !$0.0.lastPathComponent.hasPrefix(key) }.sorted { $0.1 < $1.1 }
        for (url, _) in older.prefix(files.count - limit) { try? manager.removeItem(at: url) }
    }
}

private struct StoredPicture: Codable {
    struct Sample: Codable {
        let frame: Int
        let luma, spread, change, peak: Double
    }
    struct Contrast: Codable {
        let ratio: Double
        let frame: Int
    }
    var version = 1
    let interval: Int
    let samples: [Sample]
    let cuts: [String: Double]
    let textContrast: [String: Contrast]

    init(_ picture: ReviewPicture) {
        interval = picture.interval
        samples = picture.samples.map {
            Sample(frame: $0.frame, luma: $0.luma, spread: $0.spread, change: $0.change, peak: $0.peak)
        }
        cuts = picture.cuts
        textContrast = picture.textContrast.mapValues { Contrast(ratio: $0.ratio, frame: $0.frame) }
    }

    func value(revision: Int) -> ReviewPicture? {
        guard version == 1 else { return nil }
        var picture = ReviewPicture(
            revision: revision, interval: interval,
            samples: samples.map {
                ReviewPicture.Sample(frame: $0.frame, luma: $0.luma, spread: $0.spread, change: $0.change, peak: $0.peak)
            },
            cuts: cuts)
        picture.textContrast = textContrast.mapValues { ReviewPicture.TextContrast(ratio: $0.ratio, frame: $0.frame) }
        return picture
    }
}

private struct StoredLoudness: Codable {
    var version = 1
    let integratedLUFS: Double
    let truePeakDbTP: Double
    let loudnessRangeLU: Double?
    let targetLUFS: Double?
    let maxTruePeakDbTP: Double?
    let preset: String?

    init(_ loudness: ReviewLoudness) {
        integratedLUFS = loudness.integratedLUFS
        truePeakDbTP = loudness.truePeakDbTP
        loudnessRangeLU = loudness.loudnessRangeLU
        targetLUFS = loudness.targetLUFS
        maxTruePeakDbTP = loudness.maxTruePeakDbTP
        preset = loudness.preset
    }

    func value(revision: Int) -> ReviewLoudness? {
        guard version == 1 else { return nil }
        return ReviewLoudness(
            revision: revision, integratedLUFS: integratedLUFS, truePeakDbTP: truePeakDbTP,
            loudnessRangeLU: loudnessRangeLU, targetLUFS: targetLUFS, maxTruePeakDbTP: maxTruePeakDbTP, preset: preset)
    }
}

private struct StoredPluginIssues: Codable {
    struct Fix: Codable {
        let command: String?
        let arguments: [String: JSONValue]
        let hint: String?
    }
    struct Issue: Codable {
        let id, kind, title, detail, severity: String
        let facts: [String: JSONValue]
        let frame: Int
        let endFrame: Int?
        let fix: Fix?
        let source: String?
    }
    var version = 1
    let issues: [Issue]

    init(_ issues: [ReviewIssue]) {
        self.issues = issues.map { issue in
            Issue(
                id: issue.id, kind: issue.kind, title: issue.title, detail: issue.detail,
                severity: issue.severity.rawValue, facts: issue.facts, frame: issue.frame, endFrame: issue.endFrame,
                fix: issue.fix.map { Fix(command: $0.command, arguments: $0.arguments, hint: $0.hint) },
                source: issue.source)
        }
    }

    func value(revision: Int) -> ReviewPluginIssues? {
        guard version == 1 else { return nil }
        return ReviewPluginIssues(revision: revision, issues: issues.map { issue in
            ReviewIssue(
                id: issue.id, title: issue.title, detail: issue.detail, frame: issue.frame, endFrame: issue.endFrame,
                severity: ReviewSeverity(rawValue: issue.severity) ?? .warning,
                fix: issue.fix.map { ReviewFix(command: $0.command, arguments: $0.arguments, hint: $0.hint) },
                source: issue.source, kind: issue.kind, facts: issue.facts)
        })
    }
}
