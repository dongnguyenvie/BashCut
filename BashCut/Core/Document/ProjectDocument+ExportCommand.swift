import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation

/// `export.start`: one approval for one export (`preset`) or several (`presets`, #593), each queued as its own job.
extension ProjectDocument {
    /// One output of an `export.start` request: its preset, file name and the earlier files `overwrite` replaces.
    private struct ExportTarget {
        let preset: ExportPreset
        let name: String
        let asked: String
        let replaced: [URL]
    }

    func startExportCommand(_ arguments: CommandArguments, author: Author) async throws -> JSONValue {
        let presets = try Self.exportPresets(arguments)
        let (asked, directory) = try exportDestination(arguments)
        guard project.duration > 0 else { throw RPCFailure(-32602, "The timeline is empty") }
        for preset in presets { try checkExportGuards(preset: preset, author: author) }
        let includeSubRip = arguments.bool("includeSRT")
        let normalizeAudio = arguments.bool("normalizeAudio")
        let bitRate = arguments.optionalDouble("bitrate").map { Int($0 * 1_000_000) }
        let without = try Self.exportWithoutRoles(arguments.optionalString("without"))
        let targets = presets.map { preset in
            let wanted = ExportRequest.outputName(asked, preset: preset, among: presets)
            let (name, replaced) = exportName(
                wanted, preset: preset, directory: directory, includeSubRip: includeSubRip,
                overwrite: arguments.bool("overwrite"))
            return ExportTarget(preset: preset, name: name, asked: wanted, replaced: replaced)
        }
        let outputs = targets.map {
            directory.appendingPathComponent($0.name).appendingPathExtension($0.preset.fileExtension)
        }
        // The report's speech coverage reads the clips' stored transcripts (#507-36).
        await loadReviewTranscripts()
        // Filled when the exports start at once (auto-approved), so the caller can `jobs wait --done` on them.
        let started = StartedJobs()
        let approval = try queuePrivilegedApproval(
            method: "export.start", author: author,
            arguments: [
                "captions": includeSubRip ? "include .srt" : "burned in only",
                "normalization": normalizeAudio ? "two-pass LUFS" : "off",
                (outputs.count > 1 ? "outputs" : "output"): outputs.map(\.path).joined(separator: "\n"),
                (presets.count > 1 ? "presets" : "preset"): presets.map(\.title).joined(separator: ", "),
                "bitrate": bitRate.map { "\(Double($0) / 1_000_000) Mbps" } ?? "preset default",
                "sound": without.isEmpty ? "full mix" : "without " + without.sorted().joined(separator: ", "),
            ]
        ) { [weak self] in
            guard let self else { throw RPCFailure(-32000, "Editor closed") }
            try Self.trash(targets.flatMap(\.replaced))
            for target in targets {
                started.ids.append(try startExportAuthorized(
                    name: target.name, preset: target.preset, directory: directory, includeSubRip: includeSubRip,
                    normalizeAudio: normalizeAudio, author: author, videoBitRate: bitRate, withoutRoles: without))
            }
        }
        if !approval.autoApproved {
            message = String(localized: "Waiting for approval: export.start")
        }
        var json = approval.json(output: outputs[0]).object
        json["job"] = started.ids.first.map(JSONValue.string)
        json["renamedFrom"] = targets[0].name == targets[0].asked ? nil : .string(targets[0].asked)
        let replaced = targets.flatMap(\.replaced)
        json["replaced"] = replaced.isEmpty ? nil : .array(replaced.map { .string($0.path) })
        if targets.count > 1 {
            json["exports"] = .array(targets.enumerated().map { index, target in
                var row: [String: JSONValue] = [
                    "preset": .string(target.preset.argument), "output": .string(outputs[index].path),
                ]
                row["job"] = index < started.ids.count ? .string(started.ids[index]) : nil
                row["renamedFrom"] = target.name == target.asked ? nil : .string(target.asked)
                return .object(row)
            })
        }
        // The queue runs exports in order, so the last one landing means every one has.
        if let job = started.ids.last, arguments.bool("wait") {
            json.merge(try await waitForExport(job, save: arguments.bool("save"))) { $1 }
        }
        return .object(json)
    }

    /// `preset`, or the comma-separated `presets` in the given order without repeats; exactly one of them.
    static func exportPresets(_ arguments: CommandArguments) throws -> [ExportPreset] {
        let single = arguments.optionalString("preset")
        let list = arguments.optionalString("presets")
        guard (single == nil) != (list == nil) else {
            throw RPCFailure(-32602, "Give preset (one output) or presets (several, comma separated), not both")
        }
        var presets: [ExportPreset] = []
        for name in (list ?? single ?? "").split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard let preset = ExportPreset(argument: name) else {
                throw RPCFailure(-32602, "Unknown export preset \(name): use "
                    + CommandCatalog.exportPresets.joined(separator: ", "))
            }
            if !presets.contains(preset) { presets.append(preset) }
        }
        guard !presets.isEmpty else { throw RPCFailure(-32602, "Unknown export preset") }
        return presets
    }

    /// Resolves an export name and optional directory against the saved project's folder.
    func exportDestination(_ arguments: CommandArguments) throws -> (name: String, directory: URL) {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw RPCFailure(-32602, "Save the project before exporting")
        }
        let name = try arguments.string("name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.contains("/"), !name.contains(":"), name.count <= 180 else {
            throw RPCFailure(-32602, "name must be 1–180 characters without slashes or colons")
        }
        let directory = arguments.optionalString("directory").map {
            URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL
        } ?? root.appendingPathComponent("render", isDirectory: true)
        return (name, directory)
    }

    /// `export start --wait`: the finished job (or `timedOut`), and with `save` the project saved once it landed.
    private func waitForExport(_ job: String, save: Bool) async throws -> [String: JSONValue] {
        let waited = try await waitForJobDone(job, seconds: 100).object
        var result: [String: JSONValue] = ["finished": waited["job"] ?? .null, "timedOut": waited["timedOut"] ?? .bool(false)]
        if save, waited["timedOut"] == .bool(false) {
            if dirty { try await saveNow() }
            result["saved"] = .bool(true)
        }
        return result
    }

    /// The name an export gets (#507-23): a name taken by an earlier export gets the next free suffix, or with
    /// `overwrite` keeps it and returns the old files to replace; a queued export's name is never shared.
    private func exportName(
        _ asked: String, preset: ExportPreset, directory: URL, includeSubRip: Bool, overwrite: Bool
    ) -> (name: String, replaced: [URL]) {
        let name = ExportRequest.availableName(
            asked, preset: preset, directory: directory, includeSubRip: includeSubRip,
            reserved: exports.queue.reservedOutputs, ignoringFiles: overwrite)
        guard overwrite, name == asked else { return (name, []) }
        return (name, ExportRequest.existingOutputs(asked, preset: preset, directory: directory))
    }

    /// Audio roles an export leaves out (`without`: music, sfx, voiceover or dialogue, comma separated).
    static func exportWithoutRoles(_ list: String?) throws -> Set<String> {
        guard let list else { return [] }
        let allowed: Set<String> = [TrackRole.music, TrackRole.sfx, TrackRole.voiceover, TrackRole.dialogue]
        return try Set(list.split(separator: ",").map { name in
            let role = name.trimmingCharacters(in: .whitespaces)
            guard allowed.contains(role) else {
                throw RPCFailure(-32602, "Unknown sound role \(role): use \(allowed.sorted().joined(separator: ", "))")
            }
            return role
        })
    }

    /// Moves an earlier export's files to the Trash before it is written again.
    private static func trash(_ files: [URL]) throws {
        for url in files { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }
}

/// The job IDs a privileged `export.start` started, in preset order, when it ran at once.
@MainActor
private final class StartedJobs {
    var ids: [String] = []
}
