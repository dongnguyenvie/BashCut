import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation

/// A measured record per source media (P0-A1): `media.analyze` measures, `media.analysis` reads with the agent's
/// limits, `media.cuts` corrects the cut list, and `media.list --analysis` shows what is measured.
extension ProjectDocument {
    /// The project folder and the original file of `mediaID`.
    func analysisSource(_ mediaID: String) throws -> (root: URL, media: Media, url: URL) {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        guard let media = project.media.first(where: { $0.id == mediaID }) else {
            throw RPCFailure(-32602, "Unknown media \(mediaID)")
        }
        guard let url = try? MediaPathResolver.resolve(media.path, projectRoot: root, workspaceRoot: settings.workspace),
            FileManager.default.fileExists(atPath: url.path)
        else { throw RPCFailure(-32602, "The file of media \(mediaID) is missing") }
        return (root, media, url)
    }

    /// The stored record of `mediaID` for its file as it is now, or nil when it was not measured (or changed since).
    func storedAnalysis(_ mediaID: String) throws -> (root: URL, record: MediaAnalysis?) {
        let source = try analysisSource(mediaID)
        let key = try MediaAnalyzer.key(for: source.url)
        return (source.root, MediaAnalyzer.load(key: key, projectRoot: source.root))
    }

    /// Measures the listed media (every video and audio media when nil) one after another, reusing stored records
    /// unless `force`. Images are skipped.
    func startMediaAnalyze(mediaID: String?, force: Bool, rate: Double?, author: Author) throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        if let running = jobs.jobs.first(where: { $0.method == "media.analyze" && $0.isActive }) {
            return .object(["job": .string(running.id), "state": .string("running")])
        }
        let selected = try mediaID.map { [try analysisSource($0).media] } ?? project.media.filter { !$0.isImage }
        let workspace = settings.workspace
        let id = jobs.start("media.analyze", author: author, work: { reporter in
            var results: [JSONValue] = []
            for (index, media) in selected.enumerated() {
                try Task.checkCancellation()
                reporter.progress(Double(index) / Double(max(1, selected.count)), detail: media.id)
                var row: [String: JSONValue] = ["media": .string(media.id)]
                defer { results.append(.object(row)) }
                guard let url = try? MediaPathResolver.resolve(media.path, projectRoot: root, workspaceRoot: workspace),
                    FileManager.default.fileExists(atPath: url.path)
                else {
                    row["status"] = .string("missing")
                    continue
                }
                let key = try await Self.analysisKey(url)
                row["key"] = .string(key)
                if !force, MediaAnalyzer.load(key: key, projectRoot: root) != nil {
                    row["status"] = .string("reused")
                    continue
                }
                let record = try await MediaAnalyzer.measure(
                    url, key: key, fps: media.fps, frames: media.frames,
                    pictureURL: ProxyMediaSource.proxyURL(for: media, root: root), samplesPerSecond: rate ?? 4)
                try MediaAnalyzer.save(record, projectRoot: root)
                row["status"] = .string("measured")
                row["overview"] = record.overviewJSON
            }
            return .object(["media": .array(results)])
        }, finished: { [weak self] outcome in
            guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
            self?.message = "media.analyze: " + error.localizedDescription
        })
        return .object(["job": .string(id), "state": .string("running")])
    }

    /// Hashes off the main actor: it reads up to two mebibytes of the file.
    nonisolated static func analysisKey(_ url: URL) async throws -> String { try MediaAnalyzer.key(for: url) }

    /// Seconds from a comma-separated list.
    static func seconds(_ text: String?) throws -> [Double] {
        guard let text, !text.isEmpty else { return [] }
        return try text.split(separator: ",").map { part in
            guard let value = Double(part.trimmingCharacters(in: .whitespaces)) else {
                throw RPCFailure(-32602, "Not a number of seconds: \(part)")
            }
            return value
        }
    }

    func registerMediaAnalysisCommands() {
        handleAuthored("media.analyze") { document, arguments, author in
            try document.startMediaAnalyze(
                mediaID: arguments.optionalString("media"), force: arguments.bool("force"),
                rate: arguments.optionalDouble("rate"), author: author)
        }
        handle("media.analysis") { document, arguments, _ in
            let mediaID = try arguments.string("media")
            guard let record = try document.storedAnalysis(mediaID).record else {
                throw RPCFailure(-32602, "Media \(mediaID) is not analysed: run media analyze --media \(mediaID) first")
            }
            let defaults = MediaAnalysis.Limits()
            let limits = MediaAnalysis.Limits(
                minScore: arguments.optionalDouble("minScore") ?? defaults.minScore,
                activityDb: arguments.optionalDouble("activityDb") ?? defaults.activityDb,
                bridgeSeconds: arguments.optionalDouble("bridgeSeconds") ?? defaults.bridgeSeconds)
            var result = record.json(
                limits: limits, samples: arguments.bool("samples"), curve: arguments.bool("curve")).object
            result["media"] = .string(mediaID)
            return .object(result)
        }
        handleAuthored("media.cuts") { document, arguments, _ in
            let mediaID = try arguments.string("media")
            let (root, stored) = try document.storedAnalysis(mediaID)
            guard var record = stored else {
                throw RPCFailure(-32602, "Media \(mediaID) is not analysed: run media analyze --media \(mediaID) first")
            }
            do {
                try record.correct(
                    add: try Self.seconds(arguments.optionalString("add")),
                    remove: try Self.seconds(arguments.optionalString("remove")), clear: arguments.bool("clear"))
            } catch let error as ProjectError {
                throw RPCFailure(-32602, error.localizedDescription)
            }
            try MediaAnalyzer.save(record, projectRoot: root)
            let picture = record.json().object["picture"]?.object ?? [:]
            return .object([
                "media": .string(mediaID), "cuts": picture["cuts"] ?? .array([]),
                "corrections": record.json().object["corrections"] ?? .null,
            ])
        }
    }

    /// `media.list --analysis`: the overview of each media's record, or measured false.
    func mediaAnalysisOverview(_ media: Media) -> JSONValue {
        guard !media.isImage, let stored = try? storedAnalysis(media.id), let record = stored.record else {
            return .object(["measured": .bool(false)])
        }
        return record.overviewJSON
    }
}
