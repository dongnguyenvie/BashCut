import BashCutAutomation
import BashCutProject
import BashCutStorage
import Foundation

/// `speech.rate` (P0-C2): how fast people speak in the transcribed footage, per media and speaker, and how fast each
/// synthesized voice has read, in the content language's unit; `narration.windows` (P0-C3): where narration could go.
extension ProjectDocument {
    func registerSpeechRateCommands() {
        handle("narration.windows") { document, arguments, _ in
            let words = await document.syncWords()
            var levels: MixMeasure.Curve?
            if arguments.bool("levels") {
                levels = Self.curve(try await document.measureRendered(document.project, provider: nil))
            }
            var result = NarrationWindows.json(
                document.project, words: words.source == "none" ? [] : words.words,
                minSeconds: arguments.optionalDouble("minSeconds") ?? 0, rate: arguments.optionalDouble("rate"),
                unit: SpeechUnits.unit(for: document.contentLanguage), levels: levels
            ).object
            result["wordSource"] = .string(words.source)
            return .object(result)
        }
        handle("speech.rate") { document, arguments, _ in
            let unit = arguments.optionalString("unit").flatMap(SpeechUnits.Unit.init(rawValue:))
            var rows: [JSONValue] = []
            let ids = arguments.optionalString("media").map { [$0] } ?? document.project.media.filter { !$0.isImage }.map(\.id)
            for id in ids {
                guard let transcript = try await document.storedTranscript(id) else {
                    if arguments.optionalString("media") != nil {
                        throw RPCFailure(-32602, "Media \(id) has no stored transcript: run media transcribe first")
                    }
                    continue
                }
                var row = SpeechRate.json(transcript, unit: unit ?? SpeechUnits.unit(for: transcript.language)).object
                row["media"] = .string(id)
                rows.append(.object(row))
            }
            return .object([
                "media": .array(rows), "voices": VoiceRateStore.shared.summary(voice: arguments.optionalString("voice")),
                "contentUnit": .string(SpeechUnits.unit(for: document.contentLanguage).rawValue),
            ])
        }
    }
}
