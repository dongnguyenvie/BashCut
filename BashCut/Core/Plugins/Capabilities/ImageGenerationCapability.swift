import BashCutPlugin
import BashCutProject
import Foundation
import ImageIO

/// One picture to make: the scene's ID (echoed back) and its prompt.
public struct ImagePrompt: Sendable, Equatable {
    public let id: String
    public let prompt: String

    public init(id: String, prompt: String) {
        self.id = id
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// `image.generate` (#550): a batch of pictures in one request — every scene's prompt, the style lock (style prompt,
/// reference pictures, seed) and the picture size — written as image files into the request folder. Core knows no
/// model: the provider turns the prompts and references into pictures however it likes.
public struct ImageGenerationCapability: CapabilityAdapter {
    public static let capability = "image.generate"
    public static let maximumPrompts = 24

    public let prompts: [ImagePrompt]
    public let style: String?
    public let references: [URL]
    public let seed: Int?
    public let width: Int
    public let height: Int
    public let outputRoot: URL?

    public init(
        prompts: [ImagePrompt], style: String?, references: [URL], seed: Int?, width: Int, height: Int, outputRoot: URL
    ) {
        self.prompts = prompts
        self.style = style.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        self.references = references
        self.seed = seed
        self.width = width
        self.height = height
        self.outputRoot = outputRoot
    }

    public func validate() throws {
        guard (1...Self.maximumPrompts).contains(prompts.count) else {
            throw PluginError.invalid("Give 1–\(Self.maximumPrompts) prompts")
        }
        guard prompts.allSatisfy({ !$0.prompt.isEmpty && !$0.id.isEmpty }) else {
            throw PluginError.invalid("Every picture needs an ID and a prompt")
        }
        guard Set(prompts.map(\.id)).count == prompts.count else { throw PluginError.invalid("Picture IDs must be unique") }
        guard (64...8_192).contains(width), (64...8_192).contains(height) else {
            throw PluginError.invalid("Picture size must be 64–8192 pixels a side")
        }
        guard references.count <= IllustrationLock.maximumReferences else {
            throw PluginError.invalid("Up to \(IllustrationLock.maximumReferences) reference pictures")
        }
        for reference in references where !FileManager.default.fileExists(atPath: reference.path) {
            throw PluginError.invalid("Reference picture not found: \(reference.path)")
        }
    }

    /// `aspectRatio` is the size reduced (9:16), for providers that take a ratio instead of pixels.
    public func params(outputDirectory: URL?) -> JSONValue {
        let divisor = Self.gcd(width, height)
        var styleFields: [String: JSONValue] = ["references": .array(references.map { .string($0.path) })]
        if let style { styleFields["prompt"] = .string(style) }
        if let seed { styleFields["seed"] = .integer(seed) }
        return .object([
            "prompts": .array(prompts.map { .object(["id": .string($0.id), "prompt": .string($0.prompt)]) }),
            "style": .object(styleFields),
            "width": .integer(width), "height": .integer(height),
            "aspectRatio": .string("\(width / divisor):\(height / divisor)"),
            "outputDirectory": .string(outputDirectory?.path ?? ""),
        ])
    }

    /// `images` [{id, path, seed?, revisedPrompt?}] for the IDs asked for, each a readable picture inside the request
    /// folder; `failed` [{id, message}] for scenes the provider could not make. Nothing made at all is an error.
    public func output(from result: JSONValue, context: CapabilityContext) async throws -> GeneratedImages {
        let asked = Set(prompts.map(\.id))
        var images: [GeneratedImage] = []
        for entry in result.object["images"]?.array ?? [] {
            guard let id = entry.object["id"]?.string, asked.contains(id), !images.contains(where: { $0.id == id }),
                let path = entry.object["path"]?.string
            else { throw PluginError.invalid("Image plugin returned a picture for an unknown or repeated scene") }
            let url = try context.confinedOutput(path, label: "Image plugin")
            guard let size = Self.pixelSize(url) else { throw PluginError.invalid("Image plugin output \(id) is not a picture") }
            images.append(GeneratedImage(
                id: id, url: url, width: size.width, height: size.height, seed: entry.object["seed"]?.int,
                revisedPrompt: entry.object["revisedPrompt"]?.string))
        }
        let failed = (result.object["failed"]?.array ?? []).compactMap { entry -> GeneratedImages.Failure? in
            guard let id = entry.object["id"]?.string, asked.contains(id), !images.contains(where: { $0.id == id })
            else { return nil }
            return GeneratedImages.Failure(id: id, message: entry.object["message"]?.string ?? "failed")
        }
        guard !images.isEmpty else {
            throw PluginError.invalid("Image plugin made no picture" + (failed.first.map { ": \($0.message)" } ?? ""))
        }
        let missing = asked.subtracting(images.map(\.id)).subtracting(failed.map(\.id))
        let unreported = prompts.filter { missing.contains($0.id) }.map {
            GeneratedImages.Failure(id: $0.id, message: "The provider returned no picture")
        }
        return GeneratedImages(images: images, failed: failed + unreported, provenance: context.provenance)
    }

    static func pixelSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        return (width, height)
    }

    private static func gcd(_ first: Int, _ second: Int) -> Int {
        var (a, b) = (max(1, first), max(1, second))
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}

/// One picture an `image.generate` provider made.
public struct GeneratedImage: Sendable {
    public let id: String
    public let url: URL
    public let width: Int
    public let height: Int
    public let seed: Int?
    public let revisedPrompt: String?
}

/// The pictures of one `image.generate` request, with the scenes that failed.
public struct GeneratedImages: Sendable {
    public struct Failure: Sendable, Equatable {
        public let id: String
        public let message: String
    }

    public let images: [GeneratedImage]
    public let failed: [Failure]
    public let provenance: PluginProvenance
}

extension CapabilityService {
    /// Every scene of a batch in one request to one provider.
    public func generateImages(
        _ request: ImageGenerationCapability, preferredProvider: String?, projectRoot: URL
    ) async throws -> GeneratedImages {
        try await run(request, preferredProvider: preferredProvider, projectRoot: projectRoot)
    }
}
