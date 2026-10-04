import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

struct ProxyManagerTests {
    @Test("The policy flags large, high-rate or HEVC footage and leaves light footage alone")
    func policy() async throws {
        let video = try await TestFixtures.requireVideo()
        let light = try #require(try await ProxyManager().probe(video))
        #expect(light.codec == "avc1" && light.width == 320 && light.height == 180)
        #expect(!light.needsProxy)
        var strict = ProxyManager.Policy()
        strict.maximumDimension = 200
        #expect(try await ProxyManager(policy: strict).probe(video)?.needsProxy == true)
        let audio = try TestFixtures.temporaryDirectory("proxy").appendingPathComponent("tone.wav")
        try TestFixtures.writeTone(to: audio, seconds: 0.2)
        #expect(try await ProxyManager().probe(audio) == nil)
    }

    @Test("A proxy keeps every frame time, has short GOPs and sound, and previews read it")
    func generate() async throws {
        let video = try await TestFixtures.requireVideo()
        let root = try TestFixtures.temporaryDirectory("proxy")
        defer { try? FileManager.default.removeItem(at: root) }
        let media = Media(fields: ["id": .string("clip"), "path": .string(video.path)])
        let destination = try #require(ProxyManager.destination(for: media, root: root))
        let reported = Progress()
        try await ProxyManager().generate(from: video, to: destination) { reported.add($0) }
        #expect(reported.values.last == 1)

        let original = try await Self.videoSamples(video)
        let proxy = try await Self.videoSamples(destination)
        #expect(proxy.times == original.times)
        #expect(proxy.longestGOP <= ProxyManager.keyframeInterval)
        #expect(try await !AVURLAsset(url: destination).loadTracks(withMediaType: .audio).isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
        #expect(leftovers == ["clip.mov"])

        let source = ProxyMediaSource()
        #expect(try source.url(for: media, root: root, workspace: nil, purpose: .preview) == destination)
        #expect(try source.url(for: media, root: root, workspace: nil, purpose: .export).lastPathComponent == "test.mp4")
    }

    @Test("Unsafe media IDs get no proxy path")
    func unsafeIDs() {
        let root = URL(fileURLWithPath: "/tmp/project")
        for id in ["", ".hidden", "../escape", "a/b"] {
            #expect(ProxyManager.destination(for: Media(fields: ["id": .string(id)]), root: root) == nil)
        }
    }

    private final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Double] = []
        var values: [Double] { lock.withLock { stored } }
        func add(_ value: Double) { lock.withLock { stored.append(value) } }
    }

    /// Decoded frame times on the track timeline (edit lists applied), and the longest run of stored
    /// samples between sync samples.
    private static func videoSamples(_ url: URL) async throws -> (times: [Double], longestGOP: Int) {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        let stored = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(decoded)
        reader.add(stored)
        #expect(reader.startReading())
        var times: [Double] = []
        while let buffer = decoded.copyNextSampleBuffer() {
            // Microseconds, so time scales that store the same instant compare equal.
            times.append((CMSampleBufferGetPresentationTimeStamp(buffer).seconds * 1_000_000).rounded())
        }
        var run = 0
        var longest = 0
        while let buffer = stored.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(buffer) > 0 else { continue }
            let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[CFString: Any]]
            let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
            run = notSync ? run + 1 : 1
            longest = max(longest, run)
        }
        return (times, longest)
    }
}
