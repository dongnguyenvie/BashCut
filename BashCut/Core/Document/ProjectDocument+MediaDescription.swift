import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// Shot facts the agent (or the user) wrote about source media (P0-A4): `media.describe` stores them on the media
/// as one undoable edit, `media.description` reads them with their coverage of the measured shots, and
/// `media.list --analysis` reports what is described.
extension ProjectDocument {
    func registerMediaDescriptionCommands() {
        handleAuthored("media.describe") { document, arguments, author in
            let mediaID = try arguments.string("media")
            guard let media = document.project.media.first(where: { $0.id == mediaID }) else {
                throw RPCFailure(-32602, "Unknown media \(mediaID)")
            }
            var description: JSONValue?
            if arguments.bool("clear") {
                guard media.fields["description"] != nil else { throw RPCFailure(-32602, "Media \(mediaID) is not described") }
            } else {
                guard let value = arguments["shots"] else { throw RPCFailure(-32602, "Give shots, or clear") }
                let rows = value.object["shots"]?.array ?? value.array
                do {
                    var shots = try MediaDescription.shots(rows, duration: media.durationSeconds)
                    if arguments.bool("merge"), let stored = media.shotDescription { shots = try stored.merging(shots) }
                    description = MediaDescription(
                        shots: shots, describedBy: author.rawValue,
                        describedAt: ISO8601DateFormatter().string(from: Date())
                    ).json
                } catch let error as ProjectError {
                    throw RPCFailure.invalid(error)
                }
            }
            let revision = try document.commit(
                .setMediaDescription(media: mediaID, description: description),
                label: description == nil ? "Clear media description" : "Describe media", author: author,
                baseRevision: arguments.int("baseRev"))
            var result: [String: JSONValue] = ["rev": .integer(revision), "media": .string(mediaID)]
            if let described = document.project.media.first(where: { $0.id == mediaID }) {
                result["coverage"] = document.mediaDescriptionCoverage(described)
            }
            return .object(result)
        }
        handle("media.description") { document, arguments, _ in
            if let mediaID = arguments.optionalString("media") {
                guard let media = document.project.media.first(where: { $0.id == mediaID }) else {
                    throw RPCFailure(-32602, "Unknown media \(mediaID)")
                }
                var result: [String: JSONValue] = [
                    "media": .string(mediaID), "coverage": document.mediaDescriptionCoverage(media),
                ]
                result["description"] = media.shotDescription?.json ?? .null
                return .object(result)
            }
            return document.mediaDescriptionOverview()
        }
    }

    /// Coverage of one media: described false, or the description's shots and share, and against the measured
    /// shots (`media.analyze`) when there are any.
    func mediaDescriptionCoverage(_ media: Media) -> JSONValue {
        guard let description = media.shotDescription else { return .object(["described": .bool(false)]) }
        let measured = media.isImage ? nil : (try? storedAnalysis(media.id))?.record?.shotSpans()
        var coverage = description.coverage(duration: media.durationSeconds, measured: measured).object
        coverage["described"] = .bool(true)
        for (key, value) in description.summaryJSON.object where key != "shots" { coverage[key] = value }
        return .object(coverage)
    }

    /// Every media's coverage, the totals ("38/40 measured shots described") and the media not described yet.
    func mediaDescriptionOverview() -> JSONValue {
        var rows: [JSONValue] = []
        var missing: [JSONValue] = []
        var measured = 0, covered = 0, described = 0
        for media in project.media {
            let coverage = mediaDescriptionCoverage(media).object
            if coverage["described"] == .bool(true) { described += 1 } else { missing.append(.string(media.id)) }
            measured += coverage["measuredShots"]?.int ?? 0
            covered += coverage["coveredShots"]?.int ?? 0
            rows.append(.object(["media": .string(media.id), "path": .string(media.path), "coverage": .object(coverage)]))
        }
        return .object([
            "media": .array(rows), "describedMedia": .integer(described), "totalMedia": .integer(project.media.count),
            "measuredShots": .integer(measured), "coveredShots": .integer(covered), "missing": .array(missing),
            "vocabulary": MediaDescription.vocabularyJSON,
        ])
    }
}
