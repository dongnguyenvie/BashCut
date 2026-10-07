@preconcurrency import AVFoundation
import BashCutAutomation
import BashCutEngine
import BashCutProject
import CryptoKit
import Foundation

/// The composed timeline as pictures, without exporting: `review.window` (P0-B3) shows what happens across a cut,
/// frame by frame with the sound level and the words, and `timeline.sheet` (P0-B4) lays the edit out on contact
/// sheets with an index of what each cell shows, optionally once per output with its covered zones.
extension ProjectDocument {
    func registerTimelineStillsCommands() {
        handle("review.window") { document, arguments, _ in try await document.reviewWindow(arguments) }
        handle("timeline.sheet") { document, arguments, _ in try await document.timelineSheet(arguments) }
        handle("ui.frames") { document, arguments, _ in try await document.compareFrames(arguments) }
        handle("review.layout") { document, arguments, _ in
            let frame = arguments.optionalInt("frame")
            let words = await document.syncWords()
            var result = ReviewLayout.json(
                document.project, context: document.reviewContext(), frame: frame,
                words: words.source == "none" ? nil : words.words
            ).object
            if arguments.bool("contrast"), case .array(let items)? = result["items"] {
                result["items"] = .array(try await document.measureContrast(items, frame: frame))
            }
            return .object(result)
        }
    }

    /// Each text row with `contrast` measured on the composed frame (at `frame`, or the item's middle) against the
    /// same frame with every text layer hidden.
    func measureContrast(_ rows: [JSONValue], frame: Int?) async throws -> [JSONValue] {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        var bare = project
        for index in bare.tracks.indices where bare.tracks[index].kind == TrackKind.text {
            bare.tracks[index]["hidden"] = .bool(true)
        }
        bare.revision = 0
        let textless = try await engine.build(bare, root: root, workspace: settings.workspace, purpose: .preview)
        let side = 720
        let frames = rows.map { row -> Int in
            frame ?? ((row.object["at"]?.int ?? 0) + (row.object["end"]?.int ?? 0)) / 2
        }
        let with = try await timelineImages(frames, maximumSide: side)
        let without = try await images(of: textless, frames: frames, maximumSide: side)
        let width = Double(project.width), height = Double(project.height)
        return zip(rows, frames).map { row, at in
            var fields = row.object
            let bounds = fields["bounds"]?.object ?? [:]
            let rect = CGRect(
                x: (bounds["x"]?.double ?? 0) / width, y: (bounds["y"]?.double ?? 0) / height,
                width: (bounds["width"]?.double ?? 0) / width, height: (bounds["height"]?.double ?? 0) / height)
            if let first = with[at], let second = without[at],
                let measured = MediaStills.contrast(withText: first, without: second, rect: rect)
            {
                fields["contrast"] = .object([
                    "ratio": .number((measured.ratio * 100).rounded() / 100), "frame": .integer(at),
                    "textLuminance": .number((measured.text * 1_000).rounded() / 1_000),
                    "backgroundLuminance": .number((measured.background * 1_000).rounded() / 1_000),
                    "textPixels": .integer(measured.pixels),
                ])
            } else {
                fields["contrast"] = .null
            }
            return .object(fields)
        }
    }

    /// Before and after in one grid (P0-B5): the frame without colour or the source frame, next to the edit.
    func compareFrames(_ arguments: CommandArguments) async throws -> JSONValue {
        let mode = try arguments.string("compare")
        var rows: [(frame: Int, item: String?)] = try (arguments.optionalString("frames") ?? "").split(separator: ",").map {
            guard let frame = Int($0.trimmingCharacters(in: .whitespaces)), frame >= 0, frame < project.duration else {
                throw RPCFailure(-32602, "frames must be timeline frames inside the edit")
            }
            return (frame, nil)
        }
        for id in (arguments.optionalString("items") ?? "").split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard let item = project.tracks.flatMap(\.items).first(where: { $0.id == id }) else {
                throw RPCFailure(-32602, "Unknown item \(id)")
            }
            rows.append((item.at + item.duration / 2, id))
        }
        guard !rows.isEmpty, rows.count <= 40 else { throw RPCFailure(-32602, "Give 1–40 frames or items") }
        let width = arguments.optionalInt("width") ?? 390
        let longEdge = Int((Double(width) * Double(max(project.width, project.height)) / Double(max(1, project.width))).rounded())
        let edited = try await timelineImages(rows.map(\.frame), maximumSide: longEdge)
        var before: [Int: CGImage] = [:]
        var sources: [Int: Double] = [:]
        if mode == "graded" {
            guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
            var ungraded = project.withoutColorEffects()
            ungraded.revision = 0
            let snapshot = try await engine.build(ungraded, root: root, workspace: settings.workspace, purpose: .preview)
            before = try await images(of: snapshot, frames: rows.map(\.frame), maximumSide: longEdge)
        } else {
            (before, sources) = try await sourceFrames(rows.map(\.frame), maximumSide: longEdge)
        }
        let fps = project.fps.value
        let cells = rows.flatMap { row in
            [
                MediaStills.Cell(image: before[row.frame], label: "f\(row.frame) \(mode == "graded" ? "ungraded" : "source")", group: 0),
                MediaStills.Cell(image: edited[row.frame], label: "f\(row.frame) \(MediaStills.clock(Double(row.frame) / fps)) edit", group: 1),
            ]
        }
        guard let image = MediaStills.sheet(cells, columns: 2, longEdge: longEdge) else {
            throw RPCFailure(-32603, "The grid is too large; lower width")
        }
        let directory = try stillsDirectory()
        let url = directory.appendingPathComponent("compare-\(mode)-r\(project.revision)-\(Int(Date().timeIntervalSince1970)).png")
        try MediaStills.png(image).write(to: url, options: .atomic)
        MediaStills.prune(directory, keeping: Self.keptStills)
        return .object([
            "path": .string(url.path), "columns": .array([.string(mode == "graded" ? "ungraded" : "source"), .string("edit")]),
            "rows": .array(rows.map { row in
                var json: [String: JSONValue] = ["frame": .integer(row.frame)]
                if let item = row.item { json["item"] = .string(item) }
                if let seconds = sources[row.frame] { json["sourceSeconds"] = .number((seconds * 1_000).rounded() / 1_000) }
                return .object(json)
            }),
            "width": .integer(image.width), "height": .integer(image.height),
        ])
    }

    /// The source frame the clip on Main shows at each timeline frame (no reframe, no grade), and its source second.
    private func sourceFrames(_ frames: [Int], maximumSide: Int) async throws -> ([Int: CGImage], [Int: Double]) {
        let main = project.tracks.first { $0.role == TrackRole.main }?.items ?? []
        var images: [Int: CGImage] = [:], seconds: [Int: Double] = [:]
        for frame in frames {
            guard let clip = main.first(where: { $0.at <= frame && frame < $0.end }), let mediaID = clip.mediaID,
                let media = project.media.first(where: { $0.id == mediaID }), let url = try? analysisSource(mediaID).url
            else { continue }
            let second = Double(clip.sourceIn) / media.fps.value
                + clip.sourceSeconds(afterFrames: frame - clip.at, fps: project.fps)
            seconds[frame] = second
            let index = min(max(0, media.frames - 1), Int((second * media.fps.value).rounded(.down)))
            images[frame] = try await MediaStills.images(
                url: url, isImage: media.isImage, fps: media.fps, frames: [index], maximumSide: maximumSide)[index]
        }
        return (images, seconds)
    }

    /// The preview composition of this revision, waiting up to 5 s for it after an edit.
    func currentComposition() async throws -> CompositionSnapshot {
        for _ in 0..<500 where preview.currentBuild == nil && project.duration > 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard project.duration > 0, let snapshot = preview.currentBuild else {
            throw RPCFailure(-32602, "The timeline has no picture yet")
        }
        return snapshot
    }

    /// Composed frames of the timeline, each fitted inside `maximumSide` pixels.
    func timelineImages(_ frames: [Int], maximumSide: Int) async throws -> [Int: CGImage] {
        try await images(of: try await currentComposition(), frames: frames, maximumSide: maximumSide)
    }

    func images(of snapshot: CompositionSnapshot, frames: [Int], maximumSide: Int) async throws -> [Int: CGImage] {
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumSide, height: maximumSide)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var result: [Int: CGImage] = [:]
        for await image in generator.images(for: frames.map(project.fps.time)) {
            try Task.checkCancellation()
            if let picture = try? image.image { result[project.fps.frame(image.requestedTime)] = picture }
        }
        return result
    }

    private var mainCutFrames: [Int] {
        (project.tracks.first { $0.role == TrackRole.main }?.items.sorted { $0.at < $1.at } ?? []).dropFirst().map(\.at)
    }

    func reviewWindow(_ arguments: CommandArguments) async throws -> JSONValue {
        let center = try arguments.int("frame")
        let duration = project.duration
        guard center >= 0, center < duration else { throw RPCFailure(-32602, "frame must be within the timeline") }
        let span = arguments.optionalInt("span") ?? 6, step = arguments.optionalInt("step") ?? 1
        let first = max(0, center - span), last = min(duration - 1, center + span)
        let frames = Array(stride(from: first, through: last, by: step))
        let width = arguments.optionalInt("width") ?? 1_600
        let fps = project.fps.value
        let images = try await timelineImages(frames, maximumSide: max(120, width / max(1, frames.count) * 2))
        let snapshot = try await currentComposition()
        let from = Double(first) / fps, to = Double(last + 1) / fps
        let range = CMTimeRange(start: project.fps.time(first), end: project.fps.time(last + 1))
        let levels = try await RenderDrift.envelope(snapshot.composition, mix: snapshot.audioMix, range: range)
        let words = await syncWords().words.filter { $0.end > first && $0.at <= last }
        let cuts = mainCutFrames.filter { $0 >= first && $0 <= last }
        let strip = MediaStills.Strip(
            frames: frames.map { (Double($0) / fps, images[$0]) },
            levels: levels.map { (0.01, $0.map(Double.init)) },
            gaps: [], words: words.map { ($0.text, Double($0.at) / fps, Double($0.end) / fps) }, from: from, to: to,
            levelsFrom: from, marks: cuts.map { Double($0) / fps }, labels: frames.map { "f\($0)" })
        guard let image = MediaStills.strip(strip, width: width) else {
            throw RPCFailure(-32603, "The window could not be drawn; lower width")
        }
        let directory = try stillsDirectory()
        let url = directory.appendingPathComponent("window-r\(project.revision)-f\(center)-\(span)-\(width).png")
        try MediaStills.png(image).write(to: url, options: .atomic)
        MediaStills.prune(directory, keeping: Self.keptStills)
        // The level per frame: mean power of its 10 ms windows.
        let perFrame: [JSONValue] = frames.map { frame in
            let start = Int((Double(frame - first) / fps * 100).rounded(.down))
            let end = max(start + 1, Int((Double(frame - first + 1) / fps * 100).rounded(.down)))
            let slice = (levels ?? []).dropFirst(start).prefix(end - start)
            guard !slice.isEmpty else { return .object(["frame": .integer(frame), "db": .null]) }
            let power = slice.reduce(0) { $0 + pow(10, Double($1) / 10) } / Double(slice.count)
            return .object(["frame": .integer(frame), "db": .number((10 * log10(max(power, 1e-10)) * 10).rounded() / 10)])
        }
        return .object([
            "path": .string(url.path), "revision": .integer(project.revision), "frame": .integer(center),
            "frames": .array(frames.map { .object(["frame": .integer($0), "seconds": .number((Double($0) / fps * 1_000).rounded() / 1_000)]) }),
            "cuts": .array(cuts.map(JSONValue.integer)),
            "words": .array(words.map { .object(["text": .string($0.text), "at": .integer($0.at), "end": .integer($0.end)]) }),
            "levels": levels == nil ? .null : .array(perFrame), "width": .integer(image.width),
            "height": .integer(image.height),
        ])
    }

    /// The frames a sheet shows: listed frames and `first`/`last`, every cut, the middle of each title, and a frame
    /// every `every` seconds (2 by default when nothing else is asked).
    private func sheetFrames(_ arguments: CommandArguments) throws -> [Int] {
        let duration = project.duration
        let fps = project.fps.value
        var frames: [Int] = []
        for part in (arguments.optionalString("at") ?? "").split(separator: ",") {
            let text = part.trimmingCharacters(in: .whitespaces)
            switch text {
            case "first": frames.append(0)
            case "last": frames.append(duration - 1)
            default:
                guard let frame = Int(text) else { throw RPCFailure(-32602, "at: frame numbers, first or last") }
                frames.append(frame)
            }
        }
        if arguments.bool("cuts") { frames += [0] + mainCutFrames }
        if arguments.bool("text") {
            frames += project.tracks.filter { $0.kind == TrackKind.text && $0.role != TrackRole.captions }
                .flatMap(\.items).map { $0.at + $0.duration / 2 }
        }
        let every = arguments.optionalDouble("every") ?? (frames.isEmpty ? 2 : nil)
        if let every { frames += stride(from: 0.0, to: Double(duration) / fps, by: every).map { Int(($0 * fps).rounded()) } }
        let kept = Set(frames.filter { $0 >= 0 && $0 < duration }).sorted()
        guard kept.count <= Self.maximumStills else {
            throw RPCFailure(-32602, "\(kept.count) cells asked; at most \(Self.maximumStills)")
        }
        return kept
    }

    /// What a cell shows: the visual items at `frame` and the text on screen.
    private func cellIndex(_ frame: Int, cell: Int) -> [String: JSONValue] {
        var items: [JSONValue] = [], text: [JSONValue] = []
        for track in project.tracks where track.kind != TrackKind.audio {
            for item in track.items where item.at <= frame && frame < item.end {
                items.append(.string(item.id))
                if track.kind == TrackKind.text, !item.text.isEmpty { text.append(.string(item.text)) }
            }
        }
        return [
            "cell": .integer(cell), "frame": .integer(frame),
            "seconds": .number((Double(frame) / project.fps.value * 1_000).rounded() / 1_000), "items": .array(items),
            "text": .array(text),
        ]
    }

    func timelineSheet(_ arguments: CommandArguments) async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        let frames = try sheetFrames(arguments)
        guard !frames.isEmpty else { throw RPCFailure(-32602, "The timeline is empty") }
        let size = arguments.optionalInt("size") ?? 320
        let platforms = try sheetPlatforms(arguments.optionalString("outputs"))
        // Kept per revision and request: asking again reads the index.
        let request = [
            project["id"]?.string ?? "", "\(project.revision)", "\(frames)", "\(size)", "\(arguments.optionalInt("columns") ?? 0)",
            "\(arguments.optionalInt("rows") ?? 0)", platforms.map(\.id).joined(separator: ","),
        ].joined(separator: "|")
        let key = SHA256.hash(data: Data(request.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let folder = ProjectCache.url(.timelineSheets, projectRoot: root).appendingPathComponent(key, isDirectory: true)
        let index = folder.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: index), case .object(var cached)? = try? JSONValue(parsing: data) {
            cached["cached"] = .bool(true)
            return .object(cached)
        }
        let images = try await timelineImages(frames, maximumSide: size)
        let portrait = project.height > project.width
        let columns = arguments.optionalInt("columns") ?? (portrait ? 8 : 6)
        let perSheet = columns * (arguments.optionalInt("rows") ?? (portrait ? 3 : 6))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var sheets: [JSONValue] = []
        for (group, platform) in ([nil] + platforms.map(Optional.some)).enumerated() {
            let cells = frames.enumerated().map { number, frame in
                MediaStills.Cell(
                    image: images[frame],
                    label: [platform?.id, "\(number + 1)", MediaStills.clock(Double(frame) / project.fps.value)]
                        .compactMap { $0 }.joined(separator: " "),
                    group: group, zones: platform?.safeArea)
            }
            for (page, start) in stride(from: 0, to: cells.count, by: perSheet).enumerated() {
                let part = Array(cells[start..<min(cells.count, start + perSheet)])
                guard let image = MediaStills.sheet(part, columns: columns, longEdge: size) else {
                    throw RPCFailure(-32603, "The sheet is too large; lower size or columns")
                }
                let url = folder.appendingPathComponent("\(platform?.id ?? "sheet")-\(page + 1).png")
                try MediaStills.png(image).write(to: url, options: .atomic)
                sheets.append(.object([
                    "path": .string(url.path), "output": platform.map { .string($0.id) } ?? .null,
                    "firstCell": .integer(start + 1), "cells": .integer(part.count), "width": .integer(image.width),
                    "height": .integer(image.height),
                ]))
            }
        }
        let result: [String: JSONValue] = [
            "revision": .integer(project.revision), "index": .string(index.path), "sheets": .array(sheets),
            "cells": .array(frames.enumerated().map { .object(cellIndex($1, cell: $0 + 1)) }),
            "columns": .integer(columns), "cached": .bool(false),
        ]
        try JSONEncoder().encode(JSONValue.object(result)).write(to: index, options: .atomic)
        Self.pruneSheets(ProjectCache.url(.timelineSheets, projectRoot: root), keeping: 20)
        return .object(result)
    }

    /// `all`: every output preset of the project with a platform; or preset names, comma separated. Only platforms
    /// of the frame's shape.
    private func sheetPlatforms(_ text: String?) throws -> [OutputPlatform] {
        guard let text, !text.isEmpty else { return [] }
        let names = text == "all" ? project.outputPresets : text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var platforms: [OutputPlatform] = []
        for name in names {
            guard let preset = ExportPreset(rawValue: name) else { throw RPCFailure(-32602, "Unknown output \(name)") }
            if let platform = preset.platform, platform.vertical == (project.height > project.width),
                !platforms.contains(where: { $0.id == platform.id })
            {
                platforms.append(platform)
            }
        }
        return platforms
    }

    /// Keeps the `limit` newest sheet folders.
    private static func pruneSheets(_ directory: URL, keeping limit: Int) {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return }
        let modified = { (url: URL) in
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        for url in folders.sorted(by: { modified($0) > modified($1) }).dropFirst(limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
