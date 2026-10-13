import BashCutPlugin
import BashCutProject
import BashCutStorage
import Foundation

/// The voices a `voice.synthesize` provider can speak with, as `capabilities get --voices` lists them (#532): saved
/// clones it can use first (`kind: clone`, `source: my-voices`), then its presets (`kind: preset`, `source`: the
/// provider ID).
public enum VoiceListing {
    public static let myVoicesSource = "my-voices"

    /// Whether `provider` can speak with `clone`: it clones and its reference range takes the clone's length.
    public static func canSpeak(_ clone: VoiceClone, with provider: PluginProvider) -> Bool {
        provider.cloneRange?.accepts(clone.durationSeconds) ?? false
    }

    /// The language subtag of a BCP 47 tag, lowercased (`en-US` → `en`); empty for an empty tag.
    public static func baseLanguage(_ tag: String) -> String {
        String(tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "").lowercased()
    }

    /// Rows for one provider. `rates` are `VoiceRateStore` summary rows; `content` is the content language subtag.
    public static func rows(
        provider: PluginProvider, clones: [VoiceClone], rates: [JSONValue], content: String
    ) -> [JSONValue] {
        let cloneRows = clones.filter { canSpeak($0, with: provider) }.map { clone in
            var row: [String: JSONValue] = [
                "id": .string(clone.id), "name": .string(clone.name), "kind": .string("clone"),
                "source": .string(myVoicesSource), "language": .string(clone.language),
                "durationSeconds": .number(clone.durationSeconds),
            ]
            if !content.isEmpty, !clone.language.isEmpty {
                row["speaksContentLanguage"] = .bool(baseLanguage(clone.language) == content)
            }
            return finish(row, key: provider.id + "/" + clone.id, rates: rates)
        }
        let presets = (provider.voices ?? []).map { voice in
            var row: [String: JSONValue] = [
                "id": .string(voice.id), "kind": .string("preset"), "source": .string(provider.id),
                "language": .string(voice.language),
                "region": voice.region.map(JSONValue.string) ?? .null, "style": voice.style.map(JSONValue.string) ?? .null,
                "gender": voice.gender.map(JSONValue.string) ?? .null,
                "supportsRate": voice.supportsRate.map(JSONValue.bool) ?? .null,
            ]
            if !content.isEmpty { row["speaksContentLanguage"] = .bool(baseLanguage(voice.language) == content) }
            return finish(row, key: provider.id + "/" + voice.id, rates: rates)
        }
        return cloneRows + presets
    }

    private static func finish(_ row: [String: JSONValue], key: String, rates: [JSONValue]) -> JSONValue {
        var row = row
        row["measuredRate"] = .array(rates.filter { $0.object["voice"]?.string == key })
        return .object(row)
    }
}
