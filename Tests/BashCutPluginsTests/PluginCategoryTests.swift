import BashCutAutomation
import BashCutPlugin
import Foundation
import Testing

struct PluginCategoryTests {
    private func manifest(capabilities: [String] = [], providers: [String] = [], category: String? = nil) -> PluginManifest {
        PluginManifest(
            id: "local.test", name: "Test", version: "0.0.1", entrypoint: "bin/run", capabilities: capabilities,
            providers: providers.map { PluginProvider(id: "local.test.\($0)", capability: $0, name: $0) },
            category: category)
    }

    @Test("The registry listing wins, then the manifest, then a guess from capabilities")
    func resolution() {
        let voice = manifest(capabilities: ["voice.synthesize"], category: "audio")
        #expect(PluginCategory.of(voice, listed: "effects") == .effects)
        #expect(PluginCategory.of(voice, listed: "unknown") == .audio)
        #expect(PluginCategory.of(voice) == .audio)
        #expect(PluginCategory.of(manifest(capabilities: ["voice.synthesize"], category: "nope")) == .voice)
        #expect(PluginCategory.of(manifest(providers: ["agent.terminal"])) == .agents)
        #expect(PluginCategory.of(manifest(capabilities: ["captions.transcribe"])) == .captions)
        #expect(PluginCategory.of(manifest(capabilities: ["audio.beats"])) == .audio)
        #expect(PluginCategory.of(manifest()) == .utilities)
        #expect(PluginCategory(id: nil) == .utilities && PluginCategory(id: "color") == .color)
    }

    @Test("Registry entries fall back to their capabilities")
    func registryEntry() {
        let listed = PluginRegistryEntry(id: "a.b", name: "A", category: "export", capabilities: ["agent.chat"], versions: [])
        let unlisted = PluginRegistryEntry(id: "a.c", name: "C", capabilities: ["agent.chat"], versions: [])
        #expect(listed.pluginCategory == .export)
        #expect(unlisted.pluginCategory == .agents)
    }

    @Test("Manifests decode an optional category")
    func decode() throws {
        let json = #"{"schema": "bashcut.plugin/1", "id": "a.b", "name": "A", "version": "1.0.0", "apiVersion": 2,"#
            + #" "entrypoint": "bin/run", "category": "color"}"#
        #expect(try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8)).category == "color")
    }

    @Test("Automation offers the same category ids, in display order")
    func automationChoices() {
        #expect(UIAction.pluginCategories == PluginCategory.allCases.map(\.rawValue))
        #expect(PluginCategory.allCases.sorted() == PluginCategory.allCases)
    }
}
