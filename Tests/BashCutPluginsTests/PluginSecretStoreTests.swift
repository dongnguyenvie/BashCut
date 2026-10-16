import BashCutPlugins
import Foundation
import Testing

struct PluginSecretStoreTests {
    @Test("Secrets are written to the file owner-only and read back by a new store")
    func fileRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("plugin-secrets.json")
        try PluginSecretStore(file: file).write("sk-1", plugin: "a@root@1", option: "apiKey", binding: "x")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let reopened = PluginSecretStore(file: file)
        #expect(reopened.read(plugin: "a@root@1", option: "apiKey", binding: "x") == "sk-1")
        try reopened.write("", plugin: "a@root@1", option: "apiKey", binding: "x")
        #expect(PluginSecretStore(file: file).read(plugin: "a@root@1", option: "apiKey", binding: "x").isEmpty)
    }
}
