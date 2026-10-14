import BashCutPlugin
import BashCutProject
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import BashCutPlugins

/// `image.generate` (#550): one request for every scene with the style lock and size, and the pictures it may return.
@Suite("Image generation capability")
struct ImageGenerationCapabilityTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("image-gen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func png(_ url: URL, width: Int = 96, height: Int = 160) throws {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func request(_ root: URL, references: [URL] = [], prompts: [ImagePrompt]? = nil) -> ImageGenerationCapability {
        ImageGenerationCapability(
            prompts: prompts ?? [ImagePrompt(id: "s1", prompt: " a fox "), ImagePrompt(id: "s2", prompt: "a boat")],
            style: "crayon", references: references, seed: 7, width: 1080, height: 1920, outputRoot: root)
    }

    @Test("The request carries every scene, the style lock and the size; bad batches are refused before a call")
    func params() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let hero = root.appendingPathComponent("hero.png")
        try png(hero)
        let adapter = request(root, references: [hero])
        try adapter.validate()
        let params = adapter.params(outputDirectory: root)
        #expect(params.object["prompts"] == .array([
            .object(["id": .string("s1"), "prompt": .string("a fox")]),
            .object(["id": .string("s2"), "prompt": .string("a boat")]),
        ]))
        #expect(params.object["style"] == .object([
            "prompt": .string("crayon"), "references": .array([.string(hero.path)]), "seed": .integer(7),
        ]))
        #expect(params.object["aspectRatio"] == .string("9:16") && params.object["width"] == .integer(1080))
        for bad in [
            request(root, prompts: []),
            request(root, prompts: [ImagePrompt(id: "a", prompt: "x"), ImagePrompt(id: "a", prompt: "y")]),
            request(root, prompts: [ImagePrompt(id: "a", prompt: "  ")]),
            request(root, references: [root.appendingPathComponent("missing.png")]),
        ] {
            #expect(throws: PluginError.self) { try bad.validate() }
        }
    }

    @Test("Pictures must be inside the request folder and for scenes asked; failures and silent scenes are reported")
    func output() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = request(root, prompts: [
            ImagePrompt(id: "s1", prompt: "a"), ImagePrompt(id: "s2", prompt: "b"), ImagePrompt(id: "s3", prompt: "c"),
        ])
        let context = CapabilityContext(
            provenance: PluginProvenance(pluginID: "bashcut.image-gen", pluginVersion: "0.0.1", providerID: "bashcut.image-gen.api"),
            outputDirectory: root)
        try png(root.appendingPathComponent("s1.png"))
        let result: JSONValue = .object([
            "images": .array([.object(["id": .string("s1"), "path": .string("s1.png"), "seed": .integer(3)])]),
            "failed": .array([.object(["id": .string("s2"), "message": .string("blocked")])]),
        ])
        let made = try await adapter.output(from: result, context: context)
        #expect(made.images.map(\.id) == ["s1"] && made.images[0].width == 96 && made.images[0].seed == 3)
        #expect(made.failed == [.init(id: "s2", message: "blocked"), .init(id: "s3", message: "The provider returned no picture")])
        try Data("not a picture".utf8).write(to: root.appendingPathComponent("bad.png"))
        for bad: JSONValue in [
            .object(["images": .array([.object(["id": .string("s9"), "path": .string("s1.png")])])]),
            .object(["images": .array([.object(["id": .string("s1"), "path": .string("/etc/hosts")])])]),
            .object(["images": .array([.object(["id": .string("s1"), "path": .string("bad.png")])])]),
            .object(["images": .array([]), "failed": .array([.object(["id": .string("s1"), "message": .string("quota")])])]),
        ] {
            await #expect(throws: PluginError.self) { try await adapter.output(from: bad, context: context) }
        }
    }
}
