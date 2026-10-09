import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

/// Converting video this Mac cannot decode: the ffmpeg call keeps every frame time, the copy lands through a
/// temporary file, and a failed run leaves nothing behind. A stand-in script plays ffmpeg, so no real tool runs.
struct MediaConverterTests {
    /// A fake ffmpeg: prints progress, then copies `input` to its last argument, or fails with `status`.
    private func fakeFFmpeg(in folder: URL, input: URL, status: Int32 = 0) throws -> URL {
        let url = folder.appendingPathComponent("ffmpeg")
        let body = status == 0
            ? "echo out_time_us=500000\necho progress=continue\nfor last; do :; done\ncp \"\(input.path)\" \"$last\"\n"
            : "echo 'Decoder av1 not found' >&2\nexit \(status)\n"
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test("Arguments keep frame times, encode H.264 in hardware and copy AAC sound")
    func arguments() {
        let arguments = MediaConverter.arguments(
            source: URL(fileURLWithPath: "/in.mp4"), destination: URL(fileURLWithPath: "/out.mov"),
            bitRate: 15_000_000, copyAudio: true)
        #expect(arguments.joined(separator: " ").contains("-fps_mode passthrough"))
        #expect(arguments.joined(separator: " ").contains("-c:v h264_videotoolbox -b:v 15000000"))
        #expect(arguments.joined(separator: " ").contains("-c:a copy"))
        #expect(arguments.last == "/out.mov")
        #expect(MediaConverter.arguments(
            source: URL(fileURLWithPath: "/in.mp4"), destination: URL(fileURLWithPath: "/out.mov"),
            bitRate: 1, copyAudio: false).joined(separator: " ").contains("-c:a aac"))
    }

    @Test("Bit rate scales with the picture and has a floor; progress lines are read")
    func bitRateAndProgress() {
        #expect(MediaConverter.bitRate(width: 1920, height: 1080, frameRate: 30) == 15_552_000)
        #expect(MediaConverter.bitRate(width: 320, height: 240, frameRate: 25) == 4_000_000)
        #expect(MediaConverter.progressSeconds("out_time_us=2500000") == 2.5)
        #expect(MediaConverter.progressSeconds("progress=continue") == nil)
    }

    @Test("The copy goes to media/converted under the project, named by media ID")
    func destination() {
        let root = URL(fileURLWithPath: "/project", isDirectory: true)
        let media = Media(fields: ["id": .string("m1"), "path": .string("footage/a.mp4")])
        #expect(MediaConverter.destination(for: media, root: root)?.path == "/project/media/converted/m1.mov")
        #expect(MediaConverter.destination(for: Media(fields: ["id": .string("../x")]), root: root) == nil)
    }

    @Test("A successful run writes the copy; a failed one throws ffmpeg's message and leaves no file")
    func run() async throws {
        let video = try await TestFixtures.requireVideo()
        let folder = try TestFixtures.temporaryDirectory("convert")
        let destination = folder.appendingPathComponent("out/m1.mov")
        let converter = MediaConverter(ffmpeg: try fakeFFmpeg(in: folder, input: video))
        let seen = LockedValues()
        try await converter.convert(from: video, to: destination) { seen.append($0) }
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(seen.values.last == 1)

        let failing = MediaConverter(ffmpeg: try fakeFFmpeg(in: folder, input: video, status: 1))
        let other = folder.appendingPathComponent("out/m2.mov")
        await #expect {
            try await failing.convert(from: video, to: other)
        } throws: { "\($0.localizedDescription)".contains("Decoder av1 not found") }
        #expect(!FileManager.default.fileExists(atPath: other.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: other.deletingLastPathComponent().path)
        #expect(leftovers == ["m1.mov"])
    }

    @Test("A transcript of the original is carried over to the converted copy")
    func carryTranscript() throws {
        let root = try TestFixtures.temporaryDirectory("carry-transcript")
        let original = root.appendingPathComponent("media/in.mp4")
        let copy = root.appendingPathComponent("media/converted/m1.mov")
        for (url, bytes) in [(original, "av1 bytes"), (copy, "h264 bytes")] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(bytes.utf8).write(to: url)
        }
        #expect(try MediaConverter.carryTranscript(from: original, to: copy, projectRoot: root) == false)

        let transcript = SourceTranscript(
            key: try SourceTranscript.cacheKey(for: original), language: "en", provider: ["plugin": .string("test")],
            transcribedAt: "2026-10-09T00:00:00Z", phrases: [.init(start: 0.5, end: 1.5, text: "hello there")],
            words: [.init(text: "hello", start: 0.5, end: 0.9)])
        try ProjectCache.store(transcript, .transcripts, key: transcript.key, projectRoot: root)
        #expect(try MediaConverter.carryTranscript(from: original, to: copy, projectRoot: root))

        let copyKey = try SourceTranscript.cacheKey(for: copy)
        let carried = try #require(ProjectCache.record(SourceTranscript.self, .transcripts, key: copyKey, projectRoot: root))
        #expect(carried.key == copyKey && carried.phrases == transcript.phrases && carried.words == transcript.words)
        #expect(carried.language == "en" && carried.transcribedAt == transcript.transcribedAt)
    }

    @Test("locate finds an executable ffmpeg in the given folders first")
    func locate() throws {
        let folder = try TestFixtures.temporaryDirectory("locate")
        let fake = try fakeFFmpeg(in: folder, input: folder)
        #expect(MediaConverter.locate(in: [folder.path], environment: [:])?.ffmpeg == fake)
    }
}

private final class LockedValues: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    func append(_ value: Double) { lock.withLock { stored.append(value) } }
    var values: [Double] { lock.withLock { stored } }
}
