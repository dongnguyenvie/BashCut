import AppKit
import BashCutAutomation
import BashCutProject
import UniformTypeIdentifiers

extension ProjectDocument {
    func importGeneratedCaptions(_ generated: GeneratedPluginCaptions, replace: Bool) throws {
        let provenance: [String: JSONValue] = [
            "plugin": .string(generated.pluginID), "provider": .string(generated.providerID),
            "version": .string(generated.pluginVersion),
        ]
        apply(
            try project.importingSubRip(
                generated.text, replace: replace, provenance: provenance),
            label: "Generate captions")
    }

    func importCaptions(replace: Bool = false) {
        guard fileURL != nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try SubRip.encode(project).write(to: url, atomically: true, encoding: .utf8) } catch {
            message = error.localizedDescription
        }
    }

    func registerCaptionCommands() {
        registry.register("captions.export") { [weak self] _, _ in
            guard let self else { throw RPCFailure(-32000, "Editor closed") }
            return .string(try SubRip.encode(project))
        }
        registry.register("captions.import") { [weak self] params, author in
            guard let self, let author, let base = params["baseRev"]?.int, let text = params["text"]?.string else {
                throw RPCFailure(-32602, "text and baseRev are required")
            }
            guard !busy, !conflict, !timelineGestureActive else { throw RPCFailure(-32003, "Editor busy") }
            let before = project
            try history.apply(
                project.importingSubRip(text, replace: params["replace"] == .bool(true)),
                label: "Import SRT", author: author, baseRevision: base)
            markAgentChanges(from: before, author: author, label: "Import SRT")
            dirty = true
            rebuild()
            return .object(["rev": .integer(project.revision)])
        }
    }
}
