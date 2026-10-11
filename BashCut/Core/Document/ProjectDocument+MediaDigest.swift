import BashCutAutomation
import BashCutProject
import Foundation

/// `media.digest`: each media's measured shots, description and transcript as one short read, also kept in
/// `analysis/digest.json` next to the project for sub-agents and later sessions.
extension ProjectDocument {
    func registerMediaDigestCommands() {
        handle("media.digest") { document, arguments, _ in try await document.mediaDigest(arguments) }
    }

    func mediaDigest(_ arguments: CommandArguments) async throws -> JSONValue {
        var selected = project.media.filter { !$0.isImage }
        if let id = arguments.optionalString("media") {
            selected = selected.filter { $0.id == id }
            guard !selected.isEmpty else { throw RPCFailure(-32602, "Unknown media \(id), or a still image") }
        }
        var digests: [MediaDigest] = []
        for media in selected {
            let record = (try? storedAnalysis(media.id))?.record
            let transcript = try? await storedTranscript(media.id)
            let size = media.width.flatMap { width in media.height.map { "\(width)x\($0)" } }
            let digest = MediaDigest(
                media: media.id, name: URL(fileURLWithPath: media.path).lastPathComponent,
                seconds: record?.tech.seconds ?? media.durationSeconds, size: size,
                cuts: record?.shotSpans()?.dropFirst().map(\.start), shots: media.shotDescription?.shots ?? [],
                phrases: transcript?.phrases ?? [], speechSeconds: transcript?.speechSeconds)
            digests.append(digest.range(from: arguments.optionalDouble("from"), to: arguments.optionalDouble("to")))
        }
        var result: [String: JSONValue] = [:]
        if let root = fileURL?.deletingLastPathComponent(), arguments.optionalString("media") == nil,
            arguments.optionalDouble("from") == nil, arguments.optionalDouble("to") == nil
        {
            let folder = root.appendingPathComponent("analysis", isDirectory: true)
            let file = folder.appendingPathComponent("digest.json")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(JSONValue.object(["media": .array(digests.map(\.json))])).write(to: file, options: .atomic)
            result["path"] = .string(file.path)
        }
        if arguments.optionalString("as") == "json" {
            result["media"] = .array(digests.map(\.json))
        } else {
            result["text"] = .string(digests.map(\.text).joined(separator: "\n\n"))
        }
        return .object(result)
    }
}
