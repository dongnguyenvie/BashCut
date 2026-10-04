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
        print("AUDIO_LANES median_ms=\(times.sorted()[1]) tracks=\(tracks) build_to_ready_ms=\(readyTimes.sorted()[1])")
    }
}
