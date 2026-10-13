import BashCutAutomation
import BashCutEngine
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import BashCutStorage
import Foundation

/// A clone reference cut from a source and checked, waiting for a name and consent to be saved (#532).
struct PreparedVoiceClone {
    let trim: VoiceCloneTrim
    let range: PluginCloneRange
    /// Providers whose reference range takes the trimmed clip.
    let providers: [String]
    let sourceDescription: String
    let language: String
}

/// Where a clone reference comes from: a file, or seconds of it.
struct VoiceCloneSource {
    let url: URL
    let range: ClosedRange<Double>?
    let description: String
}

@MainActor
private final class SavedVoiceClone {
    var clone: VoiceClone?
}

extension ProjectDocument {
    /// What these checks cannot tell (no cheap analysis gives them).
    static let cloneChecksNotDone = ["twoSpeakers"]

    /// The reference range to trim to: the asked provider's, else the highest-priority cloning provider's.
    func cloneRange(provider: String?) throws -> PluginCloneRange {
        let cloning = voiceProviders().map(\.provider).filter { $0.cloneRange != nil }
        if let provider {
            guard let range = cloning.first(where: { $0.id == provider })?.cloneRange else {
                throw RPCFailure(-32602, "\(provider) is not an installed voice provider that clones")
            }
            return range
        }
        guard let range = cloning.first?.cloneRange else {
            throw RPCFailure(
                -32602, "No installed voice provider clones voices (capabilities get --voices shows clones per provider)")
        }
        return range
    }

    /// `from` as a project media ID or a file path (relative to the project folder), with `at`/`to` seconds.
    func cloneSource(_ from: String, at: Double?, to: Double?) throws -> VoiceCloneSource {
        if let to, to <= (at ?? 0) { throw RPCFailure(-32602, "--to must be after --at") }
        let range: ClosedRange<Double>? = at == nil && to == nil ? nil : (at ?? 0)...(to ?? (at ?? 0) + VoiceCloneAudio.longestScan)
        let span = range.map { String(format: " %.1f–%.1f s", $0.lowerBound, $0.upperBound) } ?? ""
        if project.media.contains(where: { $0.id == from }) {
            let source = try analysisSource(from)
            return VoiceCloneSource(url: source.url, range: range, description: "media \(from) (\(source.url.lastPathComponent))" + span)
        }
        let relative = from.hasPrefix("/") ? nil : fileURL?.deletingLastPathComponent().appendingPathComponent(from)
        let url = relative?.standardizedFileURL ?? URL(fileURLWithPath: from)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RPCFailure(-32602, "\(from) is neither a media ID of this project nor a file")
        }
        return VoiceCloneSource(url: url, range: range, description: url.lastPathComponent + span)
    }

    /// Cuts and checks the best window of `source` for the provider's range into a temporary WAV.
    func prepareVoiceClone(_ source: VoiceCloneSource, provider: String?, language: String?) async throws -> PreparedVoiceClone {
        let range = try cloneRange(provider: provider)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("BashCut-voice-clones/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let trim: VoiceCloneTrim
        do {
            trim = try await VoiceCloneAudio.trim(
                source: source.url, range: source.range, minSeconds: range.minSeconds, maxSeconds: range.maxSeconds,
                output: folder.appendingPathComponent("reference.wav"))
        } catch let refusal as VoiceCloneRefusal {
            try? FileManager.default.removeItem(at: folder)
            throw RPCFailure(-32602, refusal.message, data: .object([
                "reason": .string(refusal.reason), "checks": .array(refusal.checks.map(Self.checkJSON)),
            ]))
        }
        let providers = voiceProviders().map(\.provider).filter { $0.cloneRange?.accepts(trim.seconds) ?? false }.map(\.id)
        return PreparedVoiceClone(
            trim: trim, range: range, providers: providers,
            sourceDescription: source.description + String(format: " → %.2f–%.2f s", trim.start, trim.end),
            language: language ?? contentLanguage)
    }

    /// Saves a prepared clone to My voices.
    func saveVoiceClone(
        _ prepared: PreparedVoiceClone, name: String, statement: VoiceConsentStatement, by: String
    ) throws -> VoiceClone {
        let draft = VoiceClone(
            id: "", name: name, language: prepared.language, providers: prepared.providers,
            sourceDescription: prepared.sourceDescription, durationSeconds: (prepared.trim.seconds * 100).rounded() / 100,
            consent: .init(by: by, statement: statement), reference: "")
        let clone = try voiceClones.add(draft, reference: prepared.trim.output)
        try? FileManager.default.removeItem(at: prepared.trim.output.deletingLastPathComponent())
        return clone
    }

    static func checkJSON(_ check: VoiceCloneCheck) -> JSONValue {
        .object([
            "id": .string(check.id), "passed": .bool(check.passed), "value": .number(check.value),
            "detail": .string(check.detail),
        ])
    }

    func preparedJSON(_ prepared: PreparedVoiceClone) -> [String: JSONValue] {
        let round = { (value: Double) in JSONValue.number((value * 100).rounded() / 100) }
        return [
            "window": .object([
                "start": round(prepared.trim.start), "end": round(prepared.trim.end), "seconds": round(prepared.trim.seconds),
            ]),
            "range": .object(["minSeconds": .number(prepared.range.minSeconds), "maxSeconds": .number(prepared.range.maxSeconds)]),
            "checks": .array(prepared.trim.checks.map(Self.checkJSON)),
            "notChecked": .array(Self.cloneChecksNotDone.map(JSONValue.string)),
            "providers": .array(prepared.providers.map(JSONValue.string)), "source": .string(prepared.sourceDescription),
        ]
    }

    /// `voice.clone-add`: the source is trimmed and checked at once; saving waits for the user's approval (the
    /// consent is theirs), unless they let agents act without asking.
    func registerVoiceCloneAdd() {
        handleAuthored("voice.clone-add") { document, arguments, author in
            let name = try arguments.string("name").trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...80).contains(name.count) else { throw RPCFailure(-32602, "The name is 1–80 characters") }
            guard let statement = VoiceConsentStatement(rawValue: try arguments.string("consent")) else {
                throw RPCFailure(-32602, "consent is own or permission")
            }
            let source = try document.cloneSource(
                try arguments.string("from"), at: arguments.optionalDouble("at"), to: arguments.optionalDouble("to"))
            let prepared = try await document.prepareVoiceClone(
                source, provider: arguments.optionalString("provider"), language: arguments.optionalString("language"))
            let saved = SavedVoiceClone()
            let shown = [
                "name": name, "source": prepared.sourceDescription, "consent": statement.rawValue,
                "seconds": String(format: "%.2f", prepared.trim.seconds),
            ]
            let request = try document.queuePrivilegedApproval(
                method: "voice.clone-add", author: author, arguments: shown
            ) { [weak document] in
                guard let document else { throw RPCFailure(-32000, "Editor closed") }
                let by = document.settings.agentActionsAutoApproved && author != .user
                    ? "user (agents act without asking; requested by \(author.rawValue))" : "user"
                saved.clone = try document.saveVoiceClone(prepared, name: name, statement: statement, by: by)
                document.message = String(format: String(localized: "Saved voice %@"), name)
            }
            var result = document.preparedJSON(prepared)
            result["approval"] = .string(request.autoApproved ? "approved" : "pending")
            result["requestId"] = .string(request.id.uuidString)
            if let clone = saved.clone {
                result["clone"] = document.cloneJSON(clone)
            } else {
                result["voice"] = .string(document.voiceClones.newID(for: name))
                result["next"] = .string("Once the user approves, voice clone-list shows it")
            }
            return .object(result)
        }
    }
}
