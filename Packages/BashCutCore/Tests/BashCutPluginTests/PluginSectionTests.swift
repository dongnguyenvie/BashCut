import BashCutPlugin
import Testing

struct PluginSectionTests {
    private let categories: [String: PluginCategory] = [
        "director": .agents, "whisper": .captions, "vieneu": .voice, "silence": .audio, "loudness": .audio,
        "tool": .utilities,
    ]

    private func category(_ id: String) -> PluginCategory { categories[id] ?? .utilities }

    @Test("Sections follow category order, skip empty categories and keep item order")
    func byCategory() {
        let sections = PluginSection.byCategory(["tool", "silence", "director", "loudness"], category: category)
        #expect(sections.map(\.kind) == [.category(.agents), .category(.audio), .category(.utilities)])
        #expect(sections[1].items == ["silence", "loudness"])
        #expect(sections.map(\.id) == ["agents", "audio", "utilities"])
        #expect(PluginSection<String>.byCategory([], category: category).isEmpty)
    }

    @Test("Installed: updates first, then attention, then categories; each plugin once")
    func installed() {
        let sections = PluginSection.installed(
            ["director", "whisper", "vieneu", "silence", "tool"],
            updating: { ["vieneu", "silence"].contains($0) },
            needsAttention: { ["whisper", "silence"].contains($0) }, category: category)
        #expect(sections.map(\.id) == ["updates", "attention", "agents", "utilities"])
        #expect(sections[0].items == ["vieneu", "silence"])
        #expect(sections[1].items == ["whisper"])
        #expect(sections.flatMap(\.items).sorted() == ["director", "silence", "tool", "vieneu", "whisper"])
    }

    @Test("Installed without updates or problems is only categories")
    func installedQuiet() {
        let sections = PluginSection.installed(
            ["whisper", "director"], updating: { _ in false }, needsAttention: { _ in false }, category: category)
        #expect(sections.map(\.kind) == [.category(.agents), .category(.captions)])
    }

    @Test("Untrusted, changed, outdated and a degraded ready plugin need attention; turned off does not")
    func attention() {
        let degraded = PluginHealth(pluginID: "a.b", state: .degraded, dependencies: [])
        let ready = PluginHealth(pluginID: "a.b", state: .ready, dependencies: [])
        #expect(PluginAvailability.untrusted.needsAttention(health: nil))
        #expect(PluginAvailability.changed.needsAttention(health: ready))
        #expect(PluginAvailability.outdated("Update BashCut").needsAttention(health: nil))
        #expect(PluginAvailability.ready.needsAttention(health: degraded))
        #expect(!PluginAvailability.ready.needsAttention(health: ready))
        #expect(!PluginAvailability.ready.needsAttention(health: nil))
        #expect(!PluginAvailability.disabled.needsAttention(health: degraded))
    }

    @Test("Registry search combines text, capability and category")
    func registryFilter() {
        let whisper = PluginRegistryEntry(
            id: "bashcut.whisper", name: "Whisper", category: "captions", capabilities: ["captions.transcribe"], versions: [])
        let director = PluginRegistryEntry(id: "bashcut.director", name: "Director", capabilities: ["agent.chat"], versions: [])
        #expect(whisper.matches("", capability: nil, category: .captions))
        #expect(!whisper.matches("", capability: nil, category: .voice))
        #expect(director.matches("dir", capability: "agent.chat", category: .agents))
        #expect(!director.matches("dir", capability: "captions.transcribe", category: nil))
        #expect(!director.matches("whisper", capability: nil, category: .agents))
    }
}
