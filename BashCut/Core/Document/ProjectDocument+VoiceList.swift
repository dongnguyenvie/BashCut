import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import BashCutStorage
import Foundation

extension ProjectDocument {
    /// `capabilities.get --voices` (P0-C7, #532): every voice of the installed `voice.synthesize` providers with its
    /// facts (`VoiceListing`: saved clones first, `kind` and `source` on each), whether the provider clones and its
    /// reference range, the voice each plugin is set to, and the project's saved clone.
    func voiceList() -> JSONValue {
        let catalog = plugins.service.catalog(projectRoot: fileURL?.deletingLastPathComponent())
        let rates = VoiceRateStore.shared.summary().array
        let content = Self.baseLanguage(contentLanguage)
        let clones = voiceClones.list()
        var rows: [JSONValue] = []
        for plugin in catalog.plugins {
            for provider in (plugin.manifest.providers ?? []) where provider.capability == "voice.synthesize" {
                let current = pluginOptionValues(plugin)["voice"]?.string
                let range = provider.cloneRange
                rows.append(.object([
                    "plugin": .string(plugin.id), "provider": .string(provider.id), "name": .string(provider.name),
                    "availability": .string(plugins.currentAvailability(plugin).name),
                    "clones": .bool(range != nil), "current": current.map(JSONValue.string) ?? .null,
                    "cloneRange": range.map { .object(["minSeconds": .number($0.minSeconds), "maxSeconds": .number($0.maxSeconds)]) }
                        ?? .null,
                    "maxTakes": provider.maxTakes.map(JSONValue.integer) ?? .null,
                    "voices": .array(VoiceListing.rows(provider: provider, clones: clones, rates: rates, content: content)),
                ]))
            }
        }
        return .object([
            "providers": .array(rows), "projectVoice": projectVoiceClone.map { .string($0.id) } ?? .null,
        ])
    }
}
