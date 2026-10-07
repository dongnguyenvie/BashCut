import BashCutAutomation
import BashCutEngine
import BashCutProject
import CoreGraphics
import Foundation

/// Source frames as pictures (P0-A5), by source time and never through the timeline: `media.frames` (exact frames,
/// or contact sheets with a label per cell and an optional reference row), `media.frame` (one frame at source
/// size) and `media.strip` (a filmstrip with the sound level, the gaps and the words). Files go to
/// `.bashcut/cache/media-stills`, which keeps the newest few hundred.
extension ProjectDocument {
    static let maximumStills = 400
    static let keptStills = 300

    func registerMediaStillsCommands() {
        handle("media.frames") { document, arguments, _ in try await document.mediaFrames(arguments) }
        handle("media.frame") { document, arguments, _ in try await document.mediaFrame(arguments) }
        handle("media.strip") { document, arguments, _ in try await document.mediaStrip(arguments) }
    }

    /// One media's frames to read: exact `at` seconds, every `every` seconds, or `count` evenly spaced (each in the
    /// middle of its part) over `from…to`.
    struct StillPlan {
        let media: Media
        let url: URL
        let frames: [Int]
    }

    func stillPlan(_ media: Media, arguments: CommandArguments, at: [Double], range: (Double?, Double?)) throws -> StillPlan {
        let source = try analysisSource(media.id)
        let fps = media.fps.value
        let last = max(0, media.frames - 1)
        let frame = { (seconds: Double) in min(last, max(0, Int((seconds * fps + 0.000_1).rounded(.down)))) }
        if media.isImage { return StillPlan(media: media, url: source.url, frames: [0]) }
        if !at.isEmpty { return StillPlan(media: media, url: source.url, frames: at.map(frame)) }
        let start = max(0, range.0 ?? 0), end = min(media.durationSeconds, range.1 ?? media.durationSeconds)
        guard end > start else { throw RPCFailure(-32602, "from must be before to, inside media \(media.id)") }
        var times: [Double] = []
        if let every = arguments.optionalDouble("every") {
            times = Array(stride(from: start, to: end, by: every))
        } else {
            let count = arguments.optionalInt("count") ?? 8
            times = (0..<count).map { start + (Double($0) + 0.5) * (end - start) / Double(count) }
        }
        var seen = Set<Int>()
        return StillPlan(media: media, url: source.url, frames: times.map(frame).filter { seen.insert($0).inserted })
    }

    func mediaFrames(_ arguments: CommandArguments) async throws -> JSONValue {
        let ids = arguments.optionalString("media").map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        let selected = try ids.map { list in try list.map { try analysisSource($0).media } }
            ?? project.media.filter { $0.kind != "audio" }
        let at = try Self.seconds(arguments.optionalString("at"))
        let range = (arguments.optionalDouble("from"), arguments.optionalDouble("to"))
        guard selected.count == 1 || (at.isEmpty && range == (nil, nil)) else {
            throw RPCFailure(-32602, "at, from and to need exactly one media")
        }
        if let audio = selected.first(where: { $0.kind == "audio" }) {
            throw RPCFailure(-32602, "Media \(audio.id) is audio: it has no picture (use media strip)")
        }
        var plans = try selected.map { try stillPlan($0, arguments: arguments, at: at, range: range) }
        var reference: StillPlan?
        if let referenceID = arguments.optionalString("reference") {
            guard selected.count == 1, at.isEmpty else { throw RPCFailure(-32602, "reference needs one media and no at") }
            let media = try analysisSource(referenceID).media
            reference = try stillPlan(
                media, arguments: arguments, at: [],
                range: (arguments.optionalDouble("referenceFrom"), arguments.optionalDouble("referenceTo")))
            if let other = reference, other.frames.count != plans[0].frames.count {
                // The same count of cells in both rows, so they line up.
                plans[0] = StillPlan(media: plans[0].media, url: plans[0].url,
                                     frames: Array(plans[0].frames.prefix(other.frames.count)))
            }
        }
        let total = plans.reduce(reference?.frames.count ?? 0) { $0 + $1.frames.count }
        guard total <= Self.maximumStills else {
            throw RPCFailure(-32602, "\(total) frames asked; at most \(Self.maximumStills) per call")
        }
        let sheet = arguments.bool("sheet") || reference != nil
        let size = arguments.optionalInt("size") ?? (sheet ? 320 : 640)
        var rows: [(plan: StillPlan, images: [Int: CGImage], role: String?)] = []
        if let reference {
            rows.append((reference, try await stills(reference, size: size), "REF"))
        }
        for plan in plans { rows.append((plan, try await stills(plan, size: size), reference == nil ? nil : "OURS")) }
        let directory = try stillsDirectory()
        if !sheet { return try writeFrames(rows, size: size, directory: directory) }
        return try writeSheets(rows, arguments: arguments, size: size, directory: directory)
    }

    private func stills(_ plan: StillPlan, size: Int) async throws -> [Int: CGImage] {
        try await MediaStills.images(
            url: plan.url, isImage: plan.media.isImage, fps: plan.media.fps, frames: plan.frames, maximumSide: size)
    }

    func stillsDirectory() throws -> URL {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        let directory = ProjectCache.url(.mediaStills, projectRoot: root)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }

    private func write(_ image: CGImage, name: String, directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try MediaStills.png(image).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private static func seconds(_ frame: Int, _ media: Media) -> JSONValue {
        .number((Double(frame) / media.fps.value * 1_000).rounded() / 1_000)
    }

    private func writeFrames(
        _ rows: [(plan: StillPlan, images: [Int: CGImage], role: String?)], size: Int, directory: URL
    ) throws -> JSONValue {
        var files: [JSONValue] = []
        for row in rows {
            for frame in row.plan.frames {
                guard let image = row.images[frame] else {
                    files.append(.object([
                        "media": .string(row.plan.media.id), "frame": .integer(frame),
                        "seconds": Self.seconds(frame, row.plan.media), "error": .string("not decoded"),
                    ]))
                    continue
                }
                let url = try write(image, name: "\(row.plan.media.id.prefix(8))-f\(frame)-\(size).png", directory: directory)
                files.append(.object([
                    "path": .string(url.path), "media": .string(row.plan.media.id), "frame": .integer(frame),
                    "seconds": Self.seconds(frame, row.plan.media), "width": .integer(image.width),
                    "height": .integer(image.height),
                ]))
            }
        }
        MediaStills.prune(directory, keeping: Self.keptStills)
        return .object(["frames": .array(files)])
    }

    /// Sheets of `columns × rows` cells labelled `<cell> <file> <m:ss.s>` (REF/OURS rows with a reference); the
    /// cells list maps each cell number back to its media, frame and second.
    private func writeSheets(
        _ rows: [(plan: StillPlan, images: [Int: CGImage], role: String?)], arguments: CommandArguments, size: Int,
        directory: URL
    ) throws -> JSONValue {
        var cells: [(cell: MediaStills.Cell, row: JSONValue)] = []
        for (group, row) in rows.enumerated() {
            let name = String(URL(fileURLWithPath: row.plan.media.path).deletingPathExtension().lastPathComponent.prefix(12))
            for frame in row.plan.frames {
                let number = cells.count + 1
                let time = MediaStills.clock(Double(frame) / row.plan.media.fps.value)
                let label = [row.role, "\(number)", name, time].compactMap { $0 }.joined(separator: " ")
                var json: [String: JSONValue] = [
                    "cell": .integer(number), "media": .string(row.plan.media.id), "frame": .integer(frame),
                    "seconds": Self.seconds(frame, row.plan.media),
                ]
                if let role = row.role { json["row"] = .string(role) }
                if row.images[frame] == nil { json["error"] = .string("not decoded") }
                cells.append((MediaStills.Cell(image: row.images[frame], label: label, group: group), .object(json)))
            }
        }
        let portrait = rows.lazy.compactMap { $0.images.values.first }.first.map { $0.height > $0.width } ?? false
        let referenceColumns = rows.first?.role != nil ? rows[0].plan.frames.count : nil
        let columns = arguments.optionalInt("columns") ?? referenceColumns ?? (portrait ? 8 : 6)
        let perSheet = columns * (arguments.optionalInt("rows") ?? (referenceColumns != nil ? 2 : portrait ? 3 : 6))
        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        var sheets: [JSONValue] = []
        for (index, start) in stride(from: 0, to: cells.count, by: perSheet).enumerated() {
            let page = Array(cells[start..<min(cells.count, start + perSheet)])
            guard let image = MediaStills.sheet(page.map(\.cell), columns: columns, longEdge: size) else {
                throw RPCFailure(-32603, "The sheet is too large; lower size or columns")
            }
            let url = try write(image, name: "sheet-\(stamp)-\(index + 1).png", directory: directory)
            sheets.append(.object([
                "path": .string(url.path), "width": .integer(image.width), "height": .integer(image.height),
                "cells": .array(page.map(\.row)),
            ]))
        }
        MediaStills.prune(directory, keeping: Self.keptStills)
        return .object(["sheets": .array(sheets), "columns": .integer(columns)])
    }

    func mediaFrame(_ arguments: CommandArguments) async throws -> JSONValue {
        let source = try analysisSource(try arguments.string("media"))
        let media = source.media
        let last = max(0, media.frames - 1)
        let frame: Int
        switch (arguments.optionalDouble("at"), arguments.optionalInt("index"), arguments.optionalString("edge")) {
        case (let seconds?, nil, nil): frame = min(last, max(0, Int((seconds * media.fps.value + 0.000_1).rounded(.down))))
        case (nil, let index?, nil):
            guard index <= last else { throw RPCFailure(-32602, "index must be at most \(last)") }
            frame = index
        case (nil, nil, let edge?): frame = edge == "last" ? last : 0
        case (nil, nil, nil): frame = 0
        default: throw RPCFailure(-32602, "Give one of at, index or edge")
        }
        if media.kind == "audio" { throw RPCFailure(-32602, "Media \(media.id) is audio: it has no picture") }
        let maximum = arguments.optionalInt("size")
        guard let image = try await MediaStills.images(
            url: source.url, isImage: media.isImage, fps: media.fps, frames: [frame], maximumSide: maximum)[frame]
        else { throw RPCFailure(-32603, "Frame \(frame) of media \(media.id) could not be decoded") }
        let directory = try stillsDirectory()
        let url = try write(image, name: "\(media.id.prefix(8))-f\(frame)-\(maximum.map(String.init) ?? "full").png",
                            directory: directory)
        MediaStills.prune(directory, keeping: Self.keptStills)
        return .object([
            "path": .string(url.path), "media": .string(media.id), "frame": .integer(frame),
            "seconds": Self.seconds(frame, media), "width": .integer(image.width), "height": .integer(image.height),
        ])
    }

    func mediaStrip(_ arguments: CommandArguments) async throws -> JSONValue {
        let source = try analysisSource(try arguments.string("media"))
        let media = source.media
        let from = max(0, arguments.optionalDouble("from") ?? 0)
        let to = min(media.durationSeconds, arguments.optionalDouble("to") ?? media.durationSeconds)
        guard to > from, !media.isImage else { throw RPCFailure(-32602, "from must be before to, inside a video or audio media") }
        let count = arguments.optionalInt("count") ?? 8
        let width = arguments.optionalInt("width") ?? 1_600
        let fps = media.fps.value
        let last = max(0, media.frames - 1)
        let frames: [Int] = media.kind == "audio" ? [] : (0..<count).map { index in
            let seconds = from + (Double(index) + 0.5) * (to - from) / Double(count)
            return min(last, Int((seconds * fps).rounded(.down)))
        }
        let images = media.kind == "audio" ? [:] : try await MediaStills.images(
            url: source.url, isImage: false, fps: media.fps, frames: frames, maximumSide: max(160, width / max(1, count) * 2))
        var levelSource: String?
        var sound = try storedAnalysis(media.id).record?.sound
        if sound != nil { levelSource = "analysis" } else if media.hasAudio != false {
            sound = try await MediaStills.levels(url: source.url)
            if sound != nil { levelSource = "measured" }
        }
        var gaps: [(start: Double, end: Double)] = []
        var gapsJSON: JSONValue = .null
        if let sound {
            let map = SpeechMap.json(sound: sound, words: nil).object
            gaps = map["gaps"]?.array.compactMap { gap in
                guard let start = gap.object["start"]?.double, let end = gap.object["end"]?.double else { return nil }
                return (start, end)
            } ?? []
            gapsJSON = map["gaps"] == .null ? .object(["shown": .bool(false), "reason": map["reason"] ?? .null])
                : .object(["shown": .bool(true), "count": .integer(gaps.filter { $0.end > from && $0.start < to }.count)])
        }
        let words = (try await storedTranscript(media.id))?.words.filter { $0.end > from && $0.start < to } ?? []
        let pictures: [(seconds: Double, image: CGImage?)] = frames.map { (Double($0) / fps, images[$0]) }
        let levels: (window: Double, values: [Double])? = sound.map { ($0.window, $0.levels) }
        let spoken: [(text: String, start: Double, end: Double)] = words.map { ($0.text, $0.start, $0.end) }
        let strip = MediaStills.Strip(frames: pictures, levels: levels, gaps: gaps, words: spoken, from: from, to: to)
        guard let image = MediaStills.strip(strip, width: width) else {
            throw RPCFailure(-32603, "The strip could not be drawn; lower width")
        }
        let directory = try stillsDirectory()
        let url = try write(
            image, name: "strip-\(media.id.prefix(8))-\(Int(from * 10))-\(Int(to * 10))-\(width).png", directory: directory)
        MediaStills.prune(directory, keeping: Self.keptStills)
        return .object([
            "path": .string(url.path), "media": .string(media.id), "width": .integer(image.width),
            "height": .integer(image.height), "from": .number(from), "to": .number(to),
            "frames": .array(frames.map { frame in
                JSONValue.object(["frame": .integer(frame), "seconds": Self.seconds(frame, media)])
            }),
            "levels": levelSource.map(JSONValue.string) ?? .null, "gaps": gapsJSON, "words": .integer(words.count),
        ])
    }
}
