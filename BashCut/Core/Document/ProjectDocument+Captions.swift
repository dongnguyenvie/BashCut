import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutProject
import UniformTypeIdentifiers

extension ProjectDocument {
    func importCaptions(replace: Bool = false) {
        guard fileURL != nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        guard let url = ModalCenter.shared.open(panel, name: "import-captions")?.first else { return }
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let data = try file.read(upToCount: SubRip.maximumBytes + 1) ?? Data()
            guard let text = String(data: data, encoding: .utf8) else {
                throw ProjectError.invalid("SRT must use UTF-8")
            }
            apply(try project.importingSubRip(text, replace: replace), label: "Import SRT")
        } catch { message = error.localizedDescription }
    }

    func exportCaptions() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "captions.srt"
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        guard let url = ModalCenter.shared.save(panel, name: "export-captions") else { return }
        do { try SubRip.encode(project).write(to: url, atomically: true, encoding: .utf8) } catch {
            message = error.localizedDescription
        }
    }

    func registerCaptionCommands() {
        handle("captions.export") { document, arguments, _ in
            switch arguments.optionalString("as") ?? "srt" {
            case "json": return TimelineTranscript.captionsJSON(document.project)
            case "text": return .string(TimelineTranscript.captionsText(document.project))
            default: return .string(try SubRip.encode(document.project))
            }
        }
        handle("transcript.words") { document, arguments, _ in
            let from = arguments.optionalInt("from") ?? 0, to = arguments.optionalInt("to")
            let media = arguments.optionalString("media")
            if arguments.bool("heard") { return await document.heardWords(from: from, to: to, media: media) }
            return TimelineTranscript.wordsJSON(document.project, from: from, to: to, media: media)
        }
        handleAuthored("captions.import") { document, arguments, author in
            let revision = try document.commit(
                document.project.importingSubRip(try arguments.string("text"), replace: arguments.bool("replace")),
                label: "Import SRT", author: author, baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(revision)])
        }
    }
}
