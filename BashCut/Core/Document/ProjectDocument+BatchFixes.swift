import BashCutAutomation
import BashCutProject
import Foundation

/// Batch-fix actions (P2-C3): find and replace in captions, restyle every caption, swap the music bed. Each is one
/// undoable edit of the whole project, so a pipeline step can run it on every item.
extension ProjectDocument {
    /// Replaces text in every caption; with `dryRun` only lists what would change.
    func replaceInCaptions(
        _ replace: CaptionReplace, dryRun: Bool = false, author: Author = .user, baseRevision: Int? = nil
    ) throws -> JSONValue {
        let (operations, changes) = try project.captionReplaceOperations(replace)
        var revision = project.revision
        if !dryRun, !operations.isEmpty {
            let label = String(localized: "Replace in captions")
            revision = try commit(
                .group(label: label, author: author, ops: operations), label: label, author: author,
                baseRevision: baseRevision)
        }
        return .object([
            "rev": .integer(revision), "replaced": .integer(changes.reduce(0) { $0 + $1.count }),
            "dryRun": .bool(dryRun),
            "items": .array(changes.map { change in
                .object([
                    "id": .string(change.item), "before": .string(change.before), "after": .string(change.after),
                    "count": .integer(change.count), "retimed": .bool(change.retimed),
                ])
            }),
        ])
    }

    /// Restyles every caption: `preset` first, then `style` merged into `textStyle`, then `wordStyle` (`.null`
    /// shows words all at once).
    func styleCaptions(
        preset: LibraryItem?, style: [String: JSONValue]?, wordStyle: JSONValue?, author: Author = .user,
        baseRevision: Int? = nil
    ) throws -> (revision: Int, items: [String]) {
        if let preset, preset.kind != .textPreset {
            throw RPCFailure(-32602, "\(preset.reference) is not a text preset")
        }
        let textPreset = try preset.map { try self.textPreset($0) }
        let operations: [EditOperation]
        do {
            operations = try project.captionStyleOperations(preset: textPreset, style: style, wordStyle: wordStyle)
        } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
        let label = String(localized: "Caption style")
        let revision = try commit(
            .group(label: label, author: author, ops: operations), label: label, author: author,
            baseRevision: baseRevision)
        if let preset { recordLibraryUse(preset) }
        return (revision, project.captionItems.map(\.id))
    }

    /// Replaces the music bed with project media `mediaID` or the library sound `library`.
    func replaceMusic(
        media mediaID: String?, library: LibraryItem?, fromSeconds: Double, loop: Bool, author: Author = .user,
        baseRevision: Int? = nil
    ) async throws -> JSONValue {
        guard (mediaID == nil) != (library == nil) else { throw RPCFailure(-32602, "Give either media or library") }
        let sound: Media
        if let library {
            guard library.kind == .audio else { throw RPCFailure(-32602, "\(library.reference) is not an audio item") }
            sound = try await librarySoundMedia(library, folder: LibraryAudio.projectFolder("music"))
        } else if let mediaID, let media = project.media.first(where: { $0.id == mediaID }) {
            sound = media
        } else {
            throw RPCFailure(-32602, "Unknown media \(mediaID ?? "")")
        }
        let plan: MusicReplacement
        do { plan = try project.musicReplacePlan(sound, fromSeconds: fromSeconds, loop: loop) } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
        let label = String(localized: "Replace music")
        let revision = try commitPlan(plan.planner, label: label, author: author, baseRevision: baseRevision)
        if let library { recordLibraryUse(library) }
        return .object([
            "rev": .integer(revision), "track": .string(plan.trackID), "media": .string(sound.id),
            "removed": .array(plan.removed.map(JSONValue.string)), "items": .array(plan.itemIDs.map(JSONValue.string)),
            "at": .integer(plan.at), "duration": .integer(plan.duration), "looped": .bool(plan.looped),
            "shortened": .bool(plan.shortened),
        ])
    }

    func registerBatchFixCommands() {
        handleAuthored("captions.replace") { document, arguments, author in
            let replace = CaptionReplace(
                find: try arguments.string("find"), replacement: arguments["with"]?.string ?? "",
                matchCase: arguments.bool("matchCase"), wholeWord: arguments.optionalBool("wholeWord") ?? true)
            do {
                return try document.replaceInCaptions(
                    replace, dryRun: arguments.bool("dryRun"), author: author, baseRevision: try arguments.int("baseRev"))
            } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
        }
        handleAuthored("captions.style") { document, arguments, author in
            let preset = try arguments.optionalString("preset").map { try document.libraryCatalog.item($0) }
            let style: [String: JSONValue]?
            switch arguments["style"] {
            case nil, .null?: style = nil
            case .object(let fields)?: style = fields
            default: throw RPCFailure(-32602, "style must be an object of textStyle fields")
            }
            let wordStyle = arguments.optionalString("wordStyle").map { $0 == "none" ? JSONValue.null : .string($0) }
            let result = try document.styleCaptions(
                preset: preset, style: style, wordStyle: wordStyle, author: author,
                baseRevision: try arguments.int("baseRev"))
            return .object(["rev": .integer(result.revision), "items": .array(result.items.map(JSONValue.string))])
        }
        handleAuthored("music.replace") { document, arguments, author in
            let library = try arguments.optionalString("library").map { try document.libraryCatalog.item($0) }
            return try await document.replaceMusic(
                media: arguments.optionalString("media"), library: library,
                fromSeconds: arguments.optionalDouble("from") ?? 0, loop: arguments.optionalBool("loop") ?? true,
                author: author, baseRevision: try arguments.int("baseRev"))
        }
    }
}
