import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

/// What the footage holds, from one call (P0-A6): `media.inventory` lists each media's capture facts, speech and
/// what is measured, transcribed and described, with totals per folder and for the project; `context.get` says
/// which media are not measured yet and which analysis jobs are running, so a plan does not fill gaps with
/// defaults. Raw facts only.
extension ProjectDocument {
    static let analysisJobMethods: Set<String> = ["media.analyze", "media.transcribe", "review.measure"]

    func registerMediaInventoryCommands() {
        handle("media.inventory") { document, arguments, _ in
            try await document.mediaInventory(grid: arguments.optionalDouble("locationGrid") ?? 0.001)
        }
    }

    /// One media's row; `capture` is nil when the file is missing.
    private struct InventoryRow {
        let media: Media
        let folder: String
        let capture: MediaCapture?
        let measured: Bool
        let transcript: SourceTranscript?
        let coverage: [String: JSONValue]

        var described: Bool { coverage["described"] == .bool(true) }
        var speechSeconds: Double { transcript?.speechSeconds ?? 0 }
    }

    func mediaInventory(grid: Double) async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        var rows: [InventoryRow] = []
        for media in project.media {
            var capture: MediaCapture?
            if let url = try? analysisSource(media.id).url {
                capture = try? await MediaCapture.facts(for: url, isImage: media.isImage, projectRoot: root)
            }
            let measured = !media.isImage && (try? storedAnalysis(media.id))?.record != nil
            let transcript = media.isImage ? nil : try? await storedTranscript(media.id)
            let folder = (media.path as NSString).deletingLastPathComponent
            rows.append(InventoryRow(
                media: media, folder: folder.isEmpty ? "." : folder, capture: capture, measured: measured,
                transcript: transcript, coverage: mediaDescriptionCoverage(media).object))
        }
        let folders = Dictionary(grouping: rows, by: \.folder).sorted { $0.key < $1.key }.map { folder, members in
            var totals = Self.totals(members, grid: grid)
            totals["folder"] = .string(folder)
            return JSONValue.object(totals)
        }
        return .object([
            "media": .array(rows.map(Self.inventoryJSON)), "folders": .array(folders),
            "totals": .object(Self.totals(rows, grid: grid)), "locationGrid": .number(grid),
        ])
    }

    private static func inventoryJSON(_ row: InventoryRow) -> JSONValue {
        let media = row.media
        let width = row.capture?.width ?? media.width, height = row.capture?.height ?? media.height
        var json: [String: JSONValue] = [
            "id": .string(media.id), "path": .string(media.path), "folder": .string(row.folder),
            "kind": .string(media.kind.isEmpty ? "video" : media.kind),
            "seconds": .number((media.durationSeconds * 1_000).rounded() / 1_000),
            "hasAudio": media.hasAudio.map(JSONValue.bool) ?? .null, "measured": .bool(row.measured),
            "fileMissing": .bool(row.capture == nil),
        ]
        if let width, let height {
            json["width"] = .integer(width)
            json["height"] = .integer(height)
            json["orientation"] = .string(width == height ? "square" : width > height ? "landscape" : "portrait")
        }
        if let capture = row.capture {
            json["capturedAt"] = capture.capturedAt.map(JSONValue.string) ?? .null
            json["location"] = capture.location.map(locationJSON) ?? .null
            let device = [capture.make, capture.model].compactMap { $0 }.joined(separator: " ")
            json["device"] = device.isEmpty ? .null : .string(device)
            if let software = capture.software { json["software"] = .string(software) }
        }
        json["transcript"] = row.transcript.map { transcript in
            .object([
                "language": .string(transcript.language), "speechSeconds": .number(rounded(transcript.speechSeconds)),
                "words": .integer(transcript.words.count),
            ])
        } ?? .null
        json["description"] = .object(row.coverage)
        return .object(json)
    }

    private static func locationJSON(_ location: MediaCapture.Location) -> JSONValue {
        var json: [String: JSONValue] = ["latitude": .number(location.latitude), "longitude": .number(location.longitude)]
        if let altitude = location.altitude { json["altitude"] = .number(altitude) }
        return .object(json)
    }

    private static func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    /// Counts and sums over `rows`: seconds, speech, languages, what is measured, transcribed and described (with
    /// the IDs that are not), the capture time span and the places, grouped on a `grid`-degree grid.
    private static func totals(_ rows: [InventoryRow], grid: Double) -> [String: JSONValue] {
        let times = rows.compactMap { $0.capture?.capturedAt }.sorted()
        let languages = Set(rows.compactMap { $0.transcript?.language }).sorted()
        let ids = { (rows: [InventoryRow]) in JSONValue.array(rows.map { .string($0.media.id) }) }
        let pictures = rows.filter { $0.media.kind != "audio" }
        let sounding = rows.filter { !$0.media.isImage && $0.media.hasAudio != false }
        var places: [String: (latitude: Double, longitude: Double, count: Int)] = [:]
        for location in rows.compactMap({ $0.capture?.location }) {
            let cell = grid > 0
                ? "\(Int((location.latitude / grid).rounded())),\(Int((location.longitude / grid).rounded()))" : "all"
            let current = places[cell] ?? (0, 0, 0)
            places[cell] = (current.latitude + location.latitude, current.longitude + location.longitude, current.count + 1)
        }
        let locations = places.values.sorted { $0.count > $1.count }.map { place in
            JSONValue.object([
                "latitude": .number(place.latitude / Double(place.count)),
                "longitude": .number(place.longitude / Double(place.count)), "media": .integer(place.count),
            ])
        }
        return [
            "media": .integer(rows.count),
            "seconds": .number(rounded(rows.reduce(0) { $0 + $1.media.durationSeconds })),
            "speechSeconds": .number(rounded(rows.reduce(0) { $0 + $1.speechSeconds })),
            "languages": .array(languages.map(JSONValue.string)),
            "measured": .integer(rows.filter(\.measured).count),
            "transcribed": .integer(rows.filter { $0.transcript != nil }.count),
            "described": .integer(pictures.filter(\.described).count),
            "notMeasured": ids(rows.filter { !$0.measured && !$0.media.isImage }),
            "notTranscribed": ids(sounding.filter { $0.transcript == nil }),
            "notDescribed": ids(pictures.filter { !$0.described }),
            "capturedFrom": times.first.map(JSONValue.string) ?? .null,
            "capturedTo": times.last.map(JSONValue.string) ?? .null,
            "locations": .array(locations),
            "withoutLocation": .integer(rows.filter { $0.capture?.location == nil }.count),
        ]
    }

    /// For `context.get`: running analysis jobs and the media without a record, transcript or description.
    func analysisReadiness() async -> JSONValue {
        var unmeasured: [JSONValue] = [], untranscribed: [JSONValue] = [], undescribed: [JSONValue] = []
        for media in project.media {
            if media.kind != "audio", media.fields["description"] == nil { undescribed.append(.string(media.id)) }
            guard !media.isImage else { continue }
            if (try? storedAnalysis(media.id))?.record == nil { unmeasured.append(.string(media.id)) }
            if media.hasAudio != false, (try? await storedTranscript(media.id)) == nil {
                untranscribed.append(.string(media.id))
            }
        }
        let running = jobs.jobs.filter { $0.isActive && Self.analysisJobMethods.contains($0.method) }.map { job in
            JSONValue.object([
                "id": .string(job.id), "method": .string(job.method), "state": .string(job.state.rawValue),
                "progress": job.progress.map(JSONValue.number) ?? .null,
            ])
        }
        return .object([
            "jobs": .array(running), "media": .integer(project.media.count), "unmeasured": .array(unmeasured),
            "untranscribed": .array(untranscribed), "undescribed": .array(undescribed),
        ])
    }
}
