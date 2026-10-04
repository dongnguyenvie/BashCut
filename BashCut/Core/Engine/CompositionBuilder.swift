@preconcurrency import AVFoundation
import BashCutProject

public struct CompositionSnapshot: @unchecked Sendable {
    public let composition: AVComposition
    public let videoComposition: AVVideoComposition
    public let audioMix: AVAudioMix
    /// Identifies the composition's tracks and what each plays where (`CompositionBuilder.structure`). Two
    /// snapshots with the same value differ only in their video composition and audio mix, so a player can take the
    /// new ones without loading the composition again. Nil: unknown, never reused.
    public let structure: Int?

    public init(
        composition: AVComposition, videoComposition: AVVideoComposition, audioMix: AVAudioMix, structure: Int? = nil
    ) {
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        self.structure = structure
    }
}

/// Builds compositions from project snapshots. One builder lives as long as its engine, so the assets it
/// opened (and their loaded tracks) are reused by later builds until the file on disk changes.
public actor CompositionBuilder {
    private let source: any MediaSource
    private let previewAssets: AssetCache
    private let exportAssets: AssetCache
    private var parsedLUTs = LUTCache()
    private var rampPlans = SpeedRampPlans()
    private let rampAudio = SpeedRampAudioCache()
    public var rampAudioRenders: Int { get async { await rampAudio.renders } }
    public var rampPlanBuilds: Int { rampPlans.builds }
    public var lutLoads: Int { parsedLUTs.loads }
    /// Assets opened from disk across both purpose-specific caches; cache hits do not count.
    public var assetLoads: Int { get async { await previewAssets.loads + exportAssets.loads } }

    public init(source: any MediaSource = ProxyMediaSource(), cacheLimit: Int = 64) {
        self.source = source
        previewAssets = AssetCache(minimumCapacity: cacheLimit)
        exportAssets = AssetCache(minimumCapacity: cacheLimit)
    }

    public var cachedAssetCount: Int { get async { await previewAssets.count + exportAssets.count } }

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
        let assets = purpose == .preview ? previewAssets : exportAssets
        let activeItems = project.tracks.flatMap(\.items)
        await assets.resize(for: Set(activeItems.compactMap(\.mediaID)).count + activeItems.filter { $0.speedCurve != nil }.count)
        let composition = AVMutableComposition()
        var visualByTrack: [String: [PlacedVisual]] = [:]
        var visualLanes = VideoCompositionLanes()
        var audioLanes = AudioCompositionLanes()
        let speechRanges = AudioGainPlanner.speechRanges(in: project)
        var lutCache: [String: CubeLUT] = [:]
        let lutCatalog = Dictionary(uniqueKeysWithValues: project.colorLUTs.map { ($0.id, $0) })
        /// The LUT an item's `color.lut` names, loaded once per build from the project `luts` folder.
        func loadLUT(for item: Item) throws -> CubeLUT? {
            guard let lutID = item["color"]?.object["lut"]?.string else { return nil }
            if let cached = lutCache[lutID] { return cached }
            guard let catalog = lutCatalog[lutID] else { return nil }
            let directory = root.appendingPathComponent("luts").resolvingSymlinksInPath()
            let lutURL = root.appendingPathComponent(catalog.path).resolvingSymlinksInPath()
            guard lutURL.path.hasPrefix(directory.path + "/") else {
                throw ProjectError.invalid("LUT escapes the project luts folder")
            }
            let loaded = try parsedLUTs.load(lutURL, dimension: catalog.size)
            lutCache[lutID] = loaded
            return loaded
        }
        let mediaByID = Dictionary(uniqueKeysWithValues: project.media.map { ($0.id, $0) })
        let allItems = project.tracks.flatMap(\.items)
        let itemsByID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        rampPlans.retain(Set(itemsByID.keys))
        // One source decision, still conversion and asset signature check per media in this snapshot.
        // Keep this local: a later build must discover newly created proxies or replaced originals.
        var loadedMedia: [String: LoadedAsset] = [:]
        let transitionFrom = Dictionary(uniqueKeysWithValues: project.transitions.map { ($0.fromItemID, $0) })
        let transitionTo = Dictionary(uniqueKeysWithValues: project.transitions.map { ($0.toItemID, $0) })
        for track in project.tracks where track.kind == "video" || track.kind == "audio" {
            for item in track.items.sorted(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
                try Task.checkCancellation()
                guard let mediaID = item.mediaID, let media = mediaByID[mediaID] else { continue }
                // An image is read through its one-frame still movie and held like a freeze frame.
                let isStill = media.kind == "image"
                let asset: LoadedAsset
                if let cached = loadedMedia[mediaID] {
                    asset = cached
                } else {
                    let mediaURL = try source.url(for: media, root: root, workspace: workspace, purpose: purpose)
                    asset = try await assets.load(
                        isStill ? StillImageMovie.movie(for: media, image: mediaURL, root: root) : mediaURL)
                    loadedMedia[mediaID] = asset
                }
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
                let ramp = rampPlans.plan(for: item, mediaFPS: media.fps, fps: project.fps)
                if track.kind == "video" {
                    guard let source = asset.video else {
                        throw ProjectError.invalid("No video track in \(media.path)")
                    }
                    let target = try visualLanes.take(
                        layer: track.id, start: item.at, end: item.end, composition: composition)
                    if freezeFrame == nil, !isStill, let ramp {
                        try ramp.insert(from: source, into: target)
                    } else {
                        try target.insertTimeRange(videoSourceRange, of: source, at: destination)
                        target.scaleTimeRange(
                            CMTimeRange(start: destination, duration: videoSourceRange.duration),
                            toDuration: project.fps.time(item.duration))
                    }
                    let preferred = asset.preferredTransform
                    let rect = CGRect(origin: .zero, size: asset.naturalSize).applying(preferred)
                    let properties = item["transform"]?.object ?? [:]
                    let canvas = CGSize(width: project.width, height: project.height)
                    let placement = ClipPlacement(
                        orientation: preferred.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY)),
                        size: rect.size, baseScale: Self.baseScale(source: rect.size, canvas: canvas, fill: project.fills(item)),
                        canvas: canvas)
                    let transform = placement.transform(
                        zoom: properties["zoom"]?.double ?? 1, pan: properties["pan"]?.double ?? 0,
                        tilt: properties["tilt"]?.double ?? 0, rotation: properties["rotation"]?.double ?? 0)
                    let motion = item.pictureMotion.map { LayerMotion(motion: $0, item: item, fps: project.fps.value) }
                    let incoming = transitionTo[item.id].map {
                        RenderTransition(
                            kind: $0.kind, startFrame: item.at, duration: $0.duration,
                            incoming: true, fps: project.fps.value)
                    }
                    let lut = try loadLUT(for: item)
                    let crop = SourceCrop(
                        fields: item.fields, naturalSize: asset.naturalSize, orientation: placement.orientation)
                    visualByTrack[track.id, default: []].append(
                        PlacedVisual(
                            start: item.at, end: item.end,
                            layer: FrameLayer(
                                trackID: target.trackID, transform: transform,
                                properties: item.fields, transition: incoming, lut: lut,
                                motion: motion.map { ($0, placement) }, crop: crop)))
                    if let transition = transitionFrom[item.id] {
                        let hold = try visualLanes.take(
                            layer: track.id, start: item.end, end: item.end + transition.duration, composition: composition)
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
                                        fps: project.fps.value), lut: lut,
                                    motion: motion.map { ($0, placement) }, crop: crop)))
                    }
                }
                // Main sound remains attached in the spike until separate linked dialogue editing lands.
                if track.kind == "audio" || (track.role == "main" && item["linkedAudio"] == nil) {
                    if let source = asset.audio {
                        let gain = AudioGainPlanner.points(
                            for: item, on: track, speech: speechRanges, mixGainDb: project.mixGainDb)
                        let lane = try audioLanes.take(for: item, sourceTrack: track.id, gain: gain, composition: composition)
                        let target = lane.track
                        if ramp != nil {
                            let url = try await rampAudio.render(asset: asset, item: item, mediaFPS: media.fps, fps: project.fps, root: root)
                            let rendered = try await assets.load(url)
                            guard let audio = rendered.audio else { throw ProjectError.invalid("Missing rendered ramp audio") }
                            try target.insertTimeRange(
                                CMTimeRange(start: .zero, duration: project.fps.time(item.duration)), of: audio, at: destination)
                        } else {
                            try target.insertTimeRange(normalSourceRange, of: source, at: destination)
                            target.scaleTimeRange(
                                CMTimeRange(start: destination, duration: normalSourceRange.duration),
                                toDuration: project.fps.time(item.duration))
                        }
                        applyAudioMixParameters(gain, parameters: lane.parameters, fps: project.fps)
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
        let transitionBoundaries = project.transitions.compactMap { transition -> [Int]? in
            guard let item = itemsByID[transition.toItemID] else { return nil }
            return [item.at, item.at + transition.duration]
        }.flatMap { $0 }
        let boundaries = Set(
            [0, project.duration] + allItems.flatMap { [$0.at, $0.end] } + transitionBoundaries
        ).sorted()
        // Make each layer once, in its original compositing order. Sweep boundaries rather than scanning
        // every track's items again for each caption-sized segment.
        var timedLayers: [(start: Int, end: Int, value: VisualLayer)] = []
        for track in project.tracks where !track.isHidden {
            if track.kind == "video" {
                timedLayers += (visualByTrack[track.id] ?? []).map { ($0.start, $0.end, .video($0.layer)) }
            } else if track.isAdjustment {
                for item in track.items {
                    let layer = AdjustmentLayer(properties: item.fields, lut: try loadLUT(for: item))
                    timedLayers.append((item.at, item.end, .adjustment(layer)))
                }
            } else if track.kind == "text" {
                for item in track.items {
                    let layer = TextLayer(item: item, motion: item.pictureMotion.map {
                        LayerMotion(motion: $0, item: item, fps: project.fps.value)
                    }, fps: project.fps.value)
                    timedLayers.append((item.at, item.end, .text(layer)))
                }
            }
        }
        var sweep = IntervalSweep(timedLayers)
        var instructions: [FrameInstruction] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            instructions.append(
                FrameInstruction(
                    range: CMTimeRange(
                        start: project.fps.time(start), duration: project.fps.time(end - start)),
                    layers: sweep.values(at: start)))
        }
        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = BashCutCompositor.self
        video.renderSize = CGSize(width: project.width, height: project.height)
        video.frameDuration = project.fps.time(1)
        video.instructions = instructions
        let audio = AVMutableAudioMix()
        audio.inputParameters = audioLanes.parameters
        return CompositionSnapshot(
            composition: composition, videoComposition: video, audioMix: audio, structure: Self.structure(of: composition))
    }

    /// A hash of every track (ID and media type) and segment (source file and its state on disk, source track, source
    /// and target time ranges). Edits that keep it (colour, text, opacity, transform, keyframes, volume, fades) change
    /// only the instructions and the audio mix.
    static func structure(of composition: AVComposition) -> Int {
        var hasher = Hasher()
        var files: [URL: FileSignature] = [:]
        func add(_ time: CMTime) {
            hasher.combine(time.value)
            hasher.combine(time.timescale)
        }
        for track in composition.tracks {
            hasher.combine(track.trackID)
            hasher.combine(track.mediaType.rawValue)
            for segment in track.segments {
                hasher.combine(segment.isEmpty)
                if let url = segment.sourceURL {
                    hasher.combine(url)
                    let signature = files[url] ?? FileSignature(url)
                    files[url] = signature
                    hasher.combine(signature.modified)
                    hasher.combine(signature.size)
                    hasher.combine(signature.inode)
                }
                hasher.combine(segment.sourceTrackID)
                let mapping = segment.timeMapping
                for range in [mapping.source, mapping.target] {
                    add(range.start)
                    add(range.duration)
                }
            }
        }
        return hasher.finalize()
    }
    private func applyAudioMixParameters(
        _ points: [AudioGainPoint], parameters: AVMutableAudioMixInputParameters, fps: FrameRate
    ) {
        if let first = points.first { parameters.setVolume(first.volume, at: fps.time(first.frame)) }
        for (start, end) in zip(points, points.dropFirst()) where end.frame > start.frame {
            parameters.setVolumeRamp(
                fromStartVolume: start.volume, toEndVolume: end.volume,
                timeRange: CMTimeRange(
                    start: fps.time(start.frame), duration: fps.time(end.frame - start.frame)))
        }
    }

}

private struct PlacedVisual {
    let start: Int
    let end: Int
    let layer: FrameLayer
}
