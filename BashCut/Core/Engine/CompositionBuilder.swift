@preconcurrency import AVFoundation
import BashCutProject

public struct CompositionSnapshot: @unchecked Sendable {
    public let composition: AVComposition
    public let videoComposition: AVVideoComposition
    public let audioMix: AVAudioMix

    public init(composition: AVComposition, videoComposition: AVVideoComposition, audioMix: AVAudioMix) {
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
    }
}

/// Builds compositions from project snapshots. One builder lives as long as its engine, so the assets it
/// opened (and their loaded tracks) are reused by later builds until the file on disk changes.
public actor CompositionBuilder {
    private let source: any MediaSource
    private let cacheLimit: Int
    private var assets: [URL: LoadedAsset] = [:]
    /// Least recently used first.
    private var assetOrder: [URL] = []
    /// Assets opened from disk so far; a cache hit does not count.
    public private(set) var assetLoads = 0

    public init(source: any MediaSource = ProxyMediaSource(), cacheLimit: Int = 64) {
        self.source = source
        self.cacheLimit = max(1, cacheLimit)
    }

    public var cachedAssetCount: Int { assets.count }

    /// The scale at zoom 1: fitting shows the whole picture inside the canvas (bars on the other sides), filling
    /// covers the canvas and crops what does not fit.
    public static func baseScale(source: CGSize, canvas: CGSize, fill: Bool) -> Double {
        let horizontal = canvas.width / abs(source.width), vertical = canvas.height / abs(source.height)
        return fill ? max(horizontal, vertical) : min(horizontal, vertical)
    }

    // This coordinates media loading, video lanes, audio parameters and frame instructions.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func build(_ project: Project, root: URL, workspace: URL? = nil, purpose: RenderPurpose = .export)
        async throws -> CompositionSnapshot
    {
        try project.validate()
        guard project.duration > 0 else { throw ProjectError.invalid("Timeline is empty") }
        let composition = AVMutableComposition()
        var visualByTrack: [String: [PlacedVisual]] = [:]
        var visualLanes: [String: [(end: Int, target: AVMutableCompositionTrack)]] = [:]
        var audioParameters: [AVAudioMixInputParameters] = []
        let speechRanges = AudioGainPlanner.speechRanges(in: project)
        var lutCache: [String: CubeLUT] = [:]
        /// The LUT an item's `color.lut` names, loaded once per build from the project `luts` folder.
        func loadLUT(for item: Item) throws -> CubeLUT? {
            guard let lutID = item["color"]?.object["lut"]?.string,
                let catalog = project.colorLUTs.first(where: { $0.id == lutID })
            else { return nil }
            if let cached = lutCache[lutID] { return cached }
            let directory = root.appendingPathComponent("luts").resolvingSymlinksInPath()
            let lutURL = root.appendingPathComponent(catalog.path).resolvingSymlinksInPath()
            guard lutURL.path.hasPrefix(directory.path + "/") else {
                throw ProjectError.invalid("LUT escapes the project luts folder")
            }
            let loaded = try CubeLUT.load(lutURL)
            guard loaded.dimension == catalog.size else { throw ProjectError.invalid("LUT size changed on disk") }
            lutCache[lutID] = loaded
            return loaded
        }
        let transitionFrom = Dictionary(uniqueKeysWithValues: project.transitions.map { ($0.fromItemID, $0) })
        let transitionTo = Dictionary(uniqueKeysWithValues: project.transitions.map { ($0.toItemID, $0) })
        for track in project.tracks where track.kind == "video" || track.kind == "audio" {
            for item in track.items.sorted(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
                try Task.checkCancellation()
                guard let media = project.media.first(where: { $0.id == item.mediaID }) else { continue }
                // An image is read through its one-frame still movie and held like a freeze frame.
                let isStill = media.kind == "image"
                let mediaURL = try source.url(for: media, root: root, workspace: workspace, purpose: purpose)
                let asset = try await loadedAsset(
                    isStill ? StillImageMovie.movie(for: media, image: mediaURL, root: root) : mediaURL)
                let stillRange = CMTimeRange(start: .zero, duration: StillImageMovie.sampleDuration)
                let freezeFrame = item["freezeFrame"]?.int
                let normalSourceRange = CMTimeRange(
                    start: media.fps.time(item.sourceIn),
                    duration: CMTimeMultiplyByFloat64(
                        project.fps.time(item.duration), multiplier: item.speed))
                let videoSourceRange = isStill ? stillRange : freezeFrame.map {
                    CMTimeRange(start: media.fps.time($0), duration: media.fps.time(1))
                } ?? normalSourceRange
                let destination = project.fps.time(item.at)
                if track.kind == "video" {
                    guard let source = asset.video else {
                        throw ProjectError.invalid("No video track in \(media.path)")
                    }
                    var lanes = visualLanes[track.id] ?? []
                    let laneIndex = lanes.firstIndex(where: { $0.end <= item.at })
                    let target: AVMutableCompositionTrack
                    if let laneIndex {
                        target = lanes[laneIndex].target
                        lanes[laneIndex].end = item.end
                    } else {
                        guard let created = composition.addMutableTrack(
                            withMediaType: .video,
                            preferredTrackID: kCMPersistentTrackID_Invalid)
                        else { throw ProjectError.invalid("Could not allocate video layer") }
                        target = created
                        lanes.append((end: item.end, target: created))
                    }
                    visualLanes[track.id] = lanes
                    if freezeFrame == nil, !isStill, item.speedCurve != nil {
                        try Self.insertRamp(item, media: media, fps: project.fps, from: source, into: target)
                    } else {
                        try target.insertTimeRange(videoSourceRange, of: source, at: destination)
                        target.scaleTimeRange(
                            CMTimeRange(start: destination, duration: videoSourceRange.duration),
                            toDuration: project.fps.time(item.duration))
                    }
                    let preferred = asset.preferredTransform
                    let rect = CGRect(origin: .zero, size: asset.naturalSize).applying(preferred)
                    let properties = item["transform"]?.object ?? [:]
                    let zoom = properties["zoom"]?.double ?? 1
                    let scale = Self.baseScale(
                        source: rect.size, canvas: CGSize(width: project.width, height: project.height),
                        fill: project.fills(item)) * zoom
                    let pan = properties["pan"]?.double ?? 0
                    let tilt = properties["tilt"]?.double ?? 0
                    let transform = preferred.concatenating(
                        CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
                    )
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(
                        CGAffineTransform(
                            translationX: (Double(project.width) - rect.width * scale) / 2 + pan,
                            y: (Double(project.height) - rect.height * scale) / 2 + tilt))
                    let incoming = transitionTo[item.id].map {
                        RenderTransition(
                            kind: $0.kind, startFrame: item.at, duration: $0.duration,
                            incoming: true, fps: project.fps.value)
                    }
                    let lut = try loadLUT(for: item)
                    visualByTrack[track.id, default: []].append(
                        PlacedVisual(
                            start: item.at, end: item.end,
                            layer: FrameLayer(
                                trackID: target.trackID, transform: transform,
                                properties: item.fields, transition: incoming, lut: lut)))
                    if let transition = transitionFrom[item.id],
                        let hold = composition.addMutableTrack(
                            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                    {
                        let consumed = max(
                            1, Int((Double(item.duration) / project.fps.value * media.fps.value
                                * item.speed).rounded(.down)))
                        let frame = freezeFrame ?? min(media.frames - 1, item.sourceIn + consumed - 1)
                        let holdRange = isStill ? stillRange : CMTimeRange(
                            start: media.fps.time(frame), duration: media.fps.time(1))
                        let holdStart = project.fps.time(item.end)
                        try hold.insertTimeRange(holdRange, of: source, at: holdStart)
                        hold.scaleTimeRange(
                            CMTimeRange(start: holdStart, duration: holdRange.duration),
                            toDuration: project.fps.time(transition.duration))
                        visualByTrack[track.id, default: []].append(
                            PlacedVisual(
                                start: item.end, end: item.end + transition.duration,
                                layer: FrameLayer(
                                    trackID: hold.trackID, transform: transform,
                                    properties: item.fields,
                                    transition: RenderTransition(
                                        kind: transition.kind, startFrame: item.end,
                                        duration: transition.duration, incoming: false,
                                        fps: project.fps.value), lut: lut)))
                    }
                }
                // Main sound remains attached in the spike until separate linked dialogue editing lands.
                if track.kind == "audio" || (track.role == "main" && item["linkedAudio"] == nil) {
                    if let source = asset.audio,
                        let target = composition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid)
                    {
                        if item.speedCurve != nil {
                            try Self.insertRamp(item, media: media, fps: project.fps, from: source, into: target)
                        } else {
                            try target.insertTimeRange(normalSourceRange, of: source, at: destination)
                            target.scaleTimeRange(
                                CMTimeRange(start: destination, duration: normalSourceRange.duration),
                                toDuration: project.fps.time(item.duration))
                        }
                        let parameters = audioMixParameters(
                            item: item, sourceTrack: track, track: target, fps: project.fps,
                            envelope: (speechRanges, project.mixGainDb))
                        audioParameters.append(parameters)
                    }
                }
            }
        }
        let targetDuration = project.fps.time(project.duration)
        if composition.duration < targetDuration {
            composition.insertEmptyTimeRange(
                CMTimeRange(
                    start: composition.duration,
                    duration: targetDuration - composition.duration))
        }
        let allItems = project.tracks.flatMap(\.items)
        let transitionBoundaries = project.transitions.compactMap { transition -> [Int]? in
            guard let item = allItems.first(where: { $0.id == transition.toItemID }) else { return nil }
            return [item.at, item.at + transition.duration]
        }.flatMap { $0 }
        let boundaries = Set(
            [0, project.duration] + allItems.flatMap { [$0.at, $0.end] } + transitionBoundaries
        ).sorted()
        var instructions: [FrameInstruction] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            var layers: [VisualLayer] = []
            for track in project.tracks where !track.isHidden {
                if track.kind == "video" {
                    layers.append(
                        contentsOf: (visualByTrack[track.id] ?? [])
                            .filter { $0.start <= start && $0.end > start }
                            .map { .video($0.layer) })
                } else if track.isAdjustment {
                    for item in track.items where item.at <= start && item.end > start {
                        layers.append(.adjustment(AdjustmentLayer(properties: item.fields, lut: try loadLUT(for: item))))
                    }
                } else if track.kind == "text" {
                    layers.append(
                        contentsOf: track.items.filter { $0.at <= start && $0.end > start }.map {
                            .text($0)
                        })
                }
            }
            instructions.append(
                FrameInstruction(
                    range: CMTimeRange(
                        start: project.fps.time(start), duration: project.fps.time(end - start)),
                    layers: layers))
        }
        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = BashCutCompositor.self
        video.renderSize = CGSize(width: project.width, height: project.height)
        video.frameDuration = project.fps.time(1)
        video.instructions = instructions
        let audio = AVMutableAudioMix()
        audio.inputParameters = audioParameters
        return CompositionSnapshot(composition: composition, videoComposition: video, audioMix: audio)
    }
    /// The asset at `url` with its tracks loaded, opened once and reused while the file is unchanged.
    /// A speed ramp as pieces of about two timeline frames, each inserted from its stretch of source and scaled
    /// to its length. Piece boundaries are exact in a fine timescale so the pieces butt with no gap.
    static func insertRamp(
        _ item: Item, media: Media, fps: FrameRate, from source: AVAssetTrack, into target: AVMutableCompositionTrack
    ) throws {
        guard let curve = item.speedCurve else { return }
        let scale: CMTimeScale = 600_000
        func time(_ seconds: Double) -> CMTime { CMTime(value: CMTimeValue((seconds * Double(scale)).rounded()), timescale: scale) }
        let pieces = max(2, min(240, item.duration / 2))
        let clipSeconds = Double(item.duration) / fps.value
        let sourceStart = Double(item.sourceIn) / media.fps.value
        let start = Double(item.at) / fps.value
        for piece in 0..<pieces {
            let from = Double(piece) / Double(pieces), to = Double(piece + 1) / Double(pieces)
            let sourceFrom = time(sourceStart + curve.integral(to: from) * clipSeconds)
            let sourceTo = time(sourceStart + curve.integral(to: to) * clipSeconds)
            let destinationFrom = time(start + from * clipSeconds)
            let destinationTo = time(start + to * clipSeconds)
            let sourceRange = CMTimeRange(start: sourceFrom, end: sourceTo)
            guard sourceRange.duration > .zero else { continue }
            try target.insertTimeRange(sourceRange, of: source, at: destinationFrom)
            target.scaleTimeRange(
                CMTimeRange(start: destinationFrom, duration: sourceRange.duration),
                toDuration: destinationTo - destinationFrom)
        }
    }

    private func loadedAsset(_ url: URL) async throws -> LoadedAsset {
        let signature = FileSignature(url)
        if let cached = assets[url], cached.signature == signature {
            assetOrder.removeAll { $0 == url }
            assetOrder.append(url)
            return cached
        }
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let loaded = LoadedAsset(
            asset: asset, signature: signature, video: video, audio: audio,
            naturalSize: try await video?.load(.naturalSize) ?? .zero,
            preferredTransform: try await video?.load(.preferredTransform) ?? .identity)
        assetLoads += 1
        assets[url] = loaded
        assetOrder.removeAll { $0 == url }
        assetOrder.append(url)
        while assetOrder.count > cacheLimit { assets.removeValue(forKey: assetOrder.removeFirst()) }
        return loaded
    }

    private func audioMixParameters(
        item: Item, sourceTrack: Track, track: AVCompositionTrack, fps: FrameRate,
        envelope: (speech: [Range<Int>], mixGainDb: Double)
    )
        -> AVAudioMixInputParameters
    {
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTimePitchAlgorithm =
            item["preservePitch"] == .bool(false) ? .varispeed : .spectral
        let points = AudioGainPlanner.points(
            for: item, on: sourceTrack, speech: envelope.speech, mixGainDb: envelope.mixGainDb)
        if let first = points.first { parameters.setVolume(first.volume, at: fps.time(first.frame)) }
        for (start, end) in zip(points, points.dropFirst()) where end.frame > start.frame {
            parameters.setVolumeRamp(
                fromStartVolume: start.volume, toEndVolume: end.volume,
                timeRange: CMTimeRange(
                    start: fps.time(start.frame), duration: fps.time(end.frame - start.frame)))
        }
        return parameters
    }

}

/// An opened asset with what the builder needs from it, valid while the file keeps its `signature`.
private struct LoadedAsset {
    /// Kept alive with its tracks: a track stops working once its asset is released.
    let asset: AVURLAsset
    let signature: FileSignature
    let video: AVAssetTrack?
    let audio: AVAssetTrack?
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
}

/// Modification date and size of a file; a change means the cached asset is stale.
private struct FileSignature: Equatable {
    let modified: Date?
    let size: Int?

    init(_ url: URL) {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        modified = values?.contentModificationDate
        size = values?.fileSize
    }
}

private struct PlacedVisual {
    let start: Int
    let end: Int
    let layer: FrameLayer
}
