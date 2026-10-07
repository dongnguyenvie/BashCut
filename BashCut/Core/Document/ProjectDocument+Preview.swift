import AVFoundation
import AppKit
import BashCutEngine
import BashCutProject
import Foundation

extension ProjectDocument {
    struct AgentFrame {
        let url: URL
        let frame: Int
        let width: Int
        let height: Int
    }

    /// The viewer frame for agents (Ask's attach button and `ui frame`) as a bounded PNG in `.bashcut/cache/agent-context`.
    func captureAgentFrame() async throws -> URL { try await captureAgentFrame(at: nil).url }

    func captureAgentFrame(at requested: Int?, maximumDimension: Int = 1_280) async throws -> AgentFrame {
        // Right after an edit the preview still shows the previous composition; wait for the new one to be built
        // (not shown: the grab needs no player), up to 5 seconds.
        for _ in 0..<500 where preview.currentBuild == nil && project.duration > 0 && fileURL != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let root = fileURL?.deletingLastPathComponent(), let snapshot = preview.currentBuild,
            project.duration > 0
        else {
            throw ProjectError.invalid("The viewer has no frame to attach")
        }
        let frame = min(requested ?? playhead, project.duration - 1)
        let undecodable = snapshot.undecodable(at: frame)
        if !undecodable.isEmpty { throw UndecodableMediaError(undecodable) }
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let captured = try await generator.image(at: project.fps.time(frame)).image
        let image = MediaStills.fit(captured, maximumSide: maximumDimension)
        let data = try MediaStills.png(image)
        let directory = ProjectCache.url(.agentContext, projectRoot: root)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("frame-r\(project.revision)-f\(frame)-\(maximumDimension).png")
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        MediaStills.prune(directory, keeping: 10)
        return AgentFrame(url: url, frame: frame, width: image.width, height: image.height)
    }
}
