import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation

/// A measured record per source media (P0-A1): `media.analyze` measures, `media.analysis` reads with the agent's
/// limits, `media.cuts` corrects the cut list, `media.speech-map` calibrates sound spans (P0-A3), and
/// `media.list --analysis` shows what is measured.
extension ProjectDocument {
    /// The project folder and the original file of `mediaID`.
    func analysisSource(_ mediaID: String) throws -> (root: URL, media: Media, url: URL) {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        guard let media = project.media.first(where: { $0.id == mediaID }) else {
            throw RPCFailure(-32602, "Unknown media \(mediaID)")
        }
        guard let url = Self.sourceURL(media, root: root, workspace: settings.workspace) else {
            throw RPCFailure(-32602, "The file of media \(mediaID) is missing")
        }
        return (root, media, url)
    }

    /// The file of `media` when it is there.
    nonisolated static func sourceURL(_ media: Media, root: URL, workspace: URL?) -> URL? {
        guard let url = try? MediaPathResolver.resolve(media.path, projectRoot: root, workspaceRoot: workspace),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    /// The stored record of `mediaID` for its file as it is now, or nil when it was not measured (or changed since).
    func storedAnalysis(_ mediaID: String) throws -> (root: URL, record: MediaAnalysis?) {
        let source = try analysisSource(mediaID)
        let key = try MediaAnalyzer.key(for: source.url)
        return (source.root, MediaAnalyzer.load(key: key, projectRoot: source.root))
    }

    /// Measures the listed media (one ID or a comma list; every video and audio media when nil) one after another, reusing stored records
    /// unless `force`. Images are skipped. Media still being converted are measured once their conversion lands, so
    /// the agent can ask right after import and work from the transcript meanwhile.
    func startMediaAnalyze(mediaID: String?, force: Bool, rate: Double?, author: Author) throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        if let running = jobs.jobs.first(where: { $0.method == "media.analyze" && $0.isActive }) {
            return .object(["job": .string(running.id), "state": .string("running")])
        }
        // One ID or a comma list (B8), like jobs wait takes.
        let ids = mediaID?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let selected = try ids.map { try $0.map { try analysisSource($0).media } } ?? project.media.filter { !$0.isImage }
        let workspace = settings.workspace
        let id = jobs.start("media.analyze", author: author, work: { [weak self] reporter in
            while let self, let converting = selected.lazy.compactMap({ self.conversionJob(of: $0) }).first {
                reporter.detail("waiting for conversion \(converting)")
                try await Task.sleep(for: .milliseconds(500))
            }
            // A conversion points the media at its converted copy: measure the media as they are now.
            let current = selected.map { media in self?.project.media.first { $0.id == media.id } ?? media }
            var results: [JSONValue] = []
            for (index, media) in current.enumerated() {
                try Task.checkCancellation()
                let share = 1 / Double(max(1, current.count))
                reporter.progress(Double(index) * share, detail: media.id)
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
                    pictureURL: ProxyMediaSource.proxyURL(for: media, root: root), samplesPerSecond: rate ?? 4,
                    progress: reporter.progressHandler(range: Double(index) * share...Double(index + 1) * share))
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
        handle("media.speech-map") { document, arguments, _ in
            let mediaID = try arguments.string("media")
            guard let sound = try document.storedAnalysis(mediaID).record?.sound else {
                throw RPCFailure(
                    -32602, "Media \(mediaID) has no measured sound: run media analyze --media \(mediaID) first")
            }
            let defaults = SpeechMap.Parameters()
            let parameters = SpeechMap.Parameters(
                thresholdDb: arguments.optionalDouble("thresholdDb"),
                bridgeSeconds: arguments.optionalDouble("bridgeSeconds") ?? defaults.bridgeSeconds,
                minSpeechSeconds: arguments.optionalDouble("minSpeechSeconds") ?? defaults.minSpeechSeconds,
                minSeparationDb: arguments.optionalDouble("minSeparationDb") ?? defaults.minSeparationDb)
            // The words as the recognizer timed them: the map is what other readers' word times are kept out of.
            let words = try await document.rawTranscript(mediaID)?.words
            var result = SpeechMap.json(sound: sound, words: words, parameters: parameters).object
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
                throw RPCFailure.invalid(error)
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
