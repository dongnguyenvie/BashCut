import CryptoKit
import Foundation

/// Who vouches for a registry archive, from its ed25519 signature over the archive's SHA-256 digest.
public enum PluginPublisherTrust: Sendable, Equatable {
    /// Signed with the BashCut key compiled into the app.
    case firstParty
    /// Signed with a key the registry lists for the plugin's publisher.
    case verifiedPublisher(String)
    /// No signature: only the registry checksum and the user's approval vouch for it.
    case unsigned

    public var name: String {
        switch self {
        case .firstParty: "first-party"
        case .verifiedPublisher: "verified-publisher"
        case .unsigned: "unsigned"
        }
    }
}

/// ed25519 signatures on plugin archives (`ed25519:BASE64` for keys and signatures). The signed message is the
/// 32 raw bytes of the archive's SHA-256, so CI signs the digest it already publishes.
public enum PluginSignature {
    /// Public keys of the `bashcut` publisher. The registry cannot add to this list: only an app release can.
    /// To rotate, ship the new key here first, sign with it, and keep the old key for one release cycle.
    public static let firstPartyKeys = ["ed25519:q+RG+vvYLwP2xxRtVjNxPCbb3LhvuRyKNxSx3c1p6C4="]

    /// Checks `signature` on the archive with SHA-256 `digest` (hex). A present but wrong signature throws, so a
    /// tampered registry cannot fall back to "unsigned"; a missing one is `.unsigned`.
    public static func verify(
        digest: String, signature: String?, publisher: String?, registryKeys: [String],
        firstPartyKeys: [String] = firstPartyKeys
    ) throws -> PluginPublisherTrust {
        guard let signature, !signature.isEmpty else { return .unsigned }
        guard let message = Data(hex: digest), message.count == 32 else {
            throw PluginError.invalid("The registry checksum is not a SHA-256 digest")
        }
        guard let signatureBytes = decode(signature) else {
            throw PluginError.invalid("The archive signature is malformed")
        }
        if firstPartyKeys.contains(where: { valid(signatureBytes, message, key: $0) }) { return .firstParty }
        if let publisher, registryKeys.contains(where: { valid(signatureBytes, message, key: $0) }) {
            return .verifiedPublisher(publisher)
        }
        throw PluginError.invalid("The archive signature does not match its publisher's key")
    }

    /// `ed25519:BASE64` signature of `digest` (hex) with a raw 32-byte private key; used by tests and tools.
    public static func sign(digest: String, privateKey: Data) throws -> String {
        guard let message = Data(hex: digest) else { throw PluginError.invalid("Invalid digest") }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        return "ed25519:" + (try key.signature(for: message)).base64EncodedString()
    }

    public static func publicKey(of privateKey: Data) throws -> String {
        "ed25519:" + (try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)).publicKey
            .rawRepresentation.base64EncodedString()
    }

    private static func valid(_ signature: Data, _ message: Data, key: String) -> Bool {
        guard let raw = decode(key), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(signature, for: message)
    }

    private static func decode(_ text: String) -> Data? {
        guard text.hasPrefix("ed25519:") else { return nil }
        return Data(base64Encoded: String(text.dropFirst("ed25519:".count)))
    }
}

extension Data {
    init?(hex: String) {
        let characters = Array(hex)
        guard characters.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(characters.count / 2)
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let byte = UInt8(String(characters[index...index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.init(bytes)
    }
}
