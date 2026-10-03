import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

struct AudioLaneTests {
    private func project(_ items: [Item]) throws -> Project {
        let media = Media(fields: [
            "id": .string("audio"), "path": .string("test.mp4"), "fps": FrameRate().json, "frames": .integer(59)
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
        let project = try project([first, second, third, fourth])
        let snapshot = try await CompositionBuilder().build(project, root: TestFixtures.mediaRoot)
        #expect(snapshot.audioMix.inputParameters.count == 2)
        let parameters = try #require(snapshot.audioMix.inputParameters.first)
        #expect(parameters.audioTimePitchAlgorithm == .spectral)
        #expect(snapshot.audioMix.inputParameters.last?.audioTimePitchAlgorithm == .varispeed)
        var start: Float = 0, end: Float = 0
        var range = CMTimeRange.invalid
        #expect(parameters.getVolumeRamp(for: project.fps.time(12), startVolume: &start, endVolume: &end, timeRange: &range))
        #expect(start == 1 && end == 0)
        #expect(parameters.getVolumeRamp(for: project.fps.time(15), startVolume: &start, endVolume: &end, timeRange: &range))
        #expect(abs(start - 0.1) < 0.0001 && abs(end - 0.1) < 0.0001)
        #expect(range.start == project.fps.time(15))
        #expect(parameters.getVolumeRamp(for: project.fps.time(60), startVolume: &start, endVolume: &end, timeRange: &range))
        #expect(abs(start - 0.501_187) < 0.0001 && abs(end - 0.501_187) < 0.0001)
        let lane = try #require(snapshot.composition.track(withTrackID: parameters.trackID))
        let gap = CMTimeRange(start: project.fps.time(30), duration: project.fps.time(30))
        #expect(lane.segments.contains { $0.isEmpty && $0.timeMapping.target == gap })
    }

    @Test("Overlapping project layers retain independent audio tracks")
    func overlappingLayers() async throws {
        let base = try project([Item(id: "music", media: "audio", at: 0, duration: 30)])
        let overlapping = try base.applying(.insert(track: "a2", item: Item(id: "voice", media: "audio", at: 0, duration: 30))).project
        let snapshot = try await CompositionBuilder().build(overlapping, root: TestFixtures.mediaRoot)
        #expect(snapshot.audioMix.inputParameters.count == 2)
        #expect(snapshot.composition.tracks.filter { $0.mediaType == .audio }.count == 2)
    }

    @Test("Decoded PCM retains a -20 dB gain step across a reused lane boundary")
    func renderedGain() async throws {
        let first = Item(id: "first", media: "audio", at: 0, duration: 15)
        var second = Item(id: "second", media: "audio", at: 15, duration: 15)
        second["volumeDb"] = .integer(-20)
        let snapshot = try await CompositionBuilder().build(project([first, second]), root: TestFixtures.mediaRoot)
        let reader = try AVAssetReader(asset: snapshot.composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: snapshot.composition.tracks.filter { $0.mediaType == .audio }, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ])
        output.audioMix = snapshot.audioMix
        reader.add(output)
        #expect(reader.startReading())
        var energy = [Double](repeating: 0, count: 2)
        var counts = [Int](repeating: 0, count: 2)
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
                let bin = (0.05..<0.25).contains(time) ? 0 : (0.55..<0.75).contains(time) ? 1 : -1
                if bin >= 0 { energy[bin] += Double(value * value); counts[bin] += 1 }
            }
        }
        #expect(reader.status == .completed)
        #expect(counts.allSatisfy { $0 > 9_000 })
        let ratio = sqrt((energy[1] / Double(counts[1])) / (energy[0] / Double(counts[0])))
        #expect(abs(ratio - 0.1) < 0.005)
    }

    @Test("Sequential audio cuts share a lane")
    @MainActor func sequential() async throws {
        let project = try project((0..<240).map { Item(id: "a-\($0)", media: "audio", at: $0, duration: 1) })
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
            player.play()
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
