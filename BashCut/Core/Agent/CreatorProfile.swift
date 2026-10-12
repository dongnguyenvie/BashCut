import BashCutProject
import Foundation

/// The creator's profile as structured preferences (P3-I5): `creator.<field>` keys with known meanings, so every
/// skill reads the same names. Lists are comma-separated; voice samples are media IDs of the project they were
/// recorded in. Kept with the other preferences; an agent's change for every project always waits for approval.
public enum CreatorProfile {
    public static let prefix = "creator."

    /// Field → what it holds.
    public static let fields: [String: String] = [
        "name": "The creator's name as shown on screen",
        "handle": "The @handle",
        "channel": "Channel or page name",
        "platforms": "Where they post (comma-separated: tiktok, youtube, reels…)",
        "language": "Content language code (vi, en…)",
        "niche": "What the channel is about",
        "audience": "Who watches",
        "tone": "How they speak (warm, fast, dry…)",
        "cta": "Their usual call to action",
        "voiceSamples": "Media IDs of clean recordings of their voice (comma-separated)",
        "disclosure": "How they label sponsored content",
    ]

    static let lists: Set<String> = ["platforms", "voiceSamples"]

    public static func isCreatorKey(_ key: String) -> Bool { key.hasPrefix(prefix) }

    /// Checks a `creator.*` key and value: a known field, and for voice samples media IDs that `mediaExists` knows.
    public static func validate(key: String, value: String?, mediaExists: (String) -> Bool) throws {
        let field = String(key.dropFirst(prefix.count))
        guard fields[field] != nil else {
            throw KnowledgeError(
                "Unknown creator field \(field): use one of \(fields.keys.sorted().map { prefix + $0 }.joined(separator: ", "))")
        }
        guard let value, field == "voiceSamples" else { return }
        let missing = items(value).filter { !mediaExists($0) }
        guard missing.isEmpty else {
            throw KnowledgeError("creator.voiceSamples: no media \(missing.joined(separator: ", ")) in the open project")
        }
    }

    /// The profile from preferences (the first value of each key wins, so pass project values first): lists as
    /// arrays.
    public static func json(_ prefs: [KnowledgeValue]) -> JSONValue? {
        var profile: [String: JSONValue] = [:]
        for pref in prefs where isCreatorKey(pref.key) {
            let field = String(pref.key.dropFirst(prefix.count))
            guard profile[field] == nil else { continue }
            profile[field] = lists.contains(field) ? .array(items(pref.value).map(JSONValue.string)) : .string(pref.value)
        }
        return profile.isEmpty ? nil : .object(profile)
    }

    static func items(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
