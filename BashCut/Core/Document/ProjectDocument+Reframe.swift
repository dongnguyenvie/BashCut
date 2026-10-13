import BashCutAutomation
import BashCutEngine
import BashCutPlugins
import BashCutProject
import Foundation

/// Face boxes kept per source file (`media.subjects` stores what it measures) and `clip.reframe` (P3-J1), which crops
/// a clip to its subject from them; `review.layout` reads them for text over faces.
extension ProjectDocument {
    static func subjectsKey(_ url: URL) throws -> String {
        try ProjectCache.contentKey(for: url, namespace: "media-subjects-v1")
    }

    /// Adds a `media.subjects` result to what is stored for the file; returns the stored whole.
    @discardableResult
    func storeSubjects(_ generated: GeneratedVision, url: URL, root: URL) throws -> MediaSubjects {
        let key = try Self.subjectsKey(url)
        let measured = MediaSubjects(json: .object([
            "step": .number(generated.step), "frames": .array(generated.frames),
            "provider": .object(generated.provenance.json),
        ]))
        let stored = ProjectCache.record(JSONValue.self, .subjects, key: key, projectRoot: root)
            .flatMap { $0.object["key"]?.string == key ? MediaSubjects(json: $0) : nil }
        let merged = stored?.merging(measured) ?? measured
        var record = merged.json.object
        record["key"] = .string(key)
        record["version"] = .integer(1)
        try ProjectCache.store(JSONValue.object(record), .subjects, key: key, projectRoot: root)
        return merged
    }

    /// The boxes stored for `mediaID`'s file as it is now, or nil.
    func storedSubjects(_ mediaID: String) -> MediaSubjects? {
        guard let source = try? analysisSource(mediaID), let key = try? Self.subjectsKey(source.url),
            let record = ProjectCache.record(JSONValue.self, .subjects, key: key, projectRoot: source.root),
            record.object["key"]?.string == key
        else { return nil }
        return MediaSubjects(json: record)
    }

    /// Stored boxes of every picture media on a visible video layer, for `review.layout`.
    func reviewSubjects() -> [String: MediaSubjects] {
        let used = Set(project.tracks.filter { $0.kind == TrackKind.video && !$0.isHidden }.flatMap(\.items)
            .compactMap(\.mediaID))
        var result: [String: MediaSubjects] = [:]
        for id in used { result[id] = storedSubjects(id) }
        return result
    }

    func registerReframeCommands() {
        handleAuthored("clip.reframe") { document, arguments, author in
            try await document.startReframe(arguments, author: author)
        }
    }

    static func reframeOptions(_ arguments: CommandArguments) throws -> SubjectReframe.Options {
        var options = SubjectReframe.Options()
        if let mode = arguments.optionalString("mode").flatMap(SubjectReframe.Mode.init(rawValue:)) { options.mode = mode }
        if let subject = arguments.optionalString("subject").flatMap(SubjectReframe.Subject.init(rawValue:)) {
            options.subject = subject
        }
        if let fallback = arguments.optionalString("fallback").flatMap(SubjectReframe.Fallback.init(rawValue:)) {
            options.fallback = fallback
        }
        let numbers: [(String, WritableKeyPath<SubjectReframe.Options, Double>)] = [
            ("minConfidence", \.minConfidence), ("zoom", \.zoom),
            ("gate", \.gate), ("minSubjectShare", \.minSubjectShare), ("drift", \.drift),
            ("minHold", \.minHoldSeconds), ("smooth", \.smoothSeconds),
        ]
        for (name, path) in numbers { if let value = arguments.optionalDouble(name) { options[keyPath: path] = value } }
        if let anchor = arguments.optionalString("anchor") {
            let parts = anchor.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, parts.allSatisfy({ (0...1).contains($0) }) else {
                throw RPCFailure(-32602, "anchor must be x,y with each share in 0…1")
            }
            (options.anchorX, options.anchorY) = (parts[0], parts[1])
        }
        return options
    }

    func startReframe(_ arguments: CommandArguments, author: Author) async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        let base = try arguments.int("baseRev")
        guard let id = arguments.optionalString("item") ?? selectedID,
            let track = project.tracks.first(where: { $0.items.contains { $0.id == id } }), track.kind == TrackKind.video,
            let item = track.items.first(where: { $0.id == id }), let mediaID = item.mediaID,
            let media = project.media.first(where: { $0.id == mediaID })
        else { throw RPCFailure(-32602, "Give a video clip or image to reframe (or select one)") }
        guard media.width != nil, media.height != nil else {
            throw RPCFailure(-32602, "The size of media \(mediaID) is unknown")
        }
        let options = try Self.reframeOptions(arguments)
        let step = arguments.optionalDouble("step") ?? 0.5
        let provider = arguments.optionalString("provider")
        let remeasure = arguments.bool("measure")
        let url = try analysisSource(mediaID).url
        let range = SubjectReframe.sourceRange(item, media: media, project: project)
        return try await startCapabilityJob("clip.reframe", author: author, arguments: arguments) { document in
            var subjects = remeasure ? nil : document.storedSubjects(mediaID)
            let tolerance = max(step, subjects?.step ?? step)
            let covered = subjects.map { stored in
                let inside = stored.samples(from: range.lowerBound - tolerance, to: range.upperBound + tolerance)
                guard let first = inside.first, let last = inside.last else { return false }
                return media.isImage || (first.seconds <= range.lowerBound + tolerance && last.seconds >= range.upperBound - tolerance)
            } ?? false
            var measured = false
            if !covered {
                let sampling = VisionSampling(
                    mediaURL: url, step: step, fromSeconds: media.isImage ? nil : max(0, range.lowerBound - step / 2),
                    toSeconds: media.isImage ? nil : range.upperBound + step / 2)
                let generated = try await document.plugins.running(FacesCapability.capability) {
                    try await document.plugins.service.detectSubjects(
                        sampling, preferredProvider: provider ?? document.project.preferredProvider(for: FacesCapability.capability),
                        projectRoot: root)
                }
                subjects = try document.storeSubjects(generated, url: url, root: root)
                measured = true
            }
            guard let current = document.project.tracks.flatMap(\.items).first(where: { $0.id == id }) else {
                throw RPCFailure(-32602, "Item \(id) is gone")
            }
            let plan: SubjectReframe.Plan
            do {
                plan = try SubjectReframe.plan(
                    current, media: media, project: document.project, subjects: subjects ?? MediaSubjects(samples: [], step: step),
                    options: options)
            } catch let refused as SubjectReframe.Refused {
                throw RPCFailure(-32602, refused.reason + " (fallback refuse: nothing changed)",
                                 data: .object(["coverage": refused.coverage.json, "measured": .bool(measured)]))
            }
            let revision = try document.commit(
                .setProperties(item: id, patch: plan.patch), label: plan.applied == "fit" ? "Reframe (fit)" : "Reframe",
                author: author, baseRevision: base)
            var result = plan.json.object
            result["rev"] = .integer(revision)
            result["item"] = .string(id)
            result["measured"] = .bool(measured)
            let rows = plan.previewFrames.map { (frame: current.at + $0, item: Optional(id)) }
            result["preview"] = (try? await document.frameGrid(rows, mode: "source", width: 390, sourceItem: id)) ?? .null
            return .object(result)
        }
    }
}
