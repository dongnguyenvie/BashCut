import BashCutAutomation
import BashCutPlugins
import BashCutProject
import Foundation

/// What is in the picture (P2-H6, P2-H7): `media.subjects` runs a `vision.faces` provider (face and person boxes),
/// `media.ocr` a `vision.text` provider (on-screen text), over pictures sampled every `step` source seconds. Raw
/// boxes, confidence and time; which face matters or whether text is a caption is the agent's (flexibility audit).
extension ProjectDocument {
    func registerVisionCommands() {
        handleAuthored("media.subjects") { document, arguments, author in
            let provider = arguments.optionalString("provider")
            return try await document.startVisionJob("media.subjects", arguments, author: author) { document, sampling, root in
                try await document.plugins.running(FacesCapability.capability) {
                    try await document.plugins.service.detectSubjects(
                        sampling, preferredProvider: provider
                            ?? document.project.preferredProvider(for: FacesCapability.capability),
                        projectRoot: root)
                }
            }
        }
        handleAuthored("media.ocr") { document, arguments, author in
            let provider = arguments.optionalString("provider")
            let languages = (arguments.optionalString("languages") ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return try await document.startVisionJob("media.ocr", arguments, author: author) { document, sampling, root in
                try await document.plugins.running(TextRecognitionCapability.capability) {
                    try await document.plugins.service.recognizeText(
                        sampling, languages: languages, preferredProvider: provider
                            ?? document.project.preferredProvider(for: TextRecognitionCapability.capability),
                        projectRoot: root)
                }
            }
        }
    }

    private func startVisionJob(
        _ method: String, _ arguments: CommandArguments, author: Author,
        run: @escaping @MainActor (ProjectDocument, VisionSampling, URL) async throws -> GeneratedVision
    ) async throws -> JSONValue {
        let mediaID = try arguments.string("media")
        let step = arguments.optionalDouble("step") ?? 1
        let from = arguments.optionalDouble("from"), to = arguments.optionalDouble("to")
        if let from, let to, to < from { throw RPCFailure(-32602, "to must not be before from") }
        return try await startCapabilityJob(method, author: author, arguments: arguments) { document in
            let (root, media, url) = try document.capabilityMedia(mediaID)
            guard media.kind != "audio" else { throw RPCFailure(-32602, "Media \(mediaID) has no picture") }
            let span = (to ?? media.durationSeconds) - (from ?? 0)
            guard media.isImage || span / step <= Double(VisionSampling.maximumSamples) else {
                throw RPCFailure(-32602, "Over \(VisionSampling.maximumSamples) pictures: use a larger step or a shorter range")
            }
            let generated = try await run(
                document, VisionSampling(mediaURL: url, step: step, fromSeconds: from, toSeconds: to), root)
            let fps = media.fps.value
            return .object([
                "media": .string(mediaID), "step": .number(generated.step),
                // The source frame of each picture, for media frame and media resolve-range.
                "frames": .array(generated.frames.map { frame in
                    var fields = frame.object
                    if !media.isImage, fps > 0, let seconds = fields["seconds"]?.double {
                        fields["frame"] = .integer(Int((seconds * fps).rounded()))
                    }
                    return .object(fields)
                }),
                "timeline": document.mediaPlacements(media),
                "provider": .object(generated.provenance.json),
            ])
        }
    }
}
