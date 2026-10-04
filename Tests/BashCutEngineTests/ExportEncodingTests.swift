import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing
@testable import BashCutEngine

struct ExportEncodingTests {
    @Test("H264 exports put metadata before media, retain rational FPS and bound keyframe spacing")
    func encoding() async throws {
        _ = try TestFixtures.requireVideo()
        let root = try TestFixtures.temporaryDirectory("encoding")
        defer { try? FileManager.default.removeItem(at: root) }
        let media = Media(fields: ["id": .string("m"), "path": .string("test.mp4"),
                                   "fps": FrameRate().json, "frames": .integer(59)])
        let ops: [EditOperation] = [.setFormat(width: 320, height: 180), .addMedia(media)] + (0..<5).map {
            .insert(track: "v1", item: Item(id: "c-\($0)", media: "m", at: $0 * 45, duration: 45))
        }
        let project = try Project(name: "Encoding").applying(.group(label: "Fixture", author: .user, ops: ops)).project
        let snapshot = try await CompositionBuilder().build(project, root: TestFixtures.mediaRoot)
        let url = root.appendingPathComponent("movie.mp4")
        _ = try await Exporter().export(snapshot, to: url, settings: ExportSettings(preset: .quickDraft))
        let boxes = try topLevelBoxes(Data(contentsOf: url))
        #expect(try #require(boxes.firstIndex(of: "moov")) < #require(boxes.firstIndex(of: "mdat")))
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(abs(Double(try await track.load(.nominalFrameRate)) - project.fps.value) < 0.01)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let atoms = try #require(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
            as? [String: Data])
        let avc = try #require(atoms["avcC"])
        #expect(avc.count > 3 && avc[1] == 100) // H.264 High profile_idc.
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        #expect(reader.startReading())
        var syncTimes: [Double] = []
        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(sample)
            frames += count
            guard count > 0, sample.presentationTimeStamp.isNumeric else { continue }
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
            if attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true {
                syncTimes.append(sample.presentationTimeStamp.seconds)
            }
        }
        #expect(reader.status == .completed && frames == 225)
        #expect(syncTimes.count >= 4)
        let sorted = syncTimes.sorted()
        // Leading B-pictures may present before the first sync picture. Verify decoded start coverage.
        #expect(try #require(sorted.first) <= 2.01)
        let first = try await AVAssetImageGenerator(asset: asset).image(at: .zero)
        #expect(first.actualTime.seconds <= project.fps.time(1).seconds)
        #expect(first.image.width == 320 && first.image.height == 180)
        #expect(zip(sorted, sorted.dropFirst()).allSatisfy { $1 - $0 <= 2.01 })
        #expect(project.fps.time(project.duration).seconds - (sorted.last ?? 0) <= 2.01)
    }

    private func topLevelBoxes(_ data: Data) throws -> [String] {
        var result: [String] = [], offset = 0
        func integer(_ start: Int, _ count: Int) -> UInt64 {
            data[start..<(start + count)].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        while offset + 8 <= data.count {
            let length = integer(offset, 4)
            let header = length == 1 ? 16 : 8
            try #require(offset + header <= data.count)
            let bytes = length == 1 ? integer(offset + 8, 8) : length == 0 ? UInt64(data.count - offset) : length
            try #require(bytes >= header && bytes <= data.count - offset)
            result.append(try #require(String(data: data[(offset + 4)..<(offset + 8)], encoding: .ascii)))
            offset += Int(bytes)
        }
        #expect(offset == data.count)
        return result
    }
}
