import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

struct AudioLaneTests {
    private func project(_ items: [Item], mediaPath: String = "test.mp4") async throws -> Project {
        _ = try await TestFixtures.requireVideo()
        let media = Media(fields: [
            "id": .string("audio"), "path": .string(mediaPath), "fps": FrameRate().json, "frames": .integer(59)
        ])
        return try Project(name: "Audio lanes").applying(.group(label: "Fixture", author: .user, ops:
            [.addMedia(media)] + items.map { .insert(track: "a3", item: $0) })).project
    }

    @Test("Adjacent cuts reset gain and fades; different pitch algorithms cannot share a lane")
    func gainAndPitch() async throws {
        var first = Item(id: "first", media: "audio", at: 0, duration: 15)
        first["fadeOut"] = .integer(5)
        var second = Item(id: "second", media: "audio", at: 15, duration: 15)
        second["volumeDb"] = .integer(-20)
        var third = Item(id: "third", media: "audio", at: 35, duration: 15)
        third["preservePitch"] = .bool(false)
        var fourth = Item(id: "fourth", media: "audio", at: 60, duration: 15)
        fourth["volumeDb"] = .integer(-6)
        let project = try await project([first, second, third, fourth])
        let snapshot = try await CompositionBuilder().build(project, root: TestFixtures.mediaRoot)
        #expect(snapshot.audioMix.inputParameters.count == 3)
        let parameters = try #require(snapshot.audioMix.inputParameters.first)
        #expect(parameters.audioTimePitchAlgorithm == .spectral)
        #expect(snapshot.audioMix.inputParameters.last?.audioTimePitchAlgorithm == .varispeed)
        var start: Float = 0, end: Float = 0
        var range = CMTimeRange.invalid
        #expect(parameters.getVolumeRamp(for: project.fps.time(12), startVolume: &start, endVolume: &end, timeRange: &range))
        #expect(start == 1 && end == 0)
        let secondParameters = snapshot.audioMix.inputParameters[1]
        #expect(secondParameters.getVolumeRamp(for: project.fps.time(15), startVolume: &start, endVolume: &end, timeRange: &range))
        #expect(abs(start - 0.1) < 0.0001 && abs(end - 0.1) < 0.0001)
        #expect(range.start == project.fps.time(15))
        #expect(parameters.getVolumeRamp(for: project.fps.time(60), startVolume: &start, endVolume: &end, timeRange: &range))
        #expect(abs(start - 0.501_187) < 0.0001 && abs(end - 0.501_187) < 0.0001)
        let lane = try #require(snapshot.composition.track(withTrackID: parameters.trackID))
        let gap = CMTimeRange(start: project.fps.time(15), duration: project.fps.time(45))
        #expect(lane.segments.contains { $0.isEmpty && $0.timeMapping.target == gap })
    }

    @Test("Overlapping project layers retain independent audio tracks")
    func overlappingLayers() async throws {
        let base = try await project([Item(id: "music", media: "audio", at: 0, duration: 30)])
        let overlapping = try base.applying(.insert(track: "a2", item: Item(id: "voice", media: "audio", at: 0, duration: 30))).project
        let snapshot = try await CompositionBuilder().build(overlapping, root: TestFixtures.mediaRoot)
        #expect(snapshot.audioMix.inputParameters.count == 2)
        #expect(snapshot.composition.tracks.filter { $0.mediaType == .audio }.count == 2)
    }

    @Test("Decoded gain steps survive lane reuse with AAC/PCM and both pitch algorithms", arguments: [false, true], [false, true])
    func renderedGain(pcm: Bool, preservesPitch: Bool) async throws {
        try await expectRenderedGains(pcm: pcm, preservesPitch: preservesPitch, gap: 0, lanes: 2)
    }

    @Test("A lane reused after a one-frame gap starts at the next cut's gain", arguments: [false, true])
    func renderedGainAfterGap(pcm: Bool) async throws {
        try await expectRenderedGains(pcm: pcm, preservesPitch: true, gap: 1, lanes: 1)
    }

    /// Four 15-frame cuts with different gains, `gap` frames apart; compares each cut's RMS with the first.
    private func expectRenderedGains(pcm: Bool, preservesPitch: Bool, gap: Int, lanes: Int) async throws {
        _ = try await TestFixtures.requireVideo()
        let source = TestFixtures.mediaRoot.appendingPathComponent("gain-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: source) }
        if pcm { try TestFixtures.writeTone(to: source, seconds: 2.002) }
        let gains = [0.0, -20.0, -6.0, -14.0]
        let items = gains.enumerated().map { index, gain in
            var item = Item(id: "cut-\(index)", media: "audio", at: index * (15 + gap), duration: 15)
            item["volumeDb"] = .number(gain)
            item["preservePitch"] = .bool(preservesPitch)
            return item
        }
        let timeline = try await project(items, mediaPath: pcm ? source.lastPathComponent : "test.mp4")
        let snapshot = try await CompositionBuilder().build(timeline, root: TestFixtures.mediaRoot)
        #expect(snapshot.audioMix.inputParameters.count == lanes)
        let starts = items.map { Double($0.at) / timeline.fps.value }
        let (energy, counts) = try decodedEnergy(snapshot, windows: starts.map { ($0 + 0.05)..<($0 + 0.25) })
        #expect(counts.allSatisfy { $0 > 9_000 })
        for bin in gains.indices.dropFirst() {
            let ratio = sqrt((energy[bin] / Double(counts[bin])) / (energy[0] / Double(counts[0])))
            #expect(abs(ratio - pow(10, gains[bin] / 20)) < 0.005, "cut \(bin)")
        }
    }

    /// Mixed mono PCM energy and sample count inside each time window (seconds).
    private func decodedEnergy(_ snapshot: CompositionSnapshot, windows: [Range<Double>]) throws -> ([Double], [Int]) {
        let reader = try AVAssetReader(asset: snapshot.composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: snapshot.composition.tracks.filter { $0.mediaType == .audio }, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ])
        output.audioMix = snapshot.audioMix
        reader.add(output)
        #expect(reader.startReading())
        var energy = [Double](repeating: 0, count: windows.count)
        var counts = [Int](repeating: 0, count: windows.count)
        while let buffer = output.copyNextSampleBuffer() {
            let block = try #require(CMSampleBufferGetDataBuffer(buffer))
            var samples = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes {
                guard let address = $0.baseAddress else { return OSStatus(-1) }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: address)
            }
            #expect(status == kCMBlockBufferNoErr)
            let start = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            for (index, value) in samples.enumerated() {
                let time = start + Double(index) / 48_000
                for (bin, window) in windows.enumerated() where window.contains(time) {
                    energy[bin] += Double(value * value)
                    counts[bin] += 1
                }
            }
        }
        #expect(reader.status == .completed)
        return (energy, counts)
    }

    /// AVFoundation's audio mix output stopped answering when a clip it time-scales joined the cut before it on one
    /// lane: an export froze at 17.3 s once two clips went from -60 dB to the -96 dB of their neighbours, since equal
    /// gains let the cuts share a lane. Here a one-frame cut is followed at the same gain by AAC sound at 1.5×. An
    /// export renders that sound offline (`HighSpeedAudioTests`), so the preview build is the one that still scales it.
    @Test("A sped-up clip right after a cut at the same gain gets its own lane and exports", arguments: [-96.0, 0])
    func scaledAfterTouchingCut(gainDb: Double) async throws {
        let root = try TestFixtures.temporaryDirectory("scaled-join")
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.writeTone(to: root.appendingPathComponent("tone.m4a"), seconds: 12, channels: 2, aac: true)
        try TestFixtures.writeTone(to: root.appendingPathComponent("lead.caf"), seconds: 2, channels: 2)
        let fps = FrameRate(30, 1)
        let media = [
            Media(fields: ["id": .string("tone"), "kind": .string("audio"), "path": .string("tone.m4a"),
                           "fps": FrameRate().json, "frames": .integer(359)]),
            Media(fields: ["id": .string("lead"), "kind": .string("audio"), "path": .string("lead.caf"),
                           "fps": fps.json, "frames": .integer(60)]),
        ]
        var lead = Item(id: "lead", media: "lead", at: 0, duration: 1)
        lead["volumeDb"] = .number(gainDb)
        var fast = Item(id: "fast", media: "tone", at: 1, duration: 99, sourceIn: 14)
        fast["speed"] = .number(1.5)
        fast["volumeDb"] = .number(gainDb)
        let project = try Project(name: "Scaled join", fps: fps).applying(.group(label: "Fixture", author: .user, ops:
            media.map { .addMedia($0) } + [.insert(track: "a3", item: lead), .insert(track: "a3", item: fast)])).project
        let snapshot = try await AVFoundationRenderEngine(source: OriginalMediaSource())
            .build(project, root: root, purpose: .preview)
        #expect(snapshot.audioMix.inputParameters.count == 2)
        let file = root.appendingPathComponent("mix.caf")
        let export = Task { try await Exporter().exportAudio(snapshot, to: file) }
        let finished = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { _ = try await export.value; return true }
            group.addTask { try await Task.sleep(for: .seconds(20)); return false }
            let first = try await group.next() ?? false
            group.cancelAll()
            export.cancel()
            return first
        }
        try #require(finished, "The audio export stalled")
        let seconds = Double(try AVAudioFile(forReading: file).length) / 48_000
        #expect(abs(seconds - 100.0 / 30) < 0.05)
    }

    @Test("Sequential audio cuts share a lane")
    @MainActor func sequential() async throws {
        let project = try await project((0..<240).map { Item(id: "a-\($0)", media: "audio", at: $0, duration: 1) })
        let builder = CompositionBuilder()
        var times: [Double] = []
        var tracks = 0
        var readyTimes: [Double] = []
        for _ in 0..<3 {
            let start = ContinuousClock.now
            let snapshot = try await builder.build(project, root: TestFixtures.mediaRoot)
            let elapsed = start.duration(to: .now).components
            times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            tracks = snapshot.composition.tracks.filter { $0.mediaType == .audio }.count
            let item = AVPlayerItem(asset: snapshot.composition)
            item.audioMix = snapshot.audioMix
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            // Measure paused readiness, as preview preparation does. Starting/stopping the audio device
            // here can leave subsequent items evaluating their buffer instead of measuring construction.
            let deadline = ContinuousClock.now + .seconds(5)
            while item.status == .unknown, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(1))
            }
            player.pause()
            #expect(item.status == .readyToPlay)
            let ready = start.duration(to: .now).components
            readyTimes.append(Double(ready.seconds) * 1000 + Double(ready.attoseconds) / 1e15)
        }
        #expect(tracks == 1)
        TestMeasurement.report("AUDIO_LANES median_ms=\(times.sorted()[1]) tracks=\(tracks) build_to_ready_ms=\(readyTimes.sorted()[1])")
    }
}
