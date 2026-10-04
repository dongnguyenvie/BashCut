import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

struct CaptionBuildTests {
    @Test("A long caption timeline builds one correctly ordered text layer per segment")
    func captionTimeline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let operations = (0..<1_000).map { index -> EditOperation in
            var item = Item(id: "caption-\(index)", at: index * 3, duration: 3)
            item["text"] = .string("Caption \(index)")
            return .insert(track: "t1", item: item)
        }
        let project = try Project(name: "Captions").applying(.group(label: "Fixture", author: .user, ops: operations)).project
        let builder = CompositionBuilder()
        var times: [Double] = []
        for _ in 0..<3 {
            let start = ContinuousClock.now
            let snapshot = try await builder.build(project, root: root)
            let elapsed = start.duration(to: .now).components
            times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            let instructions = try #require(snapshot.videoComposition.instructions as? [FrameInstruction])
            #expect(instructions.count == 1_000)
            for (index, instruction) in instructions.enumerated() {
                #expect(instruction.layers.count == 1)
                guard case .text(let layer) = instruction.layers.first else { Issue.record("Missing caption"); continue }
                #expect(layer.item.id == "caption-\(index)")
            }
        }
        TestMeasurement.report("CAPTION_BUILD median_ms=\(times.sorted()[1])")
    }
}
