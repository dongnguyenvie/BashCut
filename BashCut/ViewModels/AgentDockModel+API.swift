import AppKit
import BashCutAgent
import BashCutAutomation
import BashCutProject
import Foundation

extension AgentDockModel {
    func saveConfiguration() {
        let value = configuration
        let secret = apiKey
        Task {
            do {
                _ = try value.endpoint()
                if !secret.isEmpty { try await credentials.save(secret, account: value.credentialAccount) }
                UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: "modelConfiguration")
                apiKey = ""
                error = ""
            } catch { self.error = error.localizedDescription }
        }
    }

    func generate() {
        guard !generating, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let config = configuration
        let secret = apiKey
        let requestedMode = mode
        let language = scriptLanguage
        let revision = document.project.revision
        let projectSession = document.sessionID
        let requestedImageURL = contextImageURL
        let id = UUID()
        var request = prompt
        if includeContext { request += "\n" + document.contextText() + "\n" + document.timelineText() }
        let instruction =
            CommandCatalog.instructions
            + (mode == "edit"
                ? "\nReturn ONLY an ops.json array, no markdown. Do not execute anything."
                : "\nWrite a \(scriptLanguage) script for the user's request. Return ONLY runnable source, no markdown fences. "
                    + "Use the bashcut CLI for timeline operations. Never embed API keys. The user will review before running.")
        generationID = id
        requestRevision = nil
        outputMode = nil
        output = ""
        generating = true
        error = ""
        generation = Task {
            defer {
                if generationID == id {
                    generating = false
                    generationID = nil
                }
            }
            do {
                let key =
                    secret.isEmpty ? try await credentials.read(account: config.credentialAccount) : secret
                let image: ModelImage?
                if let requestedImageURL {
                    image = try await Task.detached(priority: .utility) {
                        try ModelImage(data: Data(contentsOf: requestedImageURL))
                    }.value
                } else {
                    image = nil
                }
                let result = try await client.generate(
                    configuration: config, key: key, system: instruction, prompt: request,
                    image: image)
                try Task.checkCancellation()
                guard generationID == id, document.sessionID == projectSession else { return }
                output = Self.unfence(result)
                requestRevision = revision
                outputMode = requestedMode
                outputLanguage = language
            } catch is CancellationError {} catch {
                if generationID == id { self.error = error.localizedDescription }
            }
        }
    }

    func cancel() {
        generation?.cancel()
        generationID = nil
        generating = false
    }

    func applyProposal() {
        do {
            guard !generating, outputMode == "edit" else {
                throw ModelError.invalid("Generate a timeline proposal first")
            }
            guard !document.busy, !document.conflict, !document.timelineGestureActive else {
                throw ModelError.invalid("Editor is busy or has a file conflict")
            }
            guard let revision = requestRevision else {
                throw ModelError.invalid("Generate a proposal first")
            }
            let ops = try JSONDecoder().decode(JSONValue.self, from: Data(output.utf8))
            let before = document.project
            try document.history.apply(
                .group(label: "Model API edit", author: .model, ops: WireOperations.decode(ops)),
                label: "Model API edit", author: .model, baseRevision: revision)
            document.markAgentChanges(from: before, author: .model, label: "Model API edit")
            document.dirty = true
            document.rebuild()
            document.message = "Model API edit · Undo available"
            requestRevision = nil
            error = ""
        } catch { self.error = error.localizedDescription }
    }

    func saveScript() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = outputLanguage == "python" ? "bashcut-script.py" : "bashcut-script.sh"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(output.utf8).write(to: url, options: .atomic) } catch {
            self.error = error.localizedDescription
        }
    }

    func runScript() {
        guard !generating, outputMode == "script", !output.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Run the reviewed script?")
        alert.informativeText = String(
            localized:
                "This runs local code with your user permissions in the selected workspace. Review the source above first."
        )
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Run script"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                "BashCutScripts/" + UUID().uuidString)
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = folder.appendingPathComponent(
                outputLanguage == "python" ? "script.py" : "script.sh")
            try Data(output.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let previous = selectedSession
            open(.shell)
            guard let session = current, session.id != previous else { return }
            let quoted = "'" + url.path.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
            session.runCommand((outputLanguage == "python" ? "python3 " : "/bin/zsh ") + quoted)
        } catch { self.error = error.localizedDescription }
    }

    private static func unfence(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if lines.first?.hasPrefix("```") == true,
            lines.last?.trimmingCharacters(in: .whitespaces) == "```"
        {
            lines.removeFirst()
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
