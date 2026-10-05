import AVFoundation
import BashCutAudioAnalysis
import BashCutDocument
import BashCutEngine
import BashCutPlugin
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing
@testable import BashCutPlugins

private actor NativeLoudnessProbe: LoudnessAnalyzing {
    private(set) var paths: [URL] = []
    let reject: Bool
    init(reject: Bool = false) { self.reject = reject }
    func analyzeLoudness(mediaURL: URL, preferredProvider: String?, projectRoot: URL?) async throws -> GeneratedLoudnessMeasurement {
        paths.append(mediaURL)
        if paths.count == 1 {
            #expect(mediaURL.pathExtension == "caf")
            #expect(try await AVURLAsset(url: mediaURL).loadTracks(withMediaType: .video).isEmpty)
        }
        if reject { throw ProjectError.invalid("Injected measurement failure") }
        let result = try LoudnessMeter.measure(try await TestFixtures.decodeStereo(mediaURL))
        return GeneratedLoudnessMeasurement(measurement: LoudnessMeasurement(
            integratedLUFS: result.integratedLUFS, truePeakDbTP: result.truePeakDbTP, loudnessRangeLU: result.loudnessRangeLU),
            provenance: PluginProvenance(pluginID: "test.native", pluginVersion: "1", providerID: "loudness"))
    }
}

struct LoudnessExportTests {
    @Test("Normalization measures audio only, then verifies the actual encoded movie")
    func nativePipeline() async throws {
        let root = try TestFixtures.temporaryDirectory("loudness-pipeline")
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try await request(root: root), analyzer = NativeLoudnessProbe()
        let pipeline = ExportPipeline(engine: AVFoundationRenderEngine(), loudness: analyzer)
        let result = try await pipeline.run(request) { _, _ in }
        #expect(result.verified)
        let final = try #require(result.finalMeasurement)
        let initial = try #require(result.generated?.measurement)
        let gain = try #require(result.appliedGainDb)
        #expect(abs(final.integratedLUFS - request.source.targetLUFS) < 0.3)
        #expect(abs(final.integratedLUFS - (initial.integratedLUFS + gain)) < 0.3)
        #expect(final.truePeakDbTP < -0.8)
        #expect(abs(try #require(result.mixGainDb) - (request.project.mixGainDb + gain)) < 1e-9)
        let paths = await analyzer.paths
        #expect(paths.count == 2 && paths.last == request.output)
        #expect(!FileManager.default.fileExists(atPath: paths[0].path))
        #expect(try await AVURLAsset(url: request.output).loadTracks(withMediaType: .video).count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: ProjectCache.url(.loudness, projectRoot: root).path).isEmpty)
    }

    @Test("Measurement failures remove temporary PCM and never create the final movie")
    func failedMeasurement() async throws {
        let root = try TestFixtures.temporaryDirectory("loudness-failure")
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try await request(root: root), analyzer = NativeLoudnessProbe(reject: true)
        let pipeline = ExportPipeline(engine: AVFoundationRenderEngine(), loudness: analyzer)
        await #expect(throws: (any Error).self) { _ = try await pipeline.run(request) { _, _ in } }
        #expect(!FileManager.default.fileExists(atPath: request.output.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: ProjectCache.url(.loudness, projectRoot: root).path).isEmpty)
    }

    private func request(root: URL) async throws -> ExportRequest {
        try await FileManager.default.copyItem(at: TestFixtures.requireVideo(), to: root.appendingPathComponent("test.mp4"))
        let media = Media(fields: ["id": .string("m"), "path": .string("test.mp4"),
                                   "fps": FrameRate().json, "frames": .integer(59)])
        var clip = Item(id: "clip", media: "m", at: 0, duration: 45)
        clip["volumeDb"] = .number(-4)
        clip["fadeIn"] = .integer(6)
        clip["fadeOut"] = .integer(6)
        clip["keyframes"] = ItemMotion(keys: ["volume": [.init(frame: 0, value: -8), .init(frame: 44, value: -4)]]).json
        let project = try Project(name: "Normalize").applying(.group(label: "Fixture", author: .user, ops: [
            .setFormat(width: 320, height: 180), .addMedia(media), .insert(track: "v1", item: clip),
            .setProjectProperties(patch: ["audio": .object(["targetLUFS": .number(-20), "mixGainDb": .number(-3)])])
        ])).project
        return try ExportRequest(project: project, root: root, workspace: nil, name: "normalized", preset: .proRes422HQ,
                                 directory: root, includeSubRip: false, normalizeAudio: true)
    }
}
