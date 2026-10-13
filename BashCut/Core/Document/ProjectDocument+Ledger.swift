import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutProject
import BashCutStorage
import Foundation

/// The export ledger and post links, history across projects (P3-I2), and outcomes per export (P3-I3).
extension ProjectDocument {
    func registerLedgerCommands() {
        handle("export.history") { document, arguments, _ in
            let root = try document.ledgerRoot()
            let entries = try document.exports.ledger.all(projectRoot: root)
            let full = arguments.bool("full")
            let rows = entries.enumerated().reversed().prefix(arguments.optionalInt("limit") ?? 20).map { index, entry in
                Self.ledgerRow(entry, index: index, root: root, full: full)
            }
            return .object(["count": .integer(entries.count), "exports": .array(Array(rows))])
        }
        handleAuthored("export.link") { document, arguments, _ in
            let root = try document.ledgerRoot()
            let url = try arguments.string("url")
            guard let parsed = URL(string: url), parsed.scheme != nil else { throw RPCFailure(-32602, "url must be a full URL") }
            if let posted = arguments.optionalString("postedAt"), Self.date(posted) == nil {
                throw RPCFailure(-32602, "postedAt must be an ISO 8601 date (2026-10-13) or date-time")
            }
            let link = ExportLink(
                url: url, platform: arguments.optionalString("platform")?.lowercased(),
                postedAt: arguments.optionalString("postedAt"))
            do {
                let entry = try document.exports.ledger.addLink(link, to: arguments.optionalString("export"), projectRoot: root)
                let index = try document.exports.ledger.entry(entry.id ?? entry.path, projectRoot: root).index
                return Self.ledgerRow(entry, index: index, root: root, full: false)
            } catch let error as ProjectError { throw RPCFailure(-32602, error.localizedDescription) }
        }
        handleAuthored("export.reveal-output") { document, arguments, _ in
            .object(["path": .string(try document.revealExport(arguments.optionalString("export")).path), "revealed": .bool(true)])
        }
        handle("project.history") { document, arguments, _ in document.projectHistory(limit: arguments.optionalInt("limit") ?? 10) }
        handleAuthored("outcomes.import") { document, arguments, _ in try document.importOutcomes(arguments) }
        handle("outcomes.map") { document, arguments, _ in
            let root = try document.ledgerRoot()
            let (entry, id) = try document.ledgerExport(arguments.optionalString("export"), root: root)
            guard let record = Self.outcomes(id, root: root) else {
                throw RPCFailure(-32602, "No outcomes imported for export \(id) (outcomes import FILE --export \(id))")
            }
            let snapshot = document.exports.ledger.snapshot(id, projectRoot: root)
            return Outcomes.map(
                record,
                sections: snapshot?.sections.map { Outcomes.Section(label: $0.label, start: $0.start, end: $0.end) } ?? [],
                words: snapshot?.words.map { Outcomes.Word(text: $0.text, start: $0.start) } ?? [],
                duration: entry.duration, top: arguments.optionalInt("top") ?? 3,
                window: arguments.optionalDouble("window") ?? 4)
        }
    }

    /// `export.reveal-output` and the result card's per-file icon: the export `reference` names (ID, ledger index or
    /// path; the latest by default) shown in Finder. Refuses a file that is gone.
    @discardableResult
    func revealExport(_ reference: String?) throws -> URL {
        let root = try ledgerRoot()
        let entry: StoredExportMetrics
        do { entry = try exports.ledger.entry(reference, projectRoot: root).entry } catch let error as ProjectError {
            throw RPCFailure(-32602, error.localizedDescription)
        }
        let url = URL(fileURLWithPath: entry.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RPCFailure(-32602, "\(url.lastPathComponent) is no longer on disk (\(url.path))")
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    private func ledgerRoot() throws -> URL {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Save the project first") }
        return root
    }

    /// The export a command names, with its ledger ID (exports made before the ledger have none).
    private func ledgerExport(_ reference: String?, root: URL) throws -> (StoredExportMetrics, String) {
        do {
            let entry = try exports.ledger.entry(reference, projectRoot: root).entry
            guard let id = entry.id else {
                throw RPCFailure(-32602, "This export was made before the ledger kept snapshots; export again to map outcomes")
            }
            return (entry, id)
        } catch let error as ProjectError { throw RPCFailure(-32602, error.localizedDescription) }
    }

    private func importOutcomes(_ arguments: CommandArguments) throws -> JSONValue {
        let root = try ledgerRoot()
        let (entry, id) = try ledgerExport(arguments.optionalString("export"), root: root)
        let parsed: (curve: [Outcomes.Point], totals: [String: JSONValue])
        do {
            parsed = try Outcomes.parse(
                arguments.string("data"), duration: entry.duration,
                columns: Outcomes.Columns(
                    time: arguments.optionalString("timeColumn"), retention: arguments.optionalString("retentionColumn")))
        } catch let error as ProjectError { throw RPCFailure(-32602, error.localizedDescription) }
        var totals = parsed.totals
        for (key, value) in arguments.values["totals"]?.object ?? [:] where value.double != nil { totals[key] = value }
        let record = Outcomes.Record(
            export: id, platform: arguments.optionalString("platform")?.lowercased(), curve: parsed.curve, totals: totals)
        let url = Self.outcomesURL(id, root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.outcomesEncoder.encode(record).write(to: url, options: .atomic)
        let values = record.curve.compactMap(\.retention)
        return .object([
            "export": .string(id), "path": .string(url.path), "points": .integer(record.curve.count),
            "nullPoints": .integer(record.curve.count - values.count), "unit": .string(record.unit),
            "from": record.curve.first.map { .number($0.t) } ?? .null, "to": record.curve.last.map { .number($0.t) } ?? .null,
            "totals": .object(totals),
        ])
    }

    /// `project.history`: the recent projects' ledgers and what their latest exports share.
    private func projectHistory(limit: Int) -> JSONValue {
        let openRoot = fileURL?.deletingLastPathComponent().standardizedFileURL
        var roots = [openRoot].compactMap { $0 }
        for url in settings.recentProjects {
            let root = url.deletingLastPathComponent().standardizedFileURL
            if !roots.contains(root) { roots.append(root) }
        }
        var rows: [JSONValue] = []
        var fingerprints: [[String: JSONValue]] = []
        for root in roots.prefix(limit) {
            let entries = (try? exports.ledger.all(projectRoot: root)) ?? []
            let isOpen = root == openRoot
            let latest = entries.last
            var fingerprint = entries.last(where: { $0.fingerprint != nil })?.fingerprint?.object
            if fingerprint == nil, isOpen { fingerprint = ProjectFingerprint.json(project).object }
            var row: [String: JSONValue] = [
                "name": .string(isOpen ? project.name : root.lastPathComponent), "path": .string(root.path),
                "open": .bool(isOpen), "exports": .integer(entries.count),
                "links": .array(entries.flatMap { $0.links ?? [] }.map(Self.json)),
                "lastExport": latest.map { entry in
                    .object([
                        "preset": .string(entry.preset), "seconds": .number(entry.duration),
                        "completedAt": .string(ISO8601DateFormatter().string(from: entry.completedAt)),
                    ])
                } ?? .null,
                "fingerprintFrom": .string(fingerprint == nil ? "none" : entries.contains { $0.fingerprint != nil } ? "export" : "timeline"),
            ]
            if let fingerprint {
                row["fingerprint"] = .object(fingerprint)
                fingerprints.append(fingerprint)
            }
            rows.append(.object(row))
        }
        return .object(["projects": .array(rows), "shared": Self.shared(fingerprints)])
    }

    /// How many of the projects used each look, caption preset, title preset, music file and transition kind, and
    /// the hook and cut numbers in project order.
    private static func shared(_ fingerprints: [[String: JSONValue]]) -> JSONValue {
        func counts(_ key: String) -> JSONValue {
            var tally: [String: Int] = [:]
            for fingerprint in fingerprints {
                let names: [String] = key == "transitions"
                    ? fingerprint[key].map { Array($0.object.keys) } ?? [] : fingerprint[key]?.array.compactMap(\.string) ?? []
                for name in Set(names) { tally[name, default: 0] += 1 }
            }
            return .object(tally.mapValues(JSONValue.integer))
        }
        let numbers = { (path: [String]) -> JSONValue in
            .array(fingerprints.map { fingerprint in
                var value: JSONValue? = .object(fingerprint)
                for key in path { value = value?.object[key] }
                return value ?? .null
            })
        }
        return .object([
            "projects": .integer(fingerprints.count),
            "looks": counts("looks"), "captionPresets": counts("captionPresets"), "titlePresets": counts("titlePresets"),
            "music": counts("music"), "transitions": counts("transitions"),
            "averageCutSeconds": numbers(["averageCutSeconds"]), "medianCutSeconds": numbers(["medianCutSeconds"]),
            "firstCutSeconds": numbers(["hook", "firstCutSeconds"]), "firstTextSeconds": numbers(["hook", "firstTextSeconds"]),
            "seconds": numbers(["seconds"]),
        ])
    }

    private static func ledgerRow(_ entry: StoredExportMetrics, index: Int, root: URL, full: Bool) -> JSONValue {
        var row: [String: JSONValue] = [
            "index": .integer(index), "id": entry.id.map(JSONValue.string) ?? .null,
            "rev": entry.rev.map(JSONValue.integer) ?? .null, "preset": .string(entry.preset), "path": .string(entry.path),
            "seconds": .number(entry.duration),
            "completedAt": .string(ISO8601DateFormatter().string(from: entry.completedAt)),
            "links": .array((entry.links ?? []).map(json)),
            "outcomes": .bool(entry.id.map { FileManager.default.fileExists(atPath: outcomesURL($0, root: root).path) } ?? false),
        ]
        if let fingerprint = entry.fingerprint?.object {
            row["hook"] = fingerprint["hook"] ?? .null
            row["sections"] = .integer(fingerprint["sections"]?.array.count ?? 0)
            if full { row["fingerprint"] = .object(fingerprint) }
        }
        return .object(row)
    }

    private static func json(_ link: ExportLink) -> JSONValue {
        .object([
            "url": .string(link.url), "platform": link.platform.map(JSONValue.string) ?? .null,
            "postedAt": link.postedAt.map(JSONValue.string) ?? .null,
        ])
    }

    /// A date or date-time whose first ten characters are an ISO 8601 date.
    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: String(text.prefix(10)))
    }

    private static func outcomesURL(_ id: String, root: URL) -> URL {
        root.appendingPathComponent(".bashcut/outcomes/\(id).json")
    }

    private static func outcomes(_ id: String, root: URL) -> Outcomes.Record? {
        guard let data = try? Data(contentsOf: outcomesURL(id, root: root)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Outcomes.Record.self, from: data)
    }

    private static var outcomesEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
