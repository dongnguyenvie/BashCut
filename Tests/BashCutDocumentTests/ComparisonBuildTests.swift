import AVFoundation
@testable import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation
import Testing

private actor ComparisonProbe: RenderEngine {
    private(set) var builds = 0
    private(set) var maximumActive = 0
    private var active = 0
    private var structure: Int? = 1
    func setStructure(_ value: Int?) { structure = value }

    func build(_ project: Project, root: URL, workspace: URL?, purpose: RenderPurpose) async throws -> CompositionSnapshot {
        builds += 1
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(20))
        return CompositionSnapshot(composition: AVMutableComposition(), videoComposition: AVMutableVideoComposition(),
                                   audioMix: AVMutableAudioMix(), structure: structure)
    }
    func export(_ snapshot: CompositionSnapshot, to url: URL, settings: ExportSettings,
                progress: @escaping @Sendable (Double) -> Void) async throws -> ExportReceipt {
        ExportReceipt(url: url, duration: 0, bytes: 0)
    }
}

struct ComparisonBuildTests {
    @Test("Comparison misses start graded and original builds concurrently; Compare off builds only once")
    func parallel() async throws {
        let engine = ComparisonProbe(), project = Project(name: "Probe")
        let root = FileManager.default.temporaryDirectory
        let pair = try await PreviewBuildPair.build(
            engine: engine, project: project, location: (root, nil), compare: true, cached: nil)
        #expect(await engine.builds == 2)
        #expect(await engine.maximumActive == 2)
        #expect(pair.comparison != nil && !pair.reusedComparison)
        let off = try await PreviewBuildPair.build(
            engine: engine, project: project, location: (root, nil), compare: false, cached: pair.cache)
        #expect(await engine.builds == 3)
        #expect(off.comparison == nil)
    }

    @Test("Reuse excludes revision/color changes but includes all other drawing inputs and current media structure")
    func invalidation() async throws {
        let engine = ComparisonProbe(), root = FileManager.default.temporaryDirectory
        var caption = Item(id: "t", at: 0, duration: 30)
        caption["text"] = .string("Original")
        var project = try Project(name: "Compare").applying(.insert(track: "t1", item: caption)).project
        var pair = try await PreviewBuildPair.build(
            engine: engine, project: project, location: (root, nil), compare: true, cached: nil)
        project = try project.applying(.setProperties(item: "t", patch: ["color": .object(["saturation": .number(0.2)])])).project
        pair = try await PreviewBuildPair.build(
            engine: engine, project: project, location: (root, nil), compare: true, cached: pair.cache)
        #expect(pair.reusedComparison)
        #expect(await engine.builds == 3)
        for patch: [String: JSONValue] in [
            ["text": .string("Changed")], ["opacity": .number(0.4)], ["transform": .object(["zoom": .number(1.2)])]
        ] {
            project = try project.applying(.setProperties(item: "t", patch: patch)).project
            pair = try await PreviewBuildPair.build(
            engine: engine, project: project, location: (root, nil), compare: true, cached: pair.cache)
            #expect(!pair.reusedComparison)
        }
        await engine.setStructure(2)
        pair = try await PreviewBuildPair.build(
            engine: engine, project: project, location: (root, nil), compare: true, cached: pair.cache)
        #expect(!pair.reusedComparison)
        await engine.setStructure(nil)
        for _ in 0..<2 {
            pair = try await PreviewBuildPair.build(
            engine: engine, project: project, location: (root, nil), compare: true, cached: pair.cache)
            #expect(!pair.reusedComparison)
        }
    }
}
