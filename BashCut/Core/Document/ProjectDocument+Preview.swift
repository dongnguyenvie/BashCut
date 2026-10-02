import AVFoundation
import AppKit
import BashCutProject
import Foundation

extension ProjectDocument {
    func updatePlayhead() {
        if let error = player.currentItem?.error { message = error.localizedDescription }
        guard player.rate != 0, player.currentTime().isNumeric else { return }
        playhead = project.fps.frame(player.currentTime())
        guard showColorComparison, comparisonPlayer.currentItem != nil else { return }
        let drift = abs(comparisonPlayer.currentTime().seconds - player.currentTime().seconds)
        if drift > 1 / project.fps.value {
            comparisonPlayer.seek(
                to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func seek(_ frame: Int) {
        playhead = min(max(0, frame), project.duration)
        let time = project.fps.time(playhead)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        if showColorComparison {
            comparisonPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func togglePlayback() {
        if player.rate == 0 {
            player.play()
            if showColorComparison { comparisonPlayer.play() }
        } else {
            player.pause()
            comparisonPlayer.pause()
        }
    }

    func setColorComparison(_ enabled: Bool) {
        guard showColorComparison != enabled else { return }
        showColorComparison = enabled
        rebuild()
    }

    func waitUntilReady(_ item: AVPlayerItem, message: String) async throws {
        for _ in 0..<50 where item.status == .unknown {
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        guard item.status == .readyToPlay else {
            throw item.error ?? ProjectError.invalid(message)
        }
    }

    func captureAgentFrame() async throws -> URL {
        guard let root = fileURL?.deletingLastPathComponent(), let snapshot, project.duration > 0 else {
            throw ProjectError.invalid("The viewer has no frame to attach")
        }
        let frame = min(playhead, project.duration - 1)
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let captured = try await generator.image(at: project.fps.time(frame)).image
        let image = Self.scaledAgentImage(captured, maximumDimension: 1_280)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ProjectError.invalid("The current frame could not be encoded")
        }
        let directory = root.appendingPathComponent(".bashcut/agent-context", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("frame-r\(project.revision)-f\(frame).png")
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        Self.pruneAgentFrames(in: directory, keeping: 10)
        return url
    }

    private static func scaledAgentImage(_ image: CGImage, maximumDimension: Int) -> CGImage {
        let largest = max(image.width, image.height)
        guard largest > maximumDimension else { return image }
        let scale = Double(maximumDimension) / Double(largest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func pruneAgentFrames(in directory: URL, keeping limit: Int) {
        guard let values = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return }
        let sorted = values.filter { $0.pathExtension == "png" }.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return left > right
        }
        for url in sorted.dropFirst(limit) { try? FileManager.default.removeItem(at: url) }
    }
}
