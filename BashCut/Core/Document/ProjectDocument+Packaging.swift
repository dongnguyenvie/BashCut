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
        let frame = try arguments.int("frame")
        guard frame >= 0, frame < project.duration else { throw RPCFailure(-32602, "frame must be within the timeline") }
        var aspects: [String] = arguments.optionalString("aspect").map { $0.split(separator: ",").map(String.init) } ?? []
        if aspects.isEmpty {
            aspects = outputPresets.compactMap(\.platform).compactMap { platform in
                platform.facts["cover.aspect"]?.value.string ?? platform.facts["shape"]?.value.string
            }
        }
        if aspects.isEmpty { aspects = [project.width > project.height ? "16:9" : project.width == project.height ? "1:1" : "9:16"] }
        let longEdge = arguments.optionalInt("size") ?? 1_920
        guard let image = try await timelineImages([frame], maximumSide: longEdge)[frame] else {
            throw RPCFailure(-32603, "The frame could not be drawn")
        }
        let folder = try renderFolder()
        var covers: [JSONValue] = []
        for aspect in Set(aspects).sorted() {
            let parts = aspect.split(separator: ":").compactMap { Double($0) }
            guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { throw RPCFailure(-32602, "aspect is W:H such as 16:9") }
            let crop = Self.centreCrop(width: image.width, height: image.height, aspect: parts[0] / parts[1])
            guard let cropped = image.cropping(to: crop) else { continue }
            let url = folder.appendingPathComponent("cover-f\(frame)-\(aspect.replacingOccurrences(of: ":", with: "x")).png")
            try MediaStills.png(cropped).write(to: url, options: .atomic)
            covers.append(.object([
                "aspect": .string(aspect), "path": .string(url.path), "width": .integer(cropped.width), "height": .integer(cropped.height),
            ]))
        }
        return .object(["frame": .integer(frame), "covers": .array(covers)])
    }

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
