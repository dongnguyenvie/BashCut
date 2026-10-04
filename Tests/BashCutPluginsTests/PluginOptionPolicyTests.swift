import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Testing

struct PluginOptionPolicyTests {
    private let options = [
        PluginOption(id: "provider", title: "Provider", type: .string, default: .string("anthropic"), bindsSecrets: true),
        PluginOption(id: "baseUrl", title: "Endpoint", type: .string, scope: .project, bindsSecrets: true),
        PluginOption(id: "model", title: "Model", type: .string),
        PluginOption(id: "apiKey", title: "API key", type: .secret)
    ]

    @Test("All options of credential-bearing plugins require the user, even non-secret project options")
    func permissions() throws {
        try PluginOptionPolicy.validateEdit(options: options, author: .user)
        #expect(throws: (any Error).self) { try PluginOptionPolicy.validateEdit(options: options, author: .agent) }
        #expect(throws: (any Error).self) { try PluginOptionPolicy.validateEdit(options: options, author: .external) }
        for option in options { #expect(PluginOptionPolicy.scope(of: option, in: options) == .user) }
        let ordinary = Array(options.prefix(3))
        try PluginOptionPolicy.validateEdit(options: ordinary, author: .agent)
        #expect(PluginOptionPolicy.scope(of: ordinary[1], in: ordinary) == .project)
    }

    @Test("A key never follows a changed provider or endpoint, nor falls back to a legacy key")
    func binding() throws {
        let store = PluginSecretStore(keychain: false)
        let original = PluginOptionPolicy.secretBinding(options: options, userValues: [:])
        let provider = PluginOptionPolicy.secretBinding(options: options, userValues: ["provider": .string("compatible")])
        let endpoint = PluginOptionPolicy.secretBinding(options: options, userValues: [
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
        #expect(PluginOptionPolicy.secretBinding(options: options, userValues: ["model": .string("other")]) == original)
        try store.write("", plugin: "example", option: "apiKey", binding: endpoint)
        #expect(store.read(plugin: "example", option: "apiKey", binding: endpoint).isEmpty)
    }

    @Test("Binding follows manifest declarations, not option names")
    func declaredBinding() throws {
        let undeclared = [
            PluginOption(id: "provider", title: "Provider", type: .string),
            PluginOption(id: "baseUrl", title: "Endpoint", type: .string),
            PluginOption(id: "apiKey", title: "API key", type: .secret)
        ]
        #expect(PluginOptionPolicy.secretBinding(options: undeclared, userValues: [:]) == nil)
        let region = [
            PluginOption(id: "region", title: "Region", type: .enumeration, choices: ["eu", "us"], bindsSecrets: true),
            PluginOption(id: "token", title: "Token", type: .secret)
        ]
        let eu = PluginOptionPolicy.secretBinding(options: region, userValues: [:])
        #expect(eu != nil)
        #expect(PluginOptionPolicy.secretBinding(options: region, userValues: ["region": .string("us")]) != eu)
    }

    @Test("Saving a key for new code removes only that installation's older-code keys")
    func staleKeys() throws {
        let store = PluginSecretStore(keychain: false)
        try store.write("old", plugin: "a@root@old", option: "apiKey", binding: "x")
        try store.write("old-token", plugin: "a@root@old", option: "token")
        try store.write("other", plugin: "a@elsewhere@old", option: "apiKey", binding: "x")
        try store.write("new", plugin: "a@root@new", option: "apiKey", binding: "x")
        try store.write("new-other-endpoint", plugin: "a@root@new", option: "apiKey", binding: "y")
        store.removeStale(option: "apiKey", prefix: "a@root@", keeping: "a@root@new")
        #expect(store.read(plugin: "a@root@old", option: "apiKey", binding: "x").isEmpty)
        #expect(store.read(plugin: "a@root@old", option: "token") == "old-token")
        #expect(store.read(plugin: "a@elsewhere@old", option: "apiKey", binding: "x") == "other")
        #expect(store.read(plugin: "a@root@new", option: "apiKey", binding: "x") == "new")
        #expect(store.read(plugin: "a@root@new", option: "apiKey", binding: "y") == "new-other-endpoint")
    }
}
