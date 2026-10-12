import BashCutPlugin
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutPlugins

/// `vision.faces` and `vision.text` adapters (P2-H6, P2-H7): the request a provider gets and the frames it may return.
@Suite("Vision capabilities")
struct VisionCapabilityTests {
    private let context = CapabilityContext(
        provenance: PluginProvenance(pluginID: "bashcut.vision", pluginVersion: "1.0.0", providerID: "bashcut.vision.faces"),
        outputDirectory: nil)

    private func entry(_ box: [Double], confidence: Double = 0.9, string: String? = nil) -> JSONValue {
        var fields: [String: JSONValue] = ["box": .array(box.map(JSONValue.number)), "confidence": .number(confidence)]
        if let string { fields["string"] = .string(string) }
        return .object(fields)
    }

    @Test("Requests carry the sampling and languages; bad ranges and missing files are refused before a call")
    func requests() async throws {
        let video = try await TestFixtures.requireVideo()
        let sampling = VisionSampling(mediaURL: video, step: 0.5, fromSeconds: 1, toSeconds: 2)
        #expect(FacesCapability(sampling).params(outputDirectory: nil) == .object([
            "mediaPath": .string(video.path), "step": .number(0.5), "fromSeconds": .number(1), "toSeconds": .number(2),
        ]))
        let text = TextRecognitionCapability(VisionSampling(mediaURL: video), languages: ["vi-VT", "en-US"])
        #expect(text.params(outputDirectory: nil).object["languages"] == .array([.string("vi-VT"), .string("en-US")]))
        #expect(text.params(outputDirectory: nil).object["fromSeconds"] == nil)
        try FacesCapability(sampling).validate()
        for bad in [
            VisionSampling(mediaURL: video, step: 0), VisionSampling(mediaURL: video, fromSeconds: 2, toSeconds: 1),
            VisionSampling(mediaURL: video.appendingPathExtension("missing")),
        ] {
            #expect(throws: PluginError.self) { try FacesCapability(bad).validate() }
        }
    }

    @Test("Frames with boxes and confidence pass with the provider's own fields; malformed ones are refused")
    func frames() async throws {
        let sampling = VisionSampling(mediaURL: URL(fileURLWithPath: "/dev/null"))
        let good: JSONValue = .object(["frames": .array([.object([
            "seconds": .number(0.5), "faces": .array([entry([0.1, 0.2, 0.3, 0.4])]), "people": .array([]),
            "mouthOpen": .bool(true),
        ])])])
        let faces = try await FacesCapability(sampling).output(from: good, context: context)
        #expect(faces.frames.count == 1 && faces.frames[0].object["mouthOpen"] == .bool(true))
        #expect(faces.provenance.providerID == "bashcut.vision.faces")
        let text: JSONValue = .object(["frames": .array([.object([
            "seconds": .number(0), "text": .array([entry([0, 0, 1, 0.1], string: "Hello")]),
        ])])])
        #expect(try await TextRecognitionCapability(sampling).output(from: text, context: context).frames.count == 1)

        let malformed: [JSONValue] = [
            .object([:]),
            .object(["frames": .array([.object(["seconds": .number(-1), "faces": .array([]), "people": .array([])])])]),
            .object(["frames": .array([.object(["seconds": .number(0), "faces": .array([])])])]),
            .object(["frames": .array([.object([
                "seconds": .number(0), "faces": .array([entry([0, 0, 1.5, 0.2])]), "people": .array([]),
            ])])]),
            .object(["frames": .array([.object([
                "seconds": .number(0), "faces": .array([entry([0, 0, 0.2])]), "people": .array([]),
            ])])]),
        ]
        for result in malformed {
            await #expect(throws: PluginError.self) { try await FacesCapability(sampling).output(from: result, context: context) }
        }
        let noString: JSONValue = .object(["frames": .array([.object(["seconds": .number(0), "text": .array([entry([0, 0, 1, 1])])])])])
        await #expect(throws: PluginError.self) {
            try await TextRecognitionCapability(sampling).output(from: noString, context: context)
        }
    }

    @Test("A cutout request names the picture and folder; the PNG must come back inside the request folder")
    func cutout() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let picture = folder.appendingPathComponent("mascot.png")
        try Data([0x89]).write(to: picture)
        let adapter = CutoutCapability(imageURL: picture, crop: true, outputRoot: folder)
        try adapter.validate()
        #expect(adapter.params(outputDirectory: folder) == .object([
            "imagePath": .string(picture.path), "crop": .bool(true), "outputDirectory": .string(folder.path),
        ]))
        #expect(throws: PluginError.self) {
            try CutoutCapability(imageURL: folder.appendingPathComponent("none.png"), crop: false, outputRoot: folder).validate()
        }
        let inside = CapabilityContext(provenance: context.provenance, outputDirectory: folder)
        let made = folder.appendingPathComponent("mascot-cutout.png")
        try Data([0x89]).write(to: made)
        let result: JSONValue = .object([
            "path": .string(made.path), "width": .integer(300), "height": .integer(500), "instances": .integer(1),
            "coverage": .number(0.66),
        ])
        let output = try await adapter.output(from: result, context: inside)
        #expect(output.width == 300 && output.instances == 1 && output.coverage == 0.66)
        let outside: JSONValue = .object(["path": .string("/etc/hosts"), "width": .integer(1), "height": .integer(1)])
        await #expect(throws: PluginError.self) { try await adapter.output(from: outside, context: inside) }
        await #expect(throws: PluginError.self) { try await adapter.output(from: .object([:]), context: inside) }
    }
}
