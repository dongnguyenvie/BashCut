import AVFoundation
import AppKit
import BashCutProject
import Foundation

extension ProjectDocument {
    struct AgentFrame {
        let url: URL
        let frame: Int
        let width: Int
        let height: Int
    }

    /// The viewer frame for agents (Ask's attach button and `ui frame`) as a bounded PNG in `.bashcut/agent-context`.
    func captureAgentFrame() async throws -> URL { try await captureAgentFrame(at: nil).url }

    func captureAgentFrame(at requested: Int?) async throws -> AgentFrame {
        // Right after an edit the preview is rebuilt (its snapshot is nil meanwhile); wait for it, up to 5 seconds.
        for _ in 0..<500 where preview.snapshot == nil && project.duration > 0 && fileURL != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let root = fileURL?.deletingLastPathComponent(), let snapshot = preview.snapshot, project.duration > 0 else {
            throw ProjectError.invalid("The viewer has no frame to attach")
        }
        let frame = min(requested ?? playhead, project.duration - 1)
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
        return AgentFrame(url: url, frame: frame, width: image.width, height: image.height)
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
