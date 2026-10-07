import Foundation

/// The record as data for the agent (`media.analysis`): file facts, cuts and shots, shot statistics and sound
/// spans. No verdicts: the numbers come with their units and the limits used to read them.
extension MediaAnalysis {
    /// A frame-duration spread above this ratio (longest over shortest) is reported as variable frame rate.
    public static let variableFrameRatio = 1.05

    public func json(
        limits: Limits = Limits(), samples includeSamples: Bool = false, curve includeCurve: Bool = false
    ) -> JSONValue {
        var result: [String: JSONValue] = [
            "key": .string(key), "version": .integer(version), "measuredBy": .string(measuredBy),
            "measuredAt": .string(measuredAt), "tech": techJSON,
            "picture": pictureJSON(limits: limits, samples: includeSamples),
            "sound": soundJSON(limits: limits, curve: includeCurve),
        ]
        if let picture {
            result["corrections"] = .object([
                "add": .array(corrections.add.map { Self.number(Double($0) / picture.fps) }),
                "remove": .array(corrections.remove.map { Self.number(Double($0) / picture.fps) }),
            ])
        }
        return .object(result)
    }

    /// A short line for `media.list --analysis`: what is measured, and the shot and activity counts at the default
    /// limits.
    public var overviewJSON: JSONValue {
        var row: [String: JSONValue] = [
            "measured": .bool(true), "key": .string(key), "measuredAt": .string(measuredAt),
            "picture": .bool(picture != nil), "sound": .bool(sound != nil),
        ]
        if picture != nil { row["shots"] = .integer(cuts(minScore: Limits().minScore).count + 1) }
        if !corrections.isEmpty { row["corrected"] = .bool(true) }
        return .object(row)
    }

    var techJSON: JSONValue {
        var result: [String: JSONValue] = ["seconds": Self.number(tech.seconds)]
        if let bytes = tech.bytes { result["bytes"] = .integer(bytes) }
        if let video = tech.video {
            var row: [String: JSONValue] = [
                "width": .integer(video.width), "height": .integer(video.height), "rotation": .integer(video.rotation),
                "nominalFPS": Self.number(video.nominalFPS), "seconds": Self.number(video.seconds),
            ]
            let optional: [(String, JSONValue?)] = [
                ("codec", video.codec.map(JSONValue.string)), ("frames", video.frames.map(JSONValue.integer)),
                ("minFrameSeconds", video.minFrameSeconds.map(Self.number)),
                ("maxFrameSeconds", video.maxFrameSeconds.map(Self.number)),
                ("meanFrameSeconds", video.meanFrameSeconds.map(Self.number)),
                ("transfer", video.transfer.map(JSONValue.string)), ("primaries", video.primaries.map(JSONValue.string)),
                ("matrix", video.matrix.map(JSONValue.string)), ("bitDepth", video.bitDepth.map(JSONValue.integer)),
            ]
            for case let (name, value?) in optional { row[name] = value }
            if let low = video.minFrameSeconds, let high = video.maxFrameSeconds, low > 0 {
                row["variableFrameRate"] = .bool(high / low > Self.variableFrameRatio)
            }
            row["transferKind"] = .string(Self.transferKind(video.transfer))
            result["video"] = .object(row)
        }
        if let audio = tech.audio {
            var row: [String: JSONValue] = [
                "channels": .integer(audio.channels), "sampleRate": Self.number(audio.sampleRate),
                "seconds": Self.number(audio.seconds),
            ]
            if let codec = audio.codec { row["codec"] = .string(codec) }
            result["audio"] = .object(row)
        }
        if let video = tech.video, let audio = tech.audio {
            result["audioMinusVideoSeconds"] = Self.number(audio.seconds - video.seconds)
        }
        return .object(result)
    }

    /// `sdr`, `pq`, `hlg`, `log` or `unknown`, from the transfer function the file declares (not from the picture).
    static func transferKind(_ transfer: String?) -> String {
        guard let transfer = transfer?.lowercased() else { return "unknown" }
        if transfer.contains("2084") || transfer.contains("pq") { return "pq" }
        if transfer.contains("hlg") || transfer.contains("2100") { return "hlg" }
        if transfer.contains("log") { return "log" }
        if transfer.contains("709") || transfer.contains("601") || transfer.contains("srgb")
            || transfer.contains("2_2") || transfer.contains("linear") || transfer.contains("240") {
            return "sdr"
        }
        return "unknown"
    }

    func pictureJSON(limits: Limits, samples includeSamples: Bool) -> JSONValue {
        guard let picture else { return .null }
        let fps = picture.fps
        let cuts = cuts(minScore: limits.minScore)
        let (shots, lengths) = shotsJSON(cuts)
        var summary = ReviewShots.summary(seconds: lengths, span: Double(picture.frames) / fps).object
        summary["histogram"] = Self.histogram(lengths)
        summary["cutCurve"] = Self.cutCurve(cuts, fps: fps, seconds: Double(picture.frames) / fps)
        var result: [String: JSONValue] = [
            "fps": Self.number(fps), "interval": .integer(picture.interval), "frames": .integer(picture.frames),
            "source": .string(picture.source),
            "units": .string(
                "Source frames at fps. luma, spread, change, peak and cut scores as in review.picture (fractions of "
                    + "full scale on a 24x24 grey thumbnail); sharpness: mean absolute Laplacian of a 256-pixel grey "
                    + "frame; colourfulness: Hasler-Susstrunk on a small RGB thumbnail."),
            "minScore": Self.number(limits.minScore), "candidateFloor": Self.number(picture.candidateFloor),
            "floors": ReviewPicture.floorsJSON,
            "cuts": .array(cuts.map { cut in
                var row: [String: JSONValue] = [
                    "frame": .integer(cut.frame), "seconds": .number(Self.rounded(Double(cut.frame) / fps)),
                ]
                row[cut.score == nil ? "added" : "score"] = cut.score.map(Self.number) ?? .bool(true)
                return .object(row)
            }),
            "candidatesBelow": .integer(picture.candidates.filter { $0.score < limits.minScore }.count),
            "shots": .array(shots), "summary": .object(summary),
        ]
        if includeSamples {
            result["samples"] = .array(picture.samples.map { sample in
                .object([
                    "frame": .integer(sample.frame), "seconds": .number(Self.rounded(Double(sample.frame) / fps)),
                    "luma": Self.number(sample.luma), "spread": Self.number(sample.spread),
                    "change": Self.number(sample.change), "peak": Self.number(sample.peak),
                    "sharpness": Self.number(sample.sharpness), "colourfulness": Self.number(sample.colourfulness),
                ])
            })
        }
        return .object(result)
    }

    func soundJSON(limits: Limits, curve includeCurve: Bool) -> JSONValue {
        guard let sound, !sound.levels.isEmpty else { return .null }
        let sorted = sound.levels.sorted()
        let percentile = { (share: Double) in sorted[min(sorted.count - 1, Int(Double(sorted.count) * share))] }
        let silent = sound.levels.filter { $0 <= Self.silenceDb }.count
        let floor = percentile(0.1)
        let spans = Self.activeSpans(sound, over: floor + limits.activityDb, bridge: limits.bridgeSeconds)
        let total = Double(sound.levels.count) * sound.window
        var result: [String: JSONValue] = [
            "units": .string(
                "dBFS. Levels are RMS over \(sound.window) s windows of all channels (not LUFS; use audio.measure for "
                    + "loudness). floorDb, medianDb and loudDb are the 10th, 50th and 95th percentiles of all "
                    + "windows (digital silence reads \(Self.silenceDb)). Active spans are sound over floorDb + "
                    + "activityDb, speech or not."),
            "window": Self.number(sound.window), "peakDb": .number(Self.rounded(sound.peakDb)),
            "floorDb": .number(Self.rounded(floor)), "medianDb": .number(Self.rounded(percentile(0.5))),
            "loudDb": .number(Self.rounded(percentile(0.95))),
            "silentShare": Self.number(Double(silent) / Double(sound.levels.count)),
            "activityDb": Self.number(limits.activityDb), "bridgeSeconds": Self.number(limits.bridgeSeconds),
            "active": .array(spans.map { start, end in
                .object([
                    "start": .number(Self.rounded(start)), "end": .number(Self.rounded(end)),
                    "seconds": .number(Self.rounded(end - start)),
                ])
            }),
            "activeShare": Self.number(total > 0 ? spans.map { $1 - $0 }.reduce(0, +) / total : 0),
            "stereoCorrelation": sound.stereoCorrelation.map(Self.number) ?? .null,
        ]
        if includeCurve { result["curve"] = Self.curve(sound) }
        return .object(result)
    }

    /// Windows at or over `threshold`, joined across quiet gaps up to `bridge` seconds, as start and end seconds.
    static func activeSpans(_ sound: Sound, over threshold: Double, bridge: Double) -> [(Double, Double)] {
        var spans: [(Double, Double)] = []
        for (index, level) in sound.levels.enumerated() where level >= threshold {
            let start = Double(index) * sound.window
            let end = start + sound.window
            if let last = spans.last, start - last.1 <= bridge + 1e-9 {
                spans[spans.count - 1].1 = end
            } else {
                spans.append((start, end))
            }
        }
        return spans
    }

    /// RMS level per second (power mean of its windows), dBFS.
    static func curve(_ sound: Sound) -> JSONValue {
        let perSecond = max(1, Int((1 / sound.window).rounded()))
        return .array(stride(from: 0, to: sound.levels.count, by: perSecond).map { start in
            let slice = sound.levels[start..<min(sound.levels.count, start + perSecond)]
            let power = slice.map { $0 <= silenceDb ? 0 : pow(10, $0 / 10) }.reduce(0, +) / Double(slice.count)
            return .number(power > 0 ? (max(silenceDb, 10 * log10(power)) * 10).rounded() / 10 : silenceDb)
        })
    }
}
