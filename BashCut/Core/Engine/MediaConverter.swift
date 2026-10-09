@preconcurrency import AVFoundation
import BashCutProject
import Foundation

/// Turns video this Mac cannot decode (AV1 on a Mac without an AV1 decoder, VP9 without its decoder) into an
/// H.264 copy BashCut can preview and export, using the system's ffmpeg. Every frame is kept with its time
/// (no frame-rate conversion), so the media's frame count and the items placed from it stay valid. The original
/// is never touched; the copy goes through a temporary file, so a cancelled or failed run leaves nothing behind.
public struct MediaConverter: Sendable {
    public typealias Convert = @Sendable (_ source: URL, _ destination: URL, _ progress: @escaping @Sendable (Double) -> Void)
        async throws -> Void

    /// The ffmpeg found on this Mac.
    public let ffmpeg: URL

    public init(ffmpeg: URL) { self.ffmpeg = ffmpeg }

    /// The first executable ffmpeg in `directories`, then the usual install places and `PATH`; nil when none.
    public static func locate(
        in directories: [String] = [], environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> MediaConverter? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = directories + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin"]
            + (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
            .map(MediaConverter.init(ffmpeg:))
    }

    /// Where the converted copy of `media` goes: `media/converted/<media id>.mov` in the project folder, which
    /// clearing the cache does not remove. Nil when the ID cannot be a file name.
    public static func destination(for media: Media, root: URL) -> URL? {
        guard ProxyMediaSource.isSafe(media.id) else { return nil }
        return root.appendingPathComponent("media/converted", isDirectory: true)
            .appendingPathComponent(media.id).appendingPathExtension("mov")
    }

    /// Video bit rate for the copy: about 0.25 bit per pixel per frame, at least 4 Mbit/s.
    public static func bitRate(width: Int, height: Int, frameRate: Double) -> Int {
        max(4_000_000, Int((Double(width * height) * max(1, frameRate) * 0.25).rounded()))
    }

    /// ffmpeg arguments: the first video track to H.264 on the hardware encoder with the source frame times, the
    /// first audio track copied when it is AAC (re-encoded to AAC otherwise), progress as key=value lines on stdout.
    public static func arguments(
        source: URL, destination: URL, bitRate: Int, copyAudio: Bool
    ) -> [String] {
        [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", source.path,
            "-map", "0:v:0", "-map", "0:a:0?", "-fps_mode", "passthrough",
            "-c:v", "h264_videotoolbox", "-b:v", String(bitRate), "-pix_fmt", "yuv420p",
            "-c:a", copyAudio ? "copy" : "aac", "-b:a", "256k",
            "-map_metadata", "0", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", "-f", "mov",
            destination.path,
        ]
    }

    /// Reads `out_time_us=` from ffmpeg's progress lines; nil for any other line.
    public static func progressSeconds(_ line: Substring) -> Double? {
        guard line.hasPrefix("out_time_us="), let micro = Double(line.dropFirst("out_time_us=".count)) else { return nil }
        return max(0, micro / 1_000_000)
    }

    /// Writes the decodable copy of `source` to `destination`. `progress` receives 0…1.
    public func convert(
        from source: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProjectError.invalid("\(source.lastPathComponent) has no video to convert")
        }
        let (size, transform, frameRate) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        let audioCodec = try await asset.loadTracks(withMediaType: .audio).first?.load(.formatDescriptions).first
            .map(CMFormatDescriptionGetMediaSubType)
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appendingPathComponent(".\(UUID().uuidString).partial.mov")
        defer { try? FileManager.default.removeItem(at: partial) }
        let arguments = Self.arguments(
            source: source, destination: partial,
            bitRate: Self.bitRate(width: Int(abs(rect.width)), height: Int(abs(rect.height)), frameRate: Double(frameRate)),
            copyAudio: audioCodec == kAudioFormatMPEG4AAC)
        try await run(arguments, duration: duration, progress: progress)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        progress(1)
    }

    /// Runs ffmpeg, reporting progress from its stdout and stopping it when the task is cancelled.
    private func run(_ arguments: [String], duration: Double, progress: @escaping @Sendable (Double) -> Void) async throws {
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let errorText = LockedText()
        errors.fileHandleForReading.readabilityHandler = { errorText.append($0.availableData) }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard duration > 0, let text = String(bytes: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline) {
                if let seconds = Self.progressSeconds(line) { progress(min(0.99, seconds / duration)) }
            }
        }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try process.run() } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        errorText.append(errors.fileHandleForReading.readDataToEndOfFile())
        try Task.checkCancellation()
        guard status == 0 else {
            let detail = errorText.value.trimmingCharacters(in: .whitespacesAndNewlines).suffix(400)
            throw ProjectError.invalid("ffmpeg could not convert the video (exit \(status))"
                + (detail.isEmpty ? "" : ": \(detail)"))
        }
    }
}

/// Text collected from a pipe's handler thread.
private final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    var value: String { lock.withLock { String(bytes: data, encoding: .utf8) ?? "" } }
}

extension SourceTranscript {
    /// The transcript cache key of `url`: its content key.
    public static func cacheKey(for url: URL) throws -> String {
        try ProjectCache.contentKey(for: url, namespace: "media-transcript-v\(version)")
    }
}

extension MediaConverter {
    /// Keeps the transcript when media moves to its converted copy: the copy has the same sound and frame times, so
    /// the stored transcript of `source` is stored again under `copy`'s key (transcripts are kept by file content,
    /// and the copy is another file). Returns whether there was one to carry.
    @discardableResult
    public static func carryTranscript(from source: URL, to copy: URL, projectRoot: URL) throws -> Bool {
        guard let record = ProjectCache.record(
                SourceTranscript.self, .transcripts, key: try SourceTranscript.cacheKey(for: source), projectRoot: projectRoot),
            record.version == SourceTranscript.version
        else { return false }
        let key = try SourceTranscript.cacheKey(for: copy)
        try ProjectCache.store(record.keyed(key), .transcripts, key: key, projectRoot: projectRoot)
        return true
    }
}
