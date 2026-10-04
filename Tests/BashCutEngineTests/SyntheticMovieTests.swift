import AVFoundation
import BashCutTestSupport
import Foundation
import Testing

struct SyntheticMovieTests {
    @Test("Concurrent fixture requests share a native 60-frame H264/AAC movie with audible sound")
    func nativeFixture() async throws {
        let urls = try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<8 { group.addTask { try await TestFixtures.requireVideo() } }
            var results: [URL] = []
            for try await value in group { results.append(value) }
            return results
        }
        #expect(urls.count == 8 && Set(urls) == [TestFixtures.videoURL])
        #expect(!TestFixtures.mediaRoot.path.hasPrefix(TestFixtures.repositoryRoot.path + "/"))
        let asset = AVURLAsset(url: TestFixtures.videoURL)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let audio = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        #expect(try await video.load(.naturalSize) == CGSize(width: 320, height: 180))
        #expect(abs(try await asset.load(.duration).seconds - 2.002) < 0.002)
        #expect(abs(Double(try await video.load(.nominalFrameRate)) - 30000.0 / 1001) < 0.01)
        let videoFormat = try #require(try await video.load(.formatDescriptions).first)
        let audioFormat = try #require(try await audio.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(videoFormat) == kCMVideoCodecType_H264)
        #expect(CMFormatDescriptionGetMediaSubType(audioFormat) == kAudioFormatMPEG4AAC)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(sample)
            if count > 0 {
                #expect(sample.presentationTimeStamp == CMTime(value: Int64(frames * 1001), timescale: 30000))
            }
            frames += count
        }
        #expect(reader.status == .completed && frames == 60)
        let samples = try await TestFixtures.decodeStereo(TestFixtures.videoURL)
        let rms = sqrt(samples[0].reduce(0.0) { $0 + Double($1 * $1) } / Double(samples[0].count))
        #expect(samples[0].count >= 95_000 && samples[0].count < 98_000)
        #expect(rms > 0.02 && rms < 0.2)
    }

    @Test("A cancelled fixture request does not publish a movie")
    func cancelledGeneration() async throws {
        let root = try TestFixtures.temporaryDirectory("fixture-cancelled")
        defer { try? FileManager.default.removeItem(at: root) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await SyntheticMovie.write(to: root.appendingPathComponent("movie.mp4"))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("Native fixture generation preserves an existing destination")
    func existingDestination() async throws {
        let root = try TestFixtures.temporaryDirectory("fixture-existing")
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("movie.mp4"), original = Data("existing fixture".utf8)
        try original.write(to: output)
        await #expect(throws: (any Error).self) { try await SyntheticMovie.write(to: output) }
        #expect(try Data(contentsOf: output) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["movie.mp4"])
    }
}
