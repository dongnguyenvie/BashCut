import Foundation

/// UTF-8 SubRip interchange. Project timing remains integer frames; SRT time is rounded to the nearest frame.
public enum SubRip {
    public static let maximumBytes = 4 * 1024 * 1024

    /// One cue in seconds, before it is placed on frames.
    public struct Cue: Sendable, Equatable {
        public let start: Double
        public let end: Double
        public let text: String
    }

    public static func decode(_ text: String, fps: FrameRate) throws -> [Item] {
        guard fps.numerator > 0, fps.denominator > 0 else { throw ProjectError.invalid("Frame rate is invalid") }
        return try cues(text).enumerated().map { index, cue in
            let at = (cue.start * fps.value).rounded()
            let finish = (cue.end * fps.value).rounded()
            guard at >= 0, finish <= 2_000_000_000, at < finish else {
                throw ProjectError.invalid(
                    "SRT cue \(index + 1): timing is outside frame bounds or shorter than one frame")
            }
            return caption(cue.text, at: Int(at), duration: Int(finish - at))
        }
    }

    static func caption(_ text: String, at: Int, duration: Int) -> Item {
        var item = Item(at: at, duration: duration)
        item["text"] = .string(text)
        item["textPreset"] = .string("bold-outline")
        return item
    }

    public static func cues(_ text: String) throws -> [Cue] {
        guard text.utf8.count <= maximumBytes else { throw ProjectError.invalid("SRT is too large") }
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
        return try blocks.enumerated().map { index, block in try cue(block, index: index + 1) }
    }

    private static func cue(_ lines: [String], index: Int) throws -> Cue {
        var lines = lines
        if let first = lines.first, Int(first.trimmingCharacters(in: .whitespaces)) != nil { lines.removeFirst() }
        guard lines.count >= 2 else { throw ProjectError.invalid("SRT cue \(index): timing and text are required") }
        let timing = lines.removeFirst().components(separatedBy: "-->")
        guard timing.count == 2 else { throw ProjectError.invalid("SRT cue \(index): invalid time range") }
        let start = try seconds(timing[0])
        let end = try seconds(timing[1])
        guard end > start else { throw ProjectError.invalid("SRT cue \(index): end must follow start") }
        return Cue(start: start, end: end, text: lines.joined(separator: "\n"))
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
    /// Captions from SubRip text. With `media`, cue times are that media's source times: each cue is placed
    /// through every clip where the media is heard (its trim, position, speed and speed ramp), parts outside the
    /// clips (and muted clips) are dropped, and `replace` removes only captions made from that media before. Without
    /// `media`, or when the media is not on the timeline, cue times are timeline times and `replace` removes every
    /// caption.
    public func importingSubRip(
        _ text: String, replace: Bool = false, provenance: [String: JSONValue]? = nil, media: String? = nil,
        words: [CaptionWords.Timed] = [], wordStyle: String? = nil
    ) throws -> EditOperation {
        try validate()
        guard let captions = tracks.first(where: { $0.role == "captions" }) else {
            throw ProjectError.invalid("Caption track is missing")
        }
        let placed = media.map { id in tracks.contains { $0.items.contains { $0.mediaID == id } } } ?? false
        var items = placed
            ? try placedCues(SubRip.cues(text), in: media.map(audibleClips) ?? [], words: words)
            : try timelineCues(SubRip.decode(text, fps: fps), words: words)
        guard !items.isEmpty else { throw ProjectError.invalid("No captions fall inside the media's clips") }
        for index in items.indices {
            if let provenance { items[index]["generatedBy"] = .object(provenance) }
            if let media { items[index]["captionMedia"] = .string(media) }
            if let wordStyle { items[index]["wordStyle"] = .string(wordStyle) }
        }
        let layers = captionLayers(from: captions)
        let removed = replace
            ? Set(layers.flatMap(\.items).filter { media == nil || $0["captionMedia"]?.string == media }.map(\.id))
            : []
        let deletions = removed.sorted().map { EditOperation.delete(item: $0, ripple: false) }
        return .group(
            label: "Import SRT", author: .user,
            ops: deletions + captionPlacements(items, base: captions, removing: removed))
    }

    /// Clips where `mediaID` is heard: audio clips (including the sound linked to a video clip) and video clips
    /// without linked sound, leaving out muted clips and layers and freeze frames.
    func audibleClips(_ mediaID: String) -> [(item: Item, media: Media)] {
        guard let asset = media.first(where: { $0.id == mediaID }) else { return [] }
        return tracks.flatMap { track -> [(item: Item, media: Media)] in
            guard track.kind == "audio" || track.kind == "video", !track.isMuted else { return [] }
            return track.items.filter { item in
                item.mediaID == mediaID && item["muted"] != .bool(true) && item["freezeFrame"] == nil
                    && (track.kind == "audio" || item["linkedAudio"] == nil)
            }.map { ($0, asset) }
        }.sorted { $0.item.at < $1.item.at }
    }

    /// Cues at timeline times, with the words heard during each (words near the cue are handed to attachingWords,
    /// which keeps the ones whose middle falls inside it).
    private func timelineCues(_ cues: [Item], words: [CaptionWords.Timed]) -> [Item] {
        guard !words.isEmpty else { return cues }
        let sorted = words.sorted { $0.start < $1.start }
        let longest = sorted.map { $0.end - $0.start }.max() ?? 0
        let frame = 1 / fps.value
        return cues.map { item in
            let start = Double(item.at) / fps.value, end = Double(item.end) / fps.value
            let first = sorted.partitioningIndex { $0.start >= start - frame - longest }
            let last = sorted.partitioningIndex { $0.start > end + frame }
            return item.attachingWords(first < last ? Array(sorted[first..<last]) : []) {
                Int(($0 * self.fps.value).rounded())
            }
        }
    }

    /// Places source-time cues through each clip; a cue spanning a cut is split at it.
    func placedCues(
        _ cues: [SubRip.Cue], in clips: [(item: Item, media: Media)], words: [CaptionWords.Timed] = []
    ) -> [Item] {
        var items: [Item] = []
        // A word whose middle lands inside a cue's frames is at most a couple of timeline frames outside the cue in
        // source time (rounding, at the fastest speed); only words that near a cue are handed to attachingWords.
        let margin = 2 * Project.speedRange.upperBound / fps.value
        for (clip, asset) in clips {
            let sourceStart = Double(clip.sourceIn) / asset.fps.value
            let sourceEnd = sourceStart + clip.sourceSeconds(afterFrames: clip.duration, fps: fps)
            // Words heard inside this clip only, mapped through it like the cue.
            let heard = words.filter { $0.end > sourceStart && $0.start < sourceEnd }.sorted { $0.start < $1.start }
            let longest = heard.map { $0.end - $0.start }.max() ?? 0
            for cue in cues where cue.end > sourceStart && cue.start < sourceEnd {
                let frame = { (seconds: Double) in
                    clip.at + Int(clip.timelineFrames(atSourceSeconds: seconds - sourceStart, fps: self.fps).rounded())
                }
                let at = max(clip.at, frame(max(cue.start, sourceStart)))
                let end = min(clip.end, frame(min(cue.end, sourceEnd)))
                guard end > at else { continue }
                let first = heard.partitioningIndex { $0.start >= cue.start - margin - longest }
                let last = heard.partitioningIndex { $0.start > cue.end + margin }
                let near = first < last ? Array(heard[first..<last]) : []
                items.append(SubRip.caption(cue.text, at: at, duration: end - at).attachingWords(near) {
                    frame(min(max($0, sourceStart), sourceEnd))
                })
            }
        }
        return items
    }

    /// The caption layer and the caption layers stacked above it.
    private func captionLayers(from base: Track) -> [Track] {
        guard let baseIndex = tracks.firstIndex(where: { $0.id == base.id }) else { return [] }
        return tracks[baseIndex...].filter { $0.kind == "text" && $0.role == base.role }
    }

    /// Inserts cues on the caption layer; overlapping cues go to the next free caption layer, or to new
    /// caption layers stacked above it.
    private func captionPlacements(_ items: [Item], base: Track, removing: Set<String>) -> [EditOperation] {
        guard let baseIndex = tracks.firstIndex(where: { $0.id == base.id }) else { return [] }
        var layers = captionLayers(from: base)
        for index in layers.indices { layers[index].items.removeAll { removing.contains($0.id) } }
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

extension Array {
    /// The first index whose element satisfies `belongs`, for an array where every such element comes after every
    /// other one (binary search); `endIndex` when there is none.
    func partitioningIndex(where belongs: (Element) -> Bool) -> Int {
        var low = startIndex, high = endIndex
        while low < high {
            let middle = (low + high) / 2
            if belongs(self[middle]) { high = middle } else { low = middle + 1 }
        }
        return low
    }
}
