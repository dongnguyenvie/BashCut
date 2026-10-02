// bashcut-bench: measures the M0 engine budgets on real footage without touching it.
//
//   swift run -c release bashcut-bench <footage-dir> [--clips 20] [--clip-seconds 1.5] [--proxies] [--keep]
//
// --proxies generates preview proxies (ProxyManager) first and measures preview playback and scrubbing
// on them, the way the editor previews heavy footage; export always reads the originals.
// Footage is only read. The project, a `footage` symlink, the report and the optional export
// live in build/bench/run-<timestamp>/. This is a developer tool, not a test: tests must never
// depend on real footage.
@preconcurrency import AVFoundation
import BashCutEngine
import BashCutProject
import Foundation
import QuartzCore

struct Options {
    var footage: URL
    var clips = 20
    var clipSeconds = 1.5
    var keep = false
    var proxies = false

    init(arguments: [String]) throws {
        var rest = arguments.dropFirst()
        guard let path = rest.popFirst(), !path.hasPrefix("--") else {
            throw BenchError("usage: bashcut-bench <footage-dir> [--clips N] [--clip-seconds S] [--proxies] [--keep]")
        }
        footage = URL(fileURLWithPath: path).standardizedFileURL
        while let flag = rest.popFirst() {
            switch flag {
            case "--clips": clips = Int(rest.popFirst() ?? "") ?? clips
            case "--clip-seconds": clipSeconds = Double(rest.popFirst() ?? "") ?? clipSeconds
            case "--keep": keep = true
            case "--proxies": proxies = true
            default: throw BenchError("unknown option \(flag)")
            }
        }
    }
}

struct BenchError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Source {
    let url: URL
    let frames: Int
    let fps: FrameRate
    let codec: String
}

// Same reframe cycle as the workspace's edl.py PUNCH table, so adjacent cuts never share a framing.
let punch: [(zoom: Double, pan: Double, tilt: Double)] = [
    (1.00, 0, 0), (1.22, 40, -30), (1.12, -40, 20), (1.28, 0, 40),
    (1.00, 0, 0), (1.18, 60, 10), (1.26, -60, -20), (1.10, 30, 30)
]

@main
enum Bench {
    static func main() async {
        do {
            let passed = try await run(Options(arguments: CommandLine.arguments))
            exit(passed ? 0 : 2)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run(_ options: Options) async throws -> Bool {
        let runDirectory = try makeRunDirectory(linking: options.footage)
        let sources = try await verticalSources(in: options.footage, count: options.clips, minimumSeconds: options.clipSeconds + 1.5)
        guard sources.count == options.clips else {
            throw BenchError("found \(sources.count) vertical clips longer than \(options.clipSeconds + 1.5) s, need \(options.clips)")
        }
        let project = try makeProject(sources, clipSeconds: options.clipSeconds)
        try project.data().write(to: runDirectory.appendingPathComponent("bench.bashcut.json"))
        print("footage   \(options.footage.path)")
        print("project   \(sources.count) clips · \(String(format: "%.2f", seconds(project.duration, project.fps))) s · "
              + "\(project.width)×\(project.height) @ \(String(format: "%.3f", project.fps.value)) fps · "
              + "source \(sources[0].codec)")

        var clock = ContinuousClock.now
        let proxySeconds = options.proxies ? try await makeProxies(project, root: runDirectory) : nil
        clock = ContinuousClock.now
        let builder = CompositionBuilder()
        let preview = try await builder.build(project, root: runDirectory, purpose: .preview)
        let buildTime = clock.duration(to: .now)
        let snapshot = try await builder.build(project, root: runDirectory, purpose: .export)
        let timelineSeconds = seconds(project.duration, project.fps)

        clock = ContinuousClock.now
        let readFrames = try await readThroughput(preview)
        let readTime = clock.duration(to: .now)
        let readFPS = Double(readFrames) / readTime.seconds

        let generatorScrub = try await scrubLatencies(preview, project: project)
        let scrub = try await playerScrubLatencies(preview, project: project)
        let playback = try await playback(preview, seconds: min(10, timelineSeconds - 1), fps: project.fps.value)

        let exportURL = runDirectory.appendingPathComponent("export.mp4")
        clock = ContinuousClock.now
        _ = try await Exporter().export(snapshot, to: exportURL)
        let exportTime = clock.duration(to: .now)
        let exported = try await AVURLAsset(url: exportURL).load(.duration).seconds
        if !options.keep { try? FileManager.default.removeItem(at: exportURL) }

        let checks: [(String, Bool, String)] = [
            ("playback", playback.dropped <= max(1, playback.expected / 100),
             "\(playback.delivered)/\(playback.expected) frames in \(String(format: "%.1f", playback.seconds)) s, "
             + "\(playback.dropped) dropped (budget ≤ 1 %)"),
            ("scrub p95", scrub.p95 < 100,
             String(format: "%.1f ms (p50 %.1f, max %.1f; AVPlayer exact seeks to a decoded frame; budget < 100 ms)",
                    scrub.p95, scrub.p50, scrub.max)),
            ("export", exportTime.seconds < timelineSeconds,
             String(format: "%.2f s for %.2f s of video = %.2f× real time (budget > 1×)",
                    exportTime.seconds, exported, timelineSeconds / exportTime.seconds))
        ]
        print("")
        if let proxySeconds {
            print(String(format: "proxies   %.1f s for %d clips (%@)", proxySeconds, sources.count,
                         "H.264 \(ProxyManager.longSide) px, keyframe every \(ProxyManager.keyframeInterval) frames"))
        }
        print("preview   \(options.proxies ? "proxies" : "originals")")
        print(String(format: "build     %.0f ms", buildTime.seconds * 1000))
        print(String(format: "generator %.1f ms p95 (p50 %.1f; AVAssetImageGenerator, zero tolerance; for reference)",
                     generatorScrub.p95, generatorScrub.p50))
        print(String(format: "decode    %.0f fps through the compositor (%d frames in %.2f s)", readFPS, readFrames, readTime.seconds))
        for (name, ok, detail) in checks {
            print("\(ok ? "PASS" : "FAIL")  \(name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(detail)")
        }
        let report: [String: Any] = [
            "footage": options.footage.path, "clips": sources.count, "timelineSeconds": timelineSeconds,
            "buildMs": buildTime.seconds * 1000, "decodeFPS": readFPS,
            "playback": ["delivered": playback.delivered, "expected": playback.expected, "dropped": playback.dropped],
            "scrubMs": ["p50": scrub.p50, "p95": scrub.p95, "max": scrub.max],
            "generatorScrubMs": ["p50": generatorScrub.p50, "p95": generatorScrub.p95, "max": generatorScrub.max],
            "preview": options.proxies ? "proxies" : "originals", "proxySeconds": proxySeconds ?? 0,
            "exportSeconds": exportTime.seconds, "machine": machineModel()
        ]
        let reportURL = runDirectory.appendingPathComponent("report.json")
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL)
        print("report    \(reportURL.path)")
        return checks.allSatisfy(\.1)
    }

    // MARK: - Setup

    static func makeRunDirectory(linking footage: URL) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/bench/run-\(stamp)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Media paths stay relative ("footage/…"), mirroring projects/<video>/footage in the workspace.
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("footage"), withDestinationURL: footage)
        return directory
    }

    static func verticalSources(in directory: URL, count: Int, minimumSeconds: Double) async throws -> [Source] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { ["mp4", "mov"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
        var found: [Source] = []
        for name in names where found.count < count {
            let url = directory.appendingPathComponent(name)
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let (size, transform, rate, descriptions) = try await track.load(.naturalSize, .preferredTransform,
                                                                              .nominalFrameRate, .formatDescriptions)
            let rect = CGRect(origin: .zero, size: size).applying(transform)
            let duration = try await asset.load(.duration).seconds
            guard abs(rect.height) > abs(rect.width), duration >= minimumSeconds else { continue }
            let fps = abs(Double(rate) - 29.97) < 0.01 ? FrameRate(30_000, 1_001) : FrameRate(Int(rate.rounded()), 1)
            let codec = descriptions.first.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "?"
            found.append(Source(url: url, frames: Int(duration * fps.value), fps: fps, codec: codec))
        }
        return found
    }

    static func makeProject(_ sources: [Source], clipSeconds: Double) throws -> Project {
        let project = Project(name: "DJI engine bench")
        let clipFrames = Int((clipSeconds * project.fps.value).rounded())
        var operations: [EditOperation] = []
        for (index, source) in sources.enumerated() {
            let id = "m-\(index)"
            operations.append(.addMedia(Media(fields: [
                "id": .string(id), "path": .string("footage/\(source.url.lastPathComponent)"),
                "kind": .string("video"), "fps": source.fps.json, "frames": .integer(source.frames)
            ])))
            let reframe = punch[index % punch.count]
            var item = Item(id: "c-\(index)", media: id, at: index * clipFrames, duration: clipFrames, sourceIn: 30)
            item["transform"] = .object(["zoom": .number(reframe.zoom), "pan": .number(reframe.pan), "tilt": .number(reframe.tilt)])
            operations.append(.insert(track: "v1", item: item))
            var caption = Item(id: "s-\(index)", at: index * clipFrames, duration: clipFrames)
            caption["text"] = .string("Clip \(index + 1) · \(source.url.deletingPathExtension().lastPathComponent.suffix(6))\n"
                                      + "Tiếng Việt: ă â đ ê ô ơ ư ỹ")
            operations.append(.insert(track: "t1", item: caption))
        }
        return try project.applying(.group(label: "Bench", author: .user, ops: operations)).project
    }

    /// Writes a proxy for every media file the way the editor does, returning the total time.
    static func makeProxies(_ project: Project, root: URL) async throws -> Double {
        let start = ContinuousClock.now
        let manager = ProxyManager()
        try await withThrowingTaskGroup(of: Void.self) { group in
            var pending = project.media[...]
            // Two at a time: the hardware encoder is shared, more in flight only adds memory.
            for _ in 0..<2 { if let media = pending.popFirst() { group.addTask { try await proxy(media) } } }
            while try await group.next() != nil {
                if let media = pending.popFirst() { group.addTask { try await proxy(media) } }
            }
            @Sendable func proxy(_ media: Media) async throws {
                guard let destination = ProxyManager.destination(for: media, root: root) else { return }
                try await manager.generate(from: root.appendingPathComponent(media.path), to: destination)
            }
        }
        return start.duration(to: .now).seconds
    }

    // MARK: - Measurements

    /// Decodes and composites every frame as fast as possible: the ceiling for playback.
    static func readThroughput(_ snapshot: CompositionSnapshot) async throws -> Int {
        let reader = try AVAssetReader(asset: snapshot.composition)
        let tracks = try await snapshot.composition.loadTracks(withMediaType: .video)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.videoComposition = snapshot.videoComposition
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? BenchError("reader did not start") }
        var frames = 0
        while output.copyNextSampleBuffer() != nil { frames += 1 }
        if reader.status == .failed { throw reader.error ?? BenchError("reader failed") }
        return frames
    }

    struct Latency { let p50: Double, p95: Double, max: Double }

    /// A paused scrub is an exact-frame seek, so tolerance is zero, at full output resolution.
    static func scrubLatencies(_ snapshot: CompositionSnapshot, project: Project) async throws -> Latency {
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var random = SplitMix(seed: 42)
        let frames = (0..<41).map { _ in Int(random.next() % UInt64(project.duration - 1)) }
        var samples: [Double] = []
        for (index, frame) in frames.enumerated() {
            let start = ContinuousClock.now
            _ = try await generator.image(at: project.fps.time(frame))
            if index > 0 { samples.append(start.duration(to: .now).seconds * 1000) } // first call warms up decoders
        }
        samples.sort()
        return Latency(p50: samples[samples.count / 2], p95: samples[Int(Double(samples.count - 1) * 0.95)],
                       max: samples.last ?? 0)
    }

    /// The viewer's path: a paused AVPlayer seeks with zero tolerance and the frame counts as shown once
    /// the item's video output has a new pixel buffer for the target time.
    @MainActor
    static func playerScrubLatencies(_ snapshot: CompositionSnapshot, project: Project) async throws -> Latency {
        let item = AVPlayerItem(asset: snapshot.composition)
        item.videoComposition = snapshot.videoComposition
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        for _ in 0..<100 where item.status != .readyToPlay {
            if item.status == .failed { throw item.error ?? BenchError("player item failed") }
            try await Task.sleep(for: .milliseconds(50))
        }
        var random = SplitMix(seed: 42)
        let frames = (0..<41).map { _ in Int(random.next() % UInt64(project.duration - 1)) }
        var samples: [Double] = []
        for (index, frame) in frames.enumerated() {
            let time = project.fps.time(frame)
            let start = ContinuousClock.now
            await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            for _ in 0..<500 where !output.hasNewPixelBuffer(forItemTime: time) {
                try await Task.sleep(for: .milliseconds(1))
            }
            _ = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
            if index > 0 { samples.append(start.duration(to: .now).seconds * 1000) }
        }
        samples.sort()
        return Latency(p50: samples[samples.count / 2], p95: samples[Int(Double(samples.count - 1) * 0.95)],
                       max: samples.last ?? 0)
    }

    struct Playback { let delivered: Int, expected: Int, dropped: Int, seconds: Double }

    /// Real-time playback through AVPlayer, the same path the viewer uses, without a window.
    @MainActor
    static func playback(_ snapshot: CompositionSnapshot, seconds: Double, fps: Double) async throws -> Playback {
        let item = AVPlayerItem(asset: snapshot.composition)
        item.videoComposition = snapshot.videoComposition
        item.audioMix = snapshot.audioMix
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        for _ in 0..<100 where item.status != .readyToPlay {
            if item.status == .failed { throw item.error ?? BenchError("player item failed") }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard item.status == .readyToPlay else { throw BenchError("player never became ready") }
        await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        // Let playback start before counting, as a user would see it.
        try await Task.sleep(for: .milliseconds(300))
        var lastFrame = -1
        var delivered = 0
        var dropped = 0
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < seconds {
            let time = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: time),
               output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) != nil {
                let frame = Int((time.seconds * fps).rounded())
                if lastFrame >= 0, frame > lastFrame + 1 { dropped += frame - lastFrame - 1 }
                if frame != lastFrame { delivered += 1 }
                lastFrame = frame
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        player.pause()
        return Playback(delivered: delivered, expected: Int(seconds * fps), dropped: dropped, seconds: seconds)
    }

    // MARK: - Helpers

    static func seconds(_ frames: Int, _ fps: FrameRate) -> Double { Double(frames) / fps.value }

    static func fourCC(_ code: FourCharCode) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii) ?? "?"
    }

    static func machineModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Deterministic seeks, so runs are comparable.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
