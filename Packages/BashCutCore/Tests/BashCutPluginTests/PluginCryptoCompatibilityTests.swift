import BashCutPlugin
import Foundation
import Testing

@Suite("Portable plugin signature compatibility")
struct PluginCryptoCompatibilityTests {
    @Test("Archive signatures retain their Ed25519 wire representation and reject another digest")
    func signatureVector() throws {
        // Public RFC 8032 test seed. OpenSSL independently signed the raw SHA-256 abc digest for this fixture.
        let seed = Data([
            0x9d, 0x61, 0xb1, 0x9d, 0xef, 0xfd, 0x5a, 0x60, 0xba, 0x84, 0x4a, 0xf4, 0x92, 0xec, 0x2c, 0xc4,
            0x44, 0x49, 0xc5, 0x69, 0x7b, 0x32, 0x69, 0x19, 0x70, 0x3b, 0xac, 0x03, 0x1c, 0xae, 0x7f, 0x60,
        ])
        let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let signature = "ed25519:CW9VadgH7orHsZE9pwzwqrM1wlj0uUyPIQ3RQel0OSfI0aazeIcqcslEbB915tx7Le+YvQwhS+ZwbUh5H1doCg=="
        let key = "ed25519:11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
        #expect(try PluginSignature.sign(digest: digest, privateKey: seed) == signature)
        #expect(try PluginSignature.publicKey(of: seed) == key)
        #expect(try PluginSignature.verify(
            digest: digest, signature: signature, publisher: "fixture", registryKeys: [key]) == .verifiedPublisher("fixture"))
        #expect(throws: PluginError.self) {
            try PluginSignature.verify(
                digest: String(repeating: "0", count: 64), signature: signature, publisher: "fixture", registryKeys: [key])
        }
    }
}
