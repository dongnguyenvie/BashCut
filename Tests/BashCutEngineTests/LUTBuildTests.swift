import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

struct LUTBuildTests {
    @Test("Repeated builds of a 64-cube LUT project report edit latency")
    func rebuildBenchmark() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("luts"), withIntermediateDirectories: true)
        try await FileManager.default.copyItem(at: TestFixtures.requireVideo(), to: root.appendingPathComponent("clip.mp4"))
        let cube = "LUT_3D_SIZE 64\n" + String(repeating: "0 0 0\n", count: 64 * 64 * 64)
        try Data(cube.utf8).write(to: root.appendingPathComponent("luts/test.cube"))
        let media = Media(fields: [
            "id": .string("m"), "path": .string("clip.mp4"), "fps": FrameRate().json, "frames": .integer(59),
        ])
        var project = try Project(name: "LUT benchmark").applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media), .addColorLUT(ColorLUT(id: "lut", name: "LUT", path: "luts/test.cube", size: 64)),
            .insert(track: "v1", item: Item(id: "clip", media: "m", at: 0, duration: 30)),
            .setProperties(item: "clip", patch: ["color": .object(["lut": .string("lut")])]),
        ])).project
        let builder = CompositionBuilder()
        _ = try await builder.build(project, root: root)
        var times: [Double] = []
        for index in 0..<5 {
            project = try project.applying(.setProperties(item: "clip", patch: ["opacity": .number(0.5 + Double(index) * 0.1)])).project
            let start = ContinuousClock.now
            _ = try await builder.build(project, root: root)
            let elapsed = start.duration(to: .now).components
            times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        #expect(await builder.lutLoads == 1, "Parameter edits must reuse the parsed LUT")
        TestMeasurement.report("LUT_BUILD_MS median=\(times.sorted()[2]) samples=\(times)")
    }
}
