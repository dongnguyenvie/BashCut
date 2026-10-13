import BashCutAutomation
import BashCutPlugins
import BashCutProject
import Foundation

/// Mascot poses of a brand kit (#551): a pose cut from a photo with a `vision.cutout` provider, or the missing poses
/// made from one reference with an `image.generate` provider and cut out, each saved as a sticker and stored in the
/// kit's `mascot`.
extension ProjectDocument {
    func startBrandPose(_ arguments: CommandArguments, author: Author) async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        let brand = try libraryCatalog.item(try arguments.string("brand"))
        guard brand.kind == .brand else { throw RPCFailure(-32602, "\(brand.reference) is not a brand kit") }
        guard brand.scope.isWritable else {
            throw RPCFailure(-32602, "\(brand.reference) is read-only; save a copy with library update --as first")
        }
        let names = Self.commaList(try arguments.string("pose"))
        guard !names.isEmpty, names.allSatisfy({ (1...40).contains($0.count) }) else {
            throw RPCFailure(-32602, "Pose names are 1–40 characters")
        }
        let target = PoseTarget(
            kitName: brand.name, scope: arguments.optionalString("scope").flatMap(LibraryScope.init(rawValue:)) ?? brand.scope,
            provider: arguments.optionalString("provider"), root: root, author: author)
        if arguments.bool("generate") {
            let existing = brand.params["mascot"]?.object ?? [:]
            let missing = names.filter { existing[$0] == nil }
            guard !missing.isEmpty else { throw RPCFailure(-32602, "The kit already has every pose named") }
            let referenceName = arguments.optionalString("reference") ?? existing.keys.sorted().first.flatMap { existing[$0]?.string }
            guard let referenceName else {
                throw RPCFailure(-32602, "Give --reference (a picture or sticker id): the kit has no pose to start from")
            }
            let reference = try resolvePicture(referenceName, root: root)
            return try await startCapabilityJob("library.brand-pose", author: author, arguments: arguments) { document in
                let lock = document.project.illustration?.lock
                let request = ImageGenerationCapability(
                    prompts: missing.map { ImagePrompt(id: $0, prompt: Self.posePrompt($0)) }, style: lock?.style,
                    references: [reference], seed: lock?.seed, width: 1_024, height: 1_024,
                    outputRoot: root.appendingPathComponent("generated/images", isDirectory: true))
                let generated = try await document.plugins.running(ImageGenerationCapability.capability) {
                    try await document.plugins.service.generateImages(
                        request, preferredProvider: document.project.preferredProvider(
                            for: ImageGenerationCapability.capability),
                        projectRoot: root)
                }
                let pictures = generated.images.map { ($0.id, $0.url) }
                var result = try await document.storePoses(pictures, brand: brand, target: target)
                if case .object(var fields) = result {
                    let failed = generated.failed.map { JSONValue.object(["pose": .string($0.id), "message": .string($0.message)]) }
                    fields["failed"] = .array((fields["failed"]?.array ?? []) + failed)
                    result = .object(fields)
                }
                return result
            }
        }
        guard names.count == 1, let image = arguments.optionalString("image") else {
            throw RPCFailure(-32602, "Give --image with one --pose, or --generate with the pose names")
        }
        let picture = try resolvePicture(image, root: root)
        return try await startCapabilityJob("library.brand-pose", author: author, arguments: arguments) { document in
            try await document.storePoses([(names[0], picture)], brand: brand, target: target)
        }
    }

    /// What a missing pose is asked as: the character of the reference picture, alone, in that pose. The pose name
    /// is the user's words; the wording around it only asks for a picture the cut-out can separate.
    static func posePrompt(_ pose: String) -> String {
        "The same character as in the reference picture, alone, full body, pose: \(pose). Plain background."
    }

    /// Cuts each picture out, saves it as a sticker and stores the poses in the kit. Pictures that fail to cut out
    /// are reported in `failed`.
    func storePoses(_ pictures: [(pose: String, url: URL)], brand: LibraryItem, target: PoseTarget) async throws -> JSONValue {
        var stored: [(pose: String, sticker: String)] = []
        var failed: [JSONValue] = []
        for (pose, url) in pictures {
            do {
                let sticker = try await poseSticker(from: url, pose: pose, target: target)
                stored.append((pose, sticker))
            } catch {
                failed.append(.object(["pose": .string(pose), "message": .string(error.localizedDescription)]))
            }
        }
        guard !stored.isEmpty else {
            throw RPCFailure(-32602, "No pose was stored: " + (failed.first?.object["message"]?.string ?? "nothing to cut out"))
        }
        let current = try libraryCatalog.item(brand.id, scope: brand.scope)
        var params = current.params
        var mascot = params["mascot"]?.object ?? [:]
        for (pose, sticker) in stored { mascot[pose] = .string(sticker) }
        params["mascot"] = .object(mascot)
        do { _ = try LibraryBrand(params: params) } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
        let store = try libraryCatalog.store(brand.scope)
        let changes: [String: JSONValue] = ["params": .object(params)]
        let kit = try await libraryChange(
            "library.brand-pose", scope: brand.scope, author: target.author, arguments: ["id": brand.reference]
        ) {
            try store.update(brand.id, changes: changes, file: nil, preview: nil).json()
        }
        return .object([
            "poses": .array(stored.map { .object(["pose": .string($0.pose), "sticker": .string($0.sticker)]) }),
            "failed": .array(failed), "brand": kit,
        ])
    }

    /// The brand sheet's From picture…: the pose sticker in the default library scope, for the user.
    func poseSticker(from url: URL, pose: String) async throws -> String {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        return try await poseSticker(from: url, pose: pose, target: PoseTarget(
            kitName: String(localized: "Mascot"), scope: defaultLibraryScope, provider: nil, root: root, author: .user))
    }

    /// One picture's subject on a transparent background, saved as a sticker; returns its library reference.
    func poseSticker(from url: URL, pose: String, target: PoseTarget) async throws -> String {
        let root = target.root
        let cutout = try await plugins.running(CutoutCapability.capability) {
            try await plugins.service.cutout(
                imageURL: url, crop: true,
                preferredProvider: target.provider ?? project.preferredProvider(for: CutoutCapability.capability),
                projectRoot: root, outputRoot: root.appendingPathComponent("generated/cutouts", isDirectory: true))
        }
        let added = try await addLibraryItem(
            kind: .sticker, name: "\(target.kitName) \(pose)", scope: target.scope,
            changes: ["tags": .array([.string("mascot"), .string(pose)])], file: cutout.url, author: target.author,
            method: "library.brand-pose")
        guard let id = added.object["id"]?.string else {
            throw RPCFailure(-32602, "The pose sticker waits for approval; run library brand-pose again once approved")
        }
        return "\(target.scope.rawValue):\(id)"
    }
}

/// Where pose stickers go and who asks: the kit's name (the sticker names), the library scope, the cut-out provider,
/// the project folder and the author.
struct PoseTarget {
    let kitName: String
    let scope: LibraryScope
    let provider: String?
    let root: URL
    let author: Author
}
