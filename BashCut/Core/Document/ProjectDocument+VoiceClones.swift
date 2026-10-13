import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import BashCutStorage
import Foundation

/// The voice a line is said with (#532): a provider's preset or a saved clone ("My voices"). The project's chosen
/// voice is the plugin's `voice` option for a preset (as before) or the project field `voiceClone` for a clone: a
/// clone is not one of the plugin's choices, so it cannot live in the plugin's option.
struct ResolvedVoice {
    let choice: VoiceChoice?
    /// The provider that says it; nil lets the project's preference (or priority) pick.
    let provider: String?
    /// The ID kept in the take's voice facts (`provider/voice` once the provider is known).
    let id: String?
}

extension ProjectDocument {
    var voiceClones: VoiceCloneStore { .shared }

    /// The saved clone this project speaks with, when it chose one and it is still saved.
    var projectVoiceClone: VoiceClone? {
        project["voiceClone"]?.string.flatMap { voiceClones.clone($0) }
    }

    /// Ready `voice.synthesize` providers with their plugins, highest priority first.
    func voiceProviders() -> [(plugin: InstalledPlugin, provider: PluginProvider)] {
        plugins.service.runnablePlugins(projectRoot: fileURL?.deletingLastPathComponent())
            .flatMap { plugin in
                (plugin.manifest.providers ?? []).filter { $0.capability == "voice.synthesize" }.map { (plugin, $0) }
            }
            .sorted { $0.provider.priority > $1.provider.priority }
    }

    static func canSpeak(_ clone: VoiceClone, with provider: PluginProvider) -> Bool {
        VoiceListing.canSpeak(clone, with: provider)
    }

    func cloneReference(_ clone: VoiceClone) -> VoiceCloneReference {
        VoiceCloneReference(
            path: voiceClones.referenceURL(clone).path, voice: clone.id, name: clone.name, language: clone.language)
    }

    /// `voice` as asked (a clone ID, a preset `voice` or `provider/voice`), else the project's clone, else nothing
    /// (the plugin's own `voice` option). A clone only goes to a provider that clones; a preset to the provider that
    /// offers it.
    func resolveVoice(_ voice: String?, provider: String?) throws -> ResolvedVoice {
        let preferred = provider ?? project.preferredProvider(for: "voice.synthesize")
        if let voice, voice.hasPrefix("clone-") {
            guard let clone = voiceClones.clone(voice) else { throw RPCFailure(-32602, "No saved voice \(voice)") }
            return try resolveClone(clone, preferred: preferred, explicit: provider != nil)
        }
        if let voice { return try resolvePreset(voice, provider: provider) }
        if let clone = projectVoiceClone, let resolved = try? resolveClone(clone, preferred: preferred, explicit: provider != nil) {
            return resolved
        }
        return ResolvedVoice(choice: nil, provider: provider, id: nil)
    }

    private func resolveClone(_ clone: VoiceClone, preferred: String?, explicit: Bool) throws -> ResolvedVoice {
        let usable = voiceProviders().map(\.provider).filter { Self.canSpeak(clone, with: $0) }
        let chosen = usable.first { $0.id == preferred }
            ?? (explicit ? nil : usable.first { clone.providers.contains($0.id) } ?? usable.first)
        guard let chosen else {
            throw RPCFailure(-32602, explicit && !usable.isEmpty
                ? "\(preferred ?? "The provider") cannot speak with the cloned voice \(clone.id)"
                : "No installed voice provider can speak with the cloned voice \(clone.id)")
        }
        return ResolvedVoice(choice: .clone(cloneReference(clone)), provider: chosen.id, id: clone.id)
    }

    private func resolvePreset(_ voice: String, provider: String?) throws -> ResolvedVoice {
        let parts = voice.split(separator: "/", maxSplits: 1).map(String.init)
        let (providerID, voiceID) = parts.count == 2 ? (parts[0], parts[1]) : (provider, voice)
        let match = voiceProviders().map(\.provider).first { candidate in
            (providerID == nil || candidate.id == providerID) && (candidate.voices ?? []).contains { $0.id == voiceID }
        }
        guard let match else {
            throw RPCFailure(-32602, "Unknown voice \(voice); capabilities get --voices lists the presets and clones")
        }
        return ResolvedVoice(choice: .preset(voiceID), provider: match.id, id: voiceID)
    }

    /// `voice.use`: the project's voice. A clone sets `voiceClone`; a preset sets its plugin's `voice` option and
    /// the voice provider, and clears `voiceClone`.
    func useVoice(_ voice: String, author: Author) throws -> JSONValue {
        if voice == "default" {
            if project["voiceClone"]?.string != nil {
                try commit(.setProjectProperties(patch: ["voiceClone": .null]), label: "Choose voice", author: author)
            }
            return .object(["voice": .null, "kind": .string("default"), "rev": .integer(project.revision)])
        }
        if voice.hasPrefix("clone-") {
            guard let clone = voiceClones.clone(voice) else { throw RPCFailure(-32602, "No saved voice \(voice)") }
            try commit(.setProjectProperties(patch: ["voiceClone": .string(clone.id)]), label: "Choose voice", author: author)
            return .object(["voice": .string(clone.id), "kind": .string("clone"), "rev": .integer(project.revision)])
        }
        let resolved = try resolvePreset(voice, provider: nil)
        guard case .preset(let id) = resolved.choice, let providerID = resolved.provider,
            let plugin = voiceProviders().first(where: { $0.provider.id == providerID })?.plugin
        else { throw RPCFailure(-32602, "Unknown voice \(voice)") }
        if plugin.manifest.options?.contains(where: { $0.id == "voice" }) == true {
            try setPluginOption(plugin, option: "voice", value: .string(id), author: author)
        }
        var operations: [EditOperation] = [.setProviderPreference(capability: "voice.synthesize", provider: providerID)]
        if project["voiceClone"]?.string != nil { operations.append(.setProjectProperties(patch: ["voiceClone": .null])) }
        try commit(.group(label: "Choose voice", author: author, ops: operations), label: "Choose voice", author: author)
        return .object([
            "voice": .string(id), "provider": .string(providerID), "kind": .string("preset"),
            "rev": .integer(project.revision),
        ])
    }

    /// A saved clone as `voice clone-list` and `capabilities get --voices` show it.
    func cloneJSON(_ clone: VoiceClone) -> JSONValue {
        let usable = voiceProviders().map(\.provider).filter { Self.canSpeak(clone, with: $0) }.map(\.id)
        return .object([
            "id": .string(clone.id), "name": .string(clone.name), "kind": .string("clone"),
            "source": .string(VoiceListing.myVoicesSource), "language": .string(clone.language),
            "providers": .array(usable.map(JSONValue.string)), "savedFor": .array(clone.providers.map(JSONValue.string)),
            "durationSeconds": .number(clone.durationSeconds), "sourceDescription": .string(clone.sourceDescription),
            "createdAt": .string(ISO8601DateFormatter().string(from: clone.createdAt)),
            "consent": .object([
                "by": .string(clone.consent.by), "at": .string(ISO8601DateFormatter().string(from: clone.consent.at)),
                "statement": .string(clone.consent.statement.rawValue),
            ]),
            "reference": .string(voiceClones.referenceURL(clone).path),
            "current": .bool(project["voiceClone"]?.string == clone.id),
        ])
    }

    func registerVoiceCloneCommands() {
        handle("voice.clone-list") { document, _, _ in
            .object(["clones": .array(document.voiceClones.list().map(document.cloneJSON)), "root": .string(document.voiceClones.root.path)])
        }
        handleAuthored("voice.clone-remove") { document, arguments, author in
            let id = try arguments.string("voice")
            guard let clone = document.voiceClones.clone(id) else { throw RPCFailure(-32602, "No saved voice \(id)") }
            // A saved voice belongs to the user and every project: removing it asks first, like saving it.
            let request = try document.queuePrivilegedApproval(
                method: "voice.clone-remove", author: author, arguments: ["voice": id, "name": clone.name]
            ) { [weak document] in
                try document?.removeVoiceClone(id, author: author)
            }
            return .object([
                "voice": .string(id), "approval": .string(request.autoApproved ? "approved" : "pending"),
                "requestId": .string(request.id.uuidString),
            ])
        }
        handleAuthored("voice.use") { document, arguments, author in
            do {
                return try document.useVoice(try arguments.string("voice"), author: author)
            } catch let error as ProjectError {
                throw RPCFailure.invalid(error)
            }
        }
        registerVoiceCloneAdd()
    }

    /// Removes a saved clone from every project's list; this project stops using it.
    func removeVoiceClone(_ id: String, author: Author) throws {
        do { try voiceClones.remove(id) } catch { throw RPCFailure(-32602, error.localizedDescription) }
        if project["voiceClone"]?.string == id {
            try commit(.setProjectProperties(patch: ["voiceClone": .null]), label: "Choose voice", author: author)
        }
    }
}
