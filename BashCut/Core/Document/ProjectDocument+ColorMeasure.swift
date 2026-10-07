import BashCutAutomation
import BashCutEngine
import BashCutProject
import CoreGraphics
import Foundation

/// `color.measure` (P0-B8): the colour of each clip as numbers, from its source frames, from the edit as graded, or
/// both with what the grade changed, and each clip's distance from the median clip.
extension ProjectDocument {
    func registerColorMeasureCommands() {
        handle("color.measure") { document, arguments, _ in try await document.colorMeasure(arguments) }
    }

    /// The given video items, or the clips on Main.
    private func colorItems(_ arguments: CommandArguments) throws -> [Item] {
        let main = project.tracks.first { $0.role == TrackRole.main }?.items.sorted { $0.at < $1.at } ?? []
        let all = project.tracks.filter { $0.kind == TrackKind.video }.flatMap(\.items)
        let ids = arguments.optionalString("items").map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        let items = try ids.map { list in
            try list.map { id in
                guard let item = all.first(where: { $0.id == id }) else { throw RPCFailure(-32602, "Unknown item \(id)") }
                return item
            }
        } ?? main.filter { $0.mediaID != nil }
        guard !items.isEmpty else { throw RPCFailure(-32602, "No video clips to measure") }
        return items
    }

    /// The pictures one measurement reads: the edit as composed and, for a comparison, without colour.
    private struct ColorPictures {
        var composed: [Int: CGImage] = [:]
        var ungraded: [Int: CGImage] = [:]
        let graded: Bool
        let compare: Bool
    }

    func colorMeasure(_ arguments: CommandArguments) async throws -> JSONValue {
        let items = try colorItems(arguments)
        let samples = arguments.optionalInt("samples") ?? 3
        let compare = arguments.optionalString("compare") == "source"
        let graded = arguments.bool("graded") || compare
        let frames = items.map { item in
            (0..<samples).map { item.at + Int((Double(item.duration) * (Double($0) + 0.5) / Double(samples)).rounded(.down)) }
        }
        let flat = Array(Set(frames.joined())).sorted()
        var pictures = ColorPictures(graded: graded, compare: compare)
        if graded { pictures.composed = try await timelineImages(flat, maximumSide: 640) }
        if compare {
            guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
            var bare = project.withoutColorEffects()
            bare.revision = 0
            let snapshot = try await engine.build(bare, root: root, workspace: settings.workspace, purpose: .preview)
            pictures.ungraded = try await images(of: snapshot, frames: flat, maximumSide: 640)
        }
        var rows: [JSONValue] = [], measured: [(id: String, stats: ColorMeasure.Stats)] = []
        for (item, itemFrames) in zip(items, frames) {
            let (row, stats) = try await colorRow(item, frames: itemFrames, pictures: pictures)
            rows.append(row)
            if let stats { measured.append((item.id, stats)) }
        }
        var result: [String: JSONValue] = [
            "revision": .integer(project.revision), "measured": .string(graded ? "graded" : "source"), "items": .array(rows),
        ]
        if arguments.optionalString("by") == "clip", let median = ColorMeasure.median(measured.map(\.stats)) {
            result["median"] = median.json
            result["byClip"] = .array(measured.map { entry in
                var change = ColorMeasure.compare(source: median, graded: entry.stats, deltaE: nil).object
                change["id"] = .string(entry.id)
                return .object(change)
            })
        }
        return .object(result)
    }

    /// One clip's row and the stats `by clip` compares (graded when measured, else source).
    private func colorRow(
        _ item: Item, frames: [Int], pictures: ColorPictures
    ) async throws -> (JSONValue, ColorMeasure.Stats?) {
        var row: [String: JSONValue] = [
            "id": .string(item.id), "media": item.mediaID.map(JSONValue.string) ?? .null,
            "frames": .array(frames.map(JSONValue.integer)),
        ]
        var compared: ColorMeasure.Stats?
        let ungraded = ColorMeasure.median(frames.compactMap { pictures.ungraded[$0] }.map(ColorMeasure.stats))
        if pictures.compare {
            row["ungraded"] = ungraded?.json ?? .null
        } else if !pictures.graded {
            compared = ColorMeasure.median(try await sourcePictures(item, frames: frames).map(ColorMeasure.stats))
            row["source"] = compared?.json ?? .null
        }
        if pictures.graded, let stats = ColorMeasure.median(frames.compactMap { pictures.composed[$0] }.map(ColorMeasure.stats)) {
            row["graded"] = stats.json
            compared = stats
            if let before = ungraded {
                let pairs = frames.compactMap { frame in
                    pictures.composed[frame].flatMap { after in pictures.ungraded[frame].map { (after, $0) } }
                }
                let deltaE = pairs.isEmpty ? nil : pairs.map { ColorMeasure.deltaE($0.0, $0.1) }.reduce(0, +) / Double(pairs.count)
                row["change"] = ColorMeasure.compare(source: before, graded: stats, deltaE: deltaE)
            }
        }
        return (.object(row), compared)
    }

    /// The source frames an item plays at `frames` (no reframe, no grade).
    private func sourcePictures(_ item: Item, frames: [Int]) async throws -> [CGImage] {
        guard let mediaID = item.mediaID, let media = project.media.first(where: { $0.id == mediaID }),
            let url = try? analysisSource(mediaID).url
        else { return [] }
        let indexes = frames.map { frame in
            let seconds = Double(item.sourceIn) / media.fps.value + item.sourceSeconds(afterFrames: frame - item.at, fps: project.fps)
            return min(max(0, media.frames - 1), Int((seconds * media.fps.value).rounded(.down)))
        }
        let images = try await MediaStills.images(
            url: url, isImage: media.isImage, fps: media.fps, frames: indexes, maximumSide: 640)
        return indexes.compactMap { images[$0] }
    }
}
