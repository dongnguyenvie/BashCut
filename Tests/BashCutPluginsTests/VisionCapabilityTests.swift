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
}
