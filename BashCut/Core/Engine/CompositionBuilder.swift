@preconcurrency import AVFoundation
import BashCutProject

public struct CompositionSnapshot: @unchecked Sendable {
    public let composition: AVComposition
    public let videoComposition: AVVideoComposition
    public let audioMix: AVAudioMix
}

public actor CompositionBuilder {
    public init() {}

    // This coordinates media loading, video lanes, audio parameters and frame instructions.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func build(_ project: Project, root: URL, workspace: URL? = nil) async throws
        -> CompositionSnapshot
    {
        try project.validate()
        guard project.duration > 0 else { throw ProjectError.invalid("Timeline is empty") }
        let composition = AVMutableComposition()
        var visualByTrack: [String: [PlacedVisual]] = [:]
        var visualLanes: [String: [(end: Int, target: AVMutableCompositionTrack)]] = [:]
        var assetCache: [URL: AVURLAsset] = [:]
        var audioParameters: [AVAudioMixInputParameters] = []
        let speechRanges = AudioGainPlanner.speechRanges(in: project)
        var lutCache: [String: CubeLUT] = [:]
        let transitionFrom = Dictionary(uniqueKeysWithValues: project.transitions.map { ($0.fromItemID, $0) })
        let transitionTo = Dictionary(uniqueKeysWithValues: project.transitions.map { ($0.toItemID, $0) })
        for track in project.tracks where track.kind != "text" {
            for item in track.items.sorted(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
                try Task.checkCancellation()
                guard let media = project.media.first(where: { $0.id == item.mediaID }) else { continue }
                let url = try MediaPathResolver.resolve(
                    media.path, projectRoot: root, workspaceRoot: workspace)
                let asset: AVURLAsset
                if let cached = assetCache[url] {
                    asset = cached
                } else {
                    let created = AVURLAsset(url: url)
                    assetCache[url] = created
                    asset = created
                }
                let freezeFrame = item["freezeFrame"]?.int
                let normalSourceRange = CMTimeRange(
                    start: media.fps.time(item.sourceIn),
                    duration: CMTimeMultiplyByFloat64(
                        project.fps.time(item.duration), multiplier: item.speed))
                let videoSourceRange = freezeFrame.map {
                    CMTimeRange(start: media.fps.time($0), duration: media.fps.time(1))
                } ?? normalSourceRange
                let destination = project.fps.time(item.at)
                if track.kind == "video" {
                    guard let source = try await asset.loadTracks(withMediaType: .video).first else {
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
                    try target.insertTimeRange(videoSourceRange, of: source, at: destination)
                    target.scaleTimeRange(
                        CMTimeRange(start: destination, duration: videoSourceRange.duration),
                        toDuration: project.fps.time(item.duration))
                    let naturalSize = try await source.load(.naturalSize)
                    let preferred = try await source.load(.preferredTransform)
                    let rect = CGRect(origin: .zero, size: naturalSize).applying(preferred)
                    let properties = item["transform"]?.object ?? [:]
                    let zoom = properties["zoom"]?.double ?? 1
                    let scale =
                        max(Double(project.width) / rect.width, Double(project.height) / rect.height) * zoom
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
                    let lut: CubeLUT?
                    if let lutID = item["color"]?.object["lut"]?.string,
                        let catalog = project.colorLUTs.first(where: { $0.id == lutID })
                    {
                        if let cached = lutCache[lutID] {
                            lut = cached
                        } else {
                            let directory = root.appendingPathComponent("luts").resolvingSymlinksInPath()
                            let lutURL = root.appendingPathComponent(catalog.path).resolvingSymlinksInPath()
                            guard lutURL.path.hasPrefix(directory.path + "/") else {
                                throw ProjectError.invalid("LUT escapes the project luts folder")
                            }
                            let loaded = try CubeLUT.load(lutURL)
                            guard loaded.dimension == catalog.size else {
                                throw ProjectError.invalid("LUT size changed on disk")
                            }
                            lutCache[lutID] = loaded
                            lut = loaded
                        }
                    } else {
                        lut = nil
                    }
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
                        let holdRange = CMTimeRange(
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
                    if let source = try await asset.loadTracks(withMediaType: .audio).first,
                        let target = composition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid)
                    {
                        try target.insertTimeRange(normalSourceRange, of: source, at: destination)
                        target.scaleTimeRange(
                            CMTimeRange(start: destination, duration: normalSourceRange.duration),
                            toDuration: project.fps.time(item.duration))
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
            for track in project.tracks {
                if track.kind == "video" {
                    layers.append(
                        contentsOf: (visualByTrack[track.id] ?? [])
                            .filter { $0.start <= start && $0.end > start }
                            .map { .video($0.layer) })
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

private struct PlacedVisual {
    let start: Int
    let end: Int
    let layer: FrameLayer
}
