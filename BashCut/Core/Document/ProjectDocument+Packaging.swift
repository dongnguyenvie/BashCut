import AppKit
import BashCutAutomation
import BashCutEngine
import BashCutProject
import CoreGraphics
import Foundation

/// Covers and chapters per output (P1-F3): files in the project's `render` folder.
extension ProjectDocument {
    func registerPackagingCommands() {
        handle("export.cover") { document, arguments, _ in try await document.exportCover(arguments) }
        handle("export.chapters") { document, arguments, _ in
            let id = arguments.optionalString("platform") ?? "youtube"
            guard let platform = OutputPlatform.named(id) else { throw RPCFailure(-32602, "Unknown platform \(id)") }
            var result = OutputPackaging.chapters(document.project, platform: platform).object
            if arguments.bool("write") {
                let folder = try document.renderFolder()
                let url = folder.appendingPathComponent("chapters-\(platform.id).txt")
                try (result["text"]?.string ?? "").write(to: url, atomically: true, encoding: .utf8)
                result["path"] = .string(url.path)
            }
            return .object(result)
        }
    }

    func renderFolder() throws -> URL {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Save the project first") }
        let folder = root.appendingPathComponent("render", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// One still of the composed frame per aspect, cropped from the centre: the asked aspect, else each output's
    /// cover aspect (the platform's `cover.aspect`, else its shape).
    func exportCover(_ arguments: CommandArguments) async throws -> JSONValue {
        try await exportCover(
            frame: try arguments.int("frame"),
            aspects: arguments.optionalString("aspect").map { $0.split(separator: ",").map(String.init) } ?? [],
            size: arguments.optionalInt("size"), title: arguments.optionalString("title"),
            preset: arguments.optionalString("preset"), titleSize: arguments.optionalDouble("titleSize"))
    }

    /// The Export sheet's Save Cover: the frame at the playhead, each output's aspect, the title typed there.
    func saveCoverAtPlayhead(title: String, preset: String) {
        Task {
            do {
                let result = try await exportCover(frame: min(playhead, max(0, project.duration - 1)), aspects: [],
                                                   size: nil, title: title, preset: title.isEmpty ? nil : preset)
                let paths = result.object["covers"]?.array.compactMap { $0.object["path"]?.string } ?? []
                if let first = paths.first { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: first)]) }
                message = String(format: String(localized: "Saved %lld cover(s) in render/"), paths.count)
            } catch { message = error.localizedDescription }
        }
    }

    func exportCover(
        frame: Int, aspects asked: [String], size: Int?, title: String?, preset: String?, titleSize: Double? = nil
    ) async throws -> JSONValue {
        guard frame >= 0, frame < project.duration else { throw RPCFailure(-32602, "frame must be within the timeline") }
        var aspects = asked
        if aspects.isEmpty {
            aspects = outputPresets.compactMap(\.platform).compactMap { platform in
                platform.facts["cover.aspect"]?.value.string ?? platform.facts["shape"]?.value.string
            }
        }
        if aspects.isEmpty { aspects = [project.width > project.height ? "16:9" : project.width == project.height ? "1:1" : "9:16"] }
        let longEdge = size ?? 1_920
        guard let image = try await timelineImages([frame], maximumSide: longEdge)[frame] else {
            throw RPCFailure(-32603, "The frame could not be drawn")
        }
        let title = try coverTitle(title, preset: preset, size: titleSize)
        let folder = try renderFolder()
        var covers: [JSONValue] = []
        for aspect in Set(aspects).sorted() {
            let parts = aspect.split(separator: ":").compactMap { Double($0) }
            guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { throw RPCFailure(-32602, "aspect is W:H such as 16:9") }
            let crop = Self.centreCrop(width: image.width, height: image.height, aspect: parts[0] / parts[1])
            guard var cropped = image.cropping(to: crop) else { continue }
            var row: [String: JSONValue] = [:]
            if let title, let drawn = CoverTitle.draw(title, over: cropped) {
                cropped = drawn.image
                row["titleBox"] = .object([
                    "x": .number(Self.rounded(drawn.box.minX)), "y": .number(Self.rounded(drawn.box.minY)),
                    "width": .number(Self.rounded(drawn.box.width)), "height": .number(Self.rounded(drawn.box.height)),
                ])
            }
            let suffix = title == nil ? "" : "-title"
            let url = folder.appendingPathComponent(
                "cover-f\(frame)-\(aspect.replacingOccurrences(of: ":", with: "x"))\(suffix).png")
            try MediaStills.png(cropped).write(to: url, options: .atomic)
            row.merge([
                "aspect": .string(aspect), "path": .string(url.path), "width": .integer(cropped.width), "height": .integer(cropped.height),
            ]) { $1 }
            covers.append(.object(row))
        }
        return .object(["frame": .integer(frame), "covers": .array(covers)])
    }

    /// The text item a cover title draws: `text` in a renderer preset or a library text preset (its style too;
    /// bold-outline by default) at `size` of the cover's short side (CoverTitle.defaultSize when nil: timeline presets
    /// are caption-sized). Nil without a title.
    func coverTitle(_ text: String?, preset: String?, size: Double? = nil) throws -> Item? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            if preset != nil { throw RPCFailure(-32602, "preset needs a title") }
            return nil
        }
        var item = Item(at: 0, duration: 1)
        item["text"] = .string(text)
        let name = preset ?? "bold-outline"
        if TextPreset.all.contains(name) {
            item["textPreset"] = .string(name)
            return CoverTitle.sized(item, size)
        }
        guard let library = try? libraryCatalog.item(name), library.kind == .textPreset else {
            throw RPCFailure(
                -32602, "No text preset \(name): use \(TextPreset.all.joined(separator: ", ")) or a text-preset ID from "
                    + "library list --kind text-preset")
        }
        let look = try textPreset(library)
        item["textPreset"] = .string(look.textPreset)
        var patch = try look.patch(for: item, project: project)
        patch["keyframes"] = nil
        for (key, value) in patch { item[key] = value }
        return CoverTitle.sized(item, size)
    }

    private static func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }

    static func centreCrop(width: Int, height: Int, aspect: Double) -> CGRect {
        let w = Double(width), h = Double(height)
        if w / h > aspect {
            let cropped = (h * aspect).rounded()
            return CGRect(x: ((w - cropped) / 2).rounded(), y: 0, width: cropped, height: h)
        }
        let cropped = (w / aspect).rounded()
        return CGRect(x: 0, y: ((h - cropped) / 2).rounded(), width: w, height: cropped)
    }
}
