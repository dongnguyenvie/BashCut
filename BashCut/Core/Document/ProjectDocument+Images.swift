import BashCutAutomation
import BashCutEngine
import BashCutPlugins
import BashCutProject
import Foundation
import ImageIO

/// Generated illustrations (#550): `image generate` runs every scene through one `image.generate` provider call with
/// the style lock, adds the pictures to the media pool marked `generated`, and returns a contact sheet; `image style`
/// keeps the lock; `image disclose` puts the disclosure label over generated pictures. Core knows no model.
extension ProjectDocument {
    func registerImageCommands() {
        handleAuthored("image.generate") { document, arguments, author in
            try await document.startImageGeneration(arguments, author: author)
        }
        handle("image.generate-list") { document, _, _ in document.generatedImagesList() }
        handleAuthored("image.style") { document, arguments, author in
            try document.setIllustrationStyle(arguments, author: author)
        }
        handleAuthored("image.disclose") { document, arguments, author in
            try document.discloseGeneratedImages(text: arguments.optionalString("text"), author: author)
        }
        handleAuthored("library.brand-pose") { document, arguments, author in
            try await document.startBrandPose(arguments, author: author)
        }
    }

    // MARK: Generate

    /// The scenes of `image generate`: `prompts` as [{id, prompt}] or texts, or one `prompt`.
    static func imagePrompts(_ arguments: CommandArguments) throws -> [ImagePrompt] {
        if let single = arguments.optionalString("prompt") {
            guard arguments["prompts"] == nil else { throw RPCFailure(-32602, "Give prompt or prompts, not both") }
            return [ImagePrompt(id: "1", prompt: single)]
        }
        guard case .array(let values)? = arguments["prompts"], !values.isEmpty else {
            throw RPCFailure(-32602, "Give prompts (a JSON file of [{id, prompt}]) or --prompt")
        }
        return try values.enumerated().map { index, value in
            if let text = value.string { return ImagePrompt(id: String(index + 1), prompt: text) }
            guard let prompt = value.object["prompt"]?.string else {
                throw RPCFailure(-32602, "prompts[\(index)]: expected a text or {id, prompt}")
            }
            let id = value.object["id"]?.string ?? value.object["id"]?.int.map(String.init) ?? String(index + 1)
            return ImagePrompt(id: id, prompt: prompt)
        }
    }

    /// A picture given as an absolute or project-relative path, or a library item with a file (a sticker).
    func resolvePicture(_ reference: String, root: URL) throws -> URL {
        let file = reference.hasPrefix("/") ? URL(fileURLWithPath: reference) : root.appendingPathComponent(reference)
        if FileManager.default.fileExists(atPath: file.path) { return file.standardizedFileURL }
        if let item = try? libraryCatalog.item(reference), let found = libraryCatalog.fileURL(of: item) { return found }
        throw RPCFailure(-32602, "\(reference) is neither a picture file nor a library item with a file")
    }

    /// The style lock for one call: the stored lock unless `noLock`, with this call's style, references and seed over it.
    func illustrationForCall(_ arguments: CommandArguments) -> IllustrationLock {
        var lock = arguments.bool("noLock") ? IllustrationLock() : project.illustration?.lock ?? IllustrationLock()
        if let style = arguments.optionalString("style") { lock.style = style }
        if let references = arguments["references"]?.string { lock.references = Self.commaList(references) }
        if let seed = arguments.optionalInt("seed") { lock.seed = seed }
        return lock
    }

    static func commaList(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func startImageGeneration(_ arguments: CommandArguments, author: Author) async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { throw RPCFailure(-32602, "Open a saved project first") }
        let prompts = try Self.imagePrompts(arguments)
        let lock = illustrationForCall(arguments)
        let references = try lock.references.map { try resolvePicture($0, root: root) }
        let request = ImageGenerationCapability(
            prompts: prompts, style: lock.style, references: references, seed: lock.seed,
            width: arguments.optionalInt("width") ?? project.width, height: arguments.optionalInt("height") ?? project.height,
            outputRoot: root.appendingPathComponent("generated/images", isDirectory: true))
        do { try request.validate() } catch { throw RPCFailure(-32602, error.localizedDescription) }
        let provider = arguments.optionalString("provider")
        return try await startCapabilityJob("image.generate", author: author, arguments: arguments) { document in
            let session = document.sessionID
            let generated = try await document.plugins.running(ImageGenerationCapability.capability) {
                try await document.plugins.service.generateImages(
                    request, preferredProvider: provider
                        ?? document.project.preferredProvider(for: ImageGenerationCapability.capability),
                    projectRoot: root)
            }
            try document.ensureSession(session)
            let media = try document.addGeneratedImages(generated, prompts: prompts, root: root, author: author)
            let sheet = Self.contactSheet(generated.images, into: generated.images[0].url.deletingLastPathComponent())
            return .object([
                "images": .array(zip(generated.images, media).map { image, mediaID in
                    .object([
                        "id": .string(image.id), "media": .string(mediaID), "path": .string(image.url.path),
                        "projectPath": .string(MediaPathResolver.projectPath(for: image.url, projectRoot: root)),
                        "width": .integer(image.width), "height": .integer(image.height),
                    ])
                }),
                "failed": .array(generated.failed.map { .object(["id": .string($0.id), "message": .string($0.message)]) }),
                "contactSheet": sheet.map { .string($0.path) } ?? .null,
                "style": lock.json, "provider": .object(generated.provenance.json),
            ])
        }
    }

    /// Adds the pictures to the media pool in one undo step, each with `generated: true`, what made it and its prompt.
    func addGeneratedImages(
        _ generated: GeneratedImages, prompts: [ImagePrompt], root: URL, author: Author
    ) throws -> [String] {
        var operations: [EditOperation] = []
        var ids: [String] = []
        let call = PluginCallContext.current
        for image in generated.images {
            var media = try Self.importedImage(url: image.url, projectFPS: project.fps, root: root).media
            var made = generated.provenance.json
            made["scene"] = .string(image.id)
            made["prompt"] = .string(prompts.first { $0.id == image.id }?.prompt ?? "")
            if let seed = image.seed { made["seed"] = .integer(seed) }
            if let revised = image.revisedPrompt { made["revisedPrompt"] = .string(revised) }
            var provenance = generated.provenance.json
            provenance["origin"] = .string("ai")
            if let requestID = call.requestID { provenance["requestId"] = .string(requestID) }
            media["generated"] = .bool(true)
            media["generatedBy"] = .object(made)
            media["provenance"] = .object(provenance)
            operations.append(.addMedia(media))
            ids.append(media.id)
        }
        let label = String(localized: "Generate pictures")
        try commit(.group(label: label, author: author, ops: operations), label: label, author: author)
        emitMediaImported(ids, author: author)
        return ids
    }

    /// One PNG of every picture, labelled by scene ID, next to them; nil when it cannot be drawn.
    static func contactSheet(_ images: [GeneratedImage], into folder: URL) -> URL? {
        let cells = images.map { image in
            MediaStills.Cell(image: thumbnail(image.url, maximumSide: 480), label: image.id, group: 0)
        }
        guard let sheet = MediaStills.sheet(cells, columns: min(4, cells.count), longEdge: 360),
            let data = try? MediaStills.png(sheet)
        else { return nil }
        let url = folder.appendingPathComponent("contact-sheet.png")
        return (try? data.write(to: url)) == nil ? nil : url
    }

    static func thumbnail(_ url: URL, maximumSide: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: List, style lock and disclosure

    func generatedImagesList() -> JSONValue {
        let root = fileURL?.deletingLastPathComponent()
        let uses = project.tracks.flatMap(\.items).reduce(into: [String: Int]()) { counts, item in
            if let media = item.mediaID { counts[media, default: 0] += 1 }
        }
        let images: [JSONValue] = project.media.filter(\.isGenerated).map { media in
            let made = media["generatedBy"]?.object ?? [:]
            return .object([
                "media": .string(media.id), "id": made["scene"] ?? .null, "prompt": made["prompt"] ?? .null,
                "projectPath": .string(media.path), "provider": made["provider"] ?? .null,
                "placed": .integer(uses[media.id] ?? 0),
            ])
        }
        let report = plugins.service.capabilityStatus(ImageGenerationCapability.capability, projectRoot: root)
        let style = project.illustration
        return .object([
            "images": .array(images),
            "style": style.map { .object(["lock": $0.lock.json, "from": .string($0.source)]) } ?? .null,
            "disclosure": project.disclosureText.map(JSONValue.string) ?? .null,
            "available": .bool(report.available),
            "provider": report.available ? .null : .string(report.message),
        ])
    }

    func setIllustrationStyle(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        let fields = ["style", "references", "seed", "disclosure"].filter { arguments[$0] != nil }
        if arguments.bool("clear") {
            guard fields.isEmpty else { throw RPCFailure(-32602, "clear takes no other field") }
            let revision = try commit(
                .setProjectProperties(patch: ["illustration": .null]), label: String(localized: "Clear illustration style"),
                author: author)
            return .object(["rev": .integer(revision), "style": illustrationJSON()])
        }
        guard !fields.isEmpty else { return .object(["style": illustrationJSON()]) }
        var lock = (try? project["illustration"].map { try IllustrationLock($0) }) ?? IllustrationLock()
        if let style = arguments["style"]?.string { lock.style = style.isEmpty ? nil : style }
        if let references = arguments["references"]?.string { lock.references = Self.commaList(references) }
        if let seed = arguments.optionalInt("seed") { lock.seed = seed }
        if let disclosure = arguments["disclosure"]?.string { lock.disclosure = disclosure.isEmpty ? nil : disclosure }
        do { _ = try IllustrationLock(lock.json) } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
        let revision = try commit(
            .setProjectProperties(patch: ["illustration": lock.isEmpty ? .null : lock.json]),
            label: String(localized: "Set illustration style"), author: author)
        return .object(["rev": .integer(revision), "style": illustrationJSON()])
    }

    private func illustrationJSON() -> JSONValue {
        project.illustration.map { .object(["lock": $0.lock.json, "from": .string($0.source)]) } ?? .null
    }

    /// One label per run of generated pictures still missing one, on the titles layer, in one undo step.
    func discloseGeneratedImages(text: String?, author: Author) throws -> JSONValue {
        guard let label = text ?? project.disclosureText else {
            throw RPCFailure(-32602, "No disclosure label: pass --text, or set image style --disclosure or the brand's")
        }
        let generated = Set(project.media.filter(\.isGenerated).map(\.id))
        let spans = project.tracks.filter { $0.kind == TrackKind.video && !$0.isHidden }.flatMap(\.items)
            .filter { $0.mediaID.map(generated.contains) == true && $0.duration > 0 }
            .map { $0.at..<$0.end }.sorted { $0.lowerBound < $1.lowerBound }
        var runs: [Range<Int>] = []
        for span in spans {
            if let last = runs.last, span.lowerBound <= last.upperBound {
                runs[runs.count - 1] = last.lowerBound..<max(last.upperBound, span.upperBound)
            } else {
                runs.append(span)
            }
        }
        let labels = project.tracks.filter { $0.kind == TrackKind.text && !$0.isHidden }.flatMap(\.items)
            .filter { $0["disclosure"] == .bool(true) || $0.text == label }.map { $0.at..<$0.end }
        var planner = LayerPlanner(project)
        var added: [JSONValue] = []
        do {
            let track = try planner.titleTrack()
            for run in runs where TimelineReview.uncoveredFrames(run, by: labels) > 0 {
                var item = Item(at: run.lowerBound, duration: run.count)
                item["text"] = .string(label)
                item["disclosure"] = .bool(true)
                item["textStyle"] = .object([
                    "size": .number(0.028), "align": .string("left"), "positionX": .number(0.06),
                    "positionY": .number(0.9),
                ])
                let placed = try planner.place(item, on: track)
                added.append(.object([
                    "item": .string(item.id), "track": .string(placed), "at": .integer(item.at), "dur": .integer(item.duration),
                ]))
            }
        } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
        guard !added.isEmpty else { return .object(["rev": .integer(project.revision), "added": .array([])]) }
        let revision = try commitPlan(
            planner, label: String(localized: "Add disclosure labels"), author: author, baseRevision: nil)
        return .object(["rev": .integer(revision), "added": .array(added), "text": .string(label)])
    }
}
