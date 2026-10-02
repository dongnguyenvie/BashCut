import Foundation

/// UTF-8 SubRip interchange. Project timing remains integer frames; SRT time is rounded to the nearest frame.
public enum SubRip {
    public static let maximumBytes = 4 * 1024 * 1024

    public static func decode(_ text: String, fps: FrameRate) throws -> [Item] {
        guard text.utf8.count <= maximumBytes, fps.numerator > 0, fps.denominator > 0 else {
            throw ProjectError.invalid("SRT is too large or frame rate is invalid")
        }
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        var blocks: [[String]] = []
        var block: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !block.isEmpty {
                    blocks.append(block)
                    block = []
                }
            } else {
                block.append(line)
            }
        }
        if !block.isEmpty { blocks.append(block) }
        guard !blocks.isEmpty, blocks.count <= 10000 else {
            throw ProjectError.invalid("SRT must contain 1–10000 cues")
        }
        return try blocks.enumerated().map { index, block in try cue(block, index: index + 1, fps: fps) }
    }

    private static func cue(_ lines: [String], index: Int, fps: FrameRate) throws -> Item {
        var lines = lines
        if let first = lines.first, Int(first.trimmingCharacters(in: .whitespaces)) != nil { lines.removeFirst() }
        guard lines.count >= 2 else { throw ProjectError.invalid("SRT cue \(index): timing and text are required") }
        let timing = lines.removeFirst().components(separatedBy: "-->")
        guard timing.count == 2 else { throw ProjectError.invalid("SRT cue \(index): invalid time range") }
        let start = try seconds(timing[0])
        let end = try seconds(timing[1])
        guard end > start else { throw ProjectError.invalid("SRT cue \(index): end must follow start") }
        let at = (start * fps.value).rounded()
        let finish = (end * fps.value).rounded()
        guard at >= 0, finish <= 2_000_000_000, at < finish else {
            throw ProjectError.invalid("SRT cue \(index): timing is outside frame bounds or shorter than one frame")
        }
        var item = Item(at: Int(at), duration: Int(finish - at))
        item["text"] = .string(lines.joined(separator: "\n"))
        item["style"] = .string("bold-outline")
        return item
    }

    private static func seconds(_ timestamp: String) throws -> Double {
        let fields = timestamp.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: ":,"))
        guard fields.count == 4, fields[1].count == 2, fields[2].count == 2, fields[3].count == 3,
            fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
            let hours = Double(fields[0]), let minutes = Int(fields[1]), let seconds = Int(fields[2]),
            let milliseconds = Int(fields[3]), hours.isFinite, (0...59).contains(minutes), (0...59).contains(seconds)
        else {
            throw ProjectError.invalid("SRT timestamp must be HH:MM:SS,mmm")
        }
        return hours * 3600 + Double(minutes * 60 + seconds) + Double(milliseconds) / 1000
    }

    public static func encode(_ project: Project) throws -> String {
        try project.validate()
        let captions = project.tracks.filter { $0.kind == "text" }.flatMap(\.items).enumerated()
            .filter { !$0.element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.element.at == $1.element.at ? $0.offset < $1.offset : $0.element.at < $1.element.at }
        return captions.enumerated().map { index, entry in
            let item = entry.element
            let start = milliseconds(item.at, fps: project.fps)
            let end = max(start + 1, milliseconds(item.end, fps: project.fps))
            // Blank lines delimit SRT cues; collapse paragraph gaps within a single caption.
            let text = item.text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
            return "\(index + 1)\n\(timestamp(start)) --> \(timestamp(end))\n\(text)\n"
        }.joined(separator: "\n")
    }

    private static func milliseconds(_ frame: Int, fps: FrameRate) -> Int {
        Int((Double(frame) * Double(fps.denominator) * 1000 / Double(fps.numerator)).rounded())
    }
    private static func timestamp(_ milliseconds: Int) -> String {
        String(
            format: "%02lld:%02lld:%02lld,%03lld", milliseconds / 3_600_000,
            milliseconds / 60_000 % 60, milliseconds / 1000 % 60, milliseconds % 1000)
    }
}

extension Project {
    public func importingSubRip(
        _ text: String, replace: Bool = false, provenance: [String: JSONValue]? = nil
    ) throws -> EditOperation {
        try validate()
        guard let captions = tracks.first(where: { $0.role == "captions" }) else {
            throw ProjectError.invalid("Caption track is missing")
        }
        var items = try SubRip.decode(text, fps: fps)
        if let provenance {
            for index in items.indices { items[index]["generatedBy"] = .object(provenance) }
        }
        let layers = captionLayers(from: captions)
        let deletions: [EditOperation] = replace
            ? layers.flatMap(\.items).map { .delete(item: $0.id, ripple: false) } : []
        return .group(label: "Import SRT", author: .user, ops: deletions + captionPlacements(items, base: captions, replace: replace))
    }

    /// The caption layer and the caption layers stacked above it.
    private func captionLayers(from base: Track) -> [Track] {
        guard let baseIndex = tracks.firstIndex(where: { $0.id == base.id }) else { return [] }
        return tracks[baseIndex...].filter { $0.kind == "text" && $0.role == base.role }
    }

    /// Inserts cues on the caption layer; overlapping cues go to the next free caption layer, or to new
    /// caption layers stacked above it.
    private func captionPlacements(_ items: [Item], base: Track, replace: Bool) -> [EditOperation] {
        guard let baseIndex = tracks.firstIndex(where: { $0.id == base.id }) else { return [] }
        var layers = captionLayers(from: base)
        if replace { for index in layers.indices { layers[index].items = [] } }
        var scratch = self
        var operations: [EditOperation] = []
        var inserts: [EditOperation] = []
        for item in items.sorted(by: { $0.at < $1.at }) {
            if let lane = layers.firstIndex(where: { $0.isFree(at: item.at, duration: item.duration) }) {
                layers[lane].items.append(item)
                inserts.append(.insert(track: layers[lane].id, item: item))
                continue
            }
            var layer = scratch.overflowTrack(from: base)
            let index = (scratch.tracks.firstIndex(where: { $0.id == layers[layers.count - 1].id }) ?? baseIndex) + 1
            scratch.tracks.insert(layer, at: index)
            operations.append(.addTrack(track: layer, atIndex: index))
            layer.items = [item]
            layers.append(layer)
            inserts.append(.insert(track: layer.id, item: item))
        }
        return operations + inserts
    }
}
