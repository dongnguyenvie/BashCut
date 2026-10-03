import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Testing

struct PluginOptionPolicyTests {
    private let options = [
        PluginOption(id: "provider", title: "Provider", type: .string, default: .string("anthropic")),
        PluginOption(id: "baseUrl", title: "Endpoint", type: .string, scope: .project),
        PluginOption(id: "apiKey", title: "API key", type: .secret)
    ]

    @Test("All options of credential-bearing plugins require the user, even non-secret project options")
    func permissions() throws {
        try PluginOptionPolicy.validateEdit(options: options, author: .user)
        #expect(throws: (any Error).self) { try PluginOptionPolicy.validateEdit(options: options, author: .agent) }
        #expect(throws: (any Error).self) { try PluginOptionPolicy.validateEdit(options: options, author: .external) }
        for option in options { #expect(PluginOptionPolicy.scope(of: option, in: options) == .user) }
        let ordinary = Array(options.prefix(2))
        try PluginOptionPolicy.validateEdit(options: ordinary, author: .agent)
        #expect(PluginOptionPolicy.scope(of: ordinary[1], in: ordinary) == .project)
    }

    @Test("A key never follows a changed provider or endpoint, nor falls back to a legacy key")
    func binding() throws {
        let store = PluginSecretStore(keychain: false)
        let original = PluginOptionPolicy.endpointBinding(options: options, userValues: [:])
        let provider = PluginOptionPolicy.endpointBinding(options: options, userValues: ["provider": .string("compatible")])
        let endpoint = PluginOptionPolicy.endpointBinding(options: options, userValues: [
            "provider": .string("compatible"), "baseUrl": .string("https://example.com/v1")
        ])
        try store.write("legacy-key", plugin: "example", option: "apiKey")
        #expect(store.read(plugin: "example", option: "apiKey", binding: original).isEmpty)
        try store.write("provider-key", plugin: "example", option: "apiKey", binding: original)
        #expect(store.read(plugin: "example", option: "apiKey", binding: provider).isEmpty)
        #expect(store.read(plugin: "example", option: "apiKey", binding: endpoint).isEmpty)
        try store.write("endpoint-key", plugin: "example", option: "apiKey", binding: endpoint)
        #expect(store.read(plugin: "example", option: "apiKey", binding: original) == "provider-key")
        #expect(store.read(plugin: "example", option: "apiKey", binding: endpoint) == "endpoint-key")
        #expect(PluginOptionPolicy.endpointBinding(options: options, userValues: ["model": .string("other")]) == original)
        try store.write("", plugin: "example", option: "apiKey", binding: endpoint)
        #expect(store.read(plugin: "example", option: "apiKey", binding: endpoint).isEmpty)
    }
}
