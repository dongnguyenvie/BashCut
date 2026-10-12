import AVFoundation
import BashCutProject
import BashCutTestSupport
import Testing

@testable import BashCutEngine

/// A clip at another rate with no animation came out of the composition at its own rate, so a 30 fps export of a
/// 24 fps clip was variable frame rate with a fifth of its frames missing (#507-1).
struct ConstantFrameRateExportTests {
    @Test("A 24 fps clip with no animation exports one picture on every project frame")
    func otherRateClip() async throws {
        let directory = try TestFixtures.temporaryDirectory("constant-rate")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("film.mov")
        try await SourceEdgeMovie.write(
            .init(pictures: 72, frame: CMTime(value: 1, timescale: 24), audioSeconds: 3), to: source)
        let media = try await SourceEdgeMovie.media(source, count: .pictures)
        let project = try Project(name: "Constant rate").applying(
            .group(label: "Fixture", author: .user, ops: [
                .addMedia(media),
                .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: 60)),
            ])).project
        let snapshot = try await CompositionBuilder().build(project, root: directory)
        let output = directory.appendingPathComponent("export.mp4")
        try await Exporter().export(snapshot, to: output, settings: ExportSettings(preset: .quickDraft))
        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let times = try DeliveredQC.frameTimes(asset, track: track).sorted()
        #expect(times.count == 60)
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        // The file's 1/600 timescale writes a 29.97 fps frame as 20 or 21 ticks; a 24 fps picture would be 25.
        #expect(gaps.allSatisfy { $0 < 21.5 / 600 }, "\(gaps)")
    }

    @Test("A held picture at the end is written on every frame up to the timeline's end")
    func heldEnd() {
        let frame = CMTime(value: 1, timescale: 30)
        let grid = ConstantFrames(end: CMTimeMultiply(frame, multiplier: 10), frame: frame)
        var pending = [Self.sample(at: .zero), Self.sample(at: CMTimeMultiply(frame, multiplier: 3))]
        var written: [CMTime] = []
        while let sample = grid.next({ pending.isEmpty ? nil : pending.removeFirst() }) {
            written.append(sample.presentationTimeStamp)
        }
        #expect(written == (0..<10).map { CMTimeMultiply(frame, multiplier: Int32($0)) })
    }

    private static func sample(at time: CMTime) -> CMSampleBuffer {
        var format: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: nil, codecType: kCVPixelFormatType_32BGRA, width: 2, height: 2, extensions: nil,
            formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
        return sample!
    }
}
