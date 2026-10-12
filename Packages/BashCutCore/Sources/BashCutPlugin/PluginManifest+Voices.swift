import Foundation

/// One voice a `voice.synthesize` provider offers (P0-C7), as facts the agent picks by.
public struct PluginVoice: Codable, Sendable, Equatable {
    public let id: String
    public let language: String
    public let region: String?
    public let style: String?
    public let gender: String?
    /// Whether the provider can change this voice's speaking rate.
    public let supportsRate: Bool?
}

extension PluginProvider {
    /// `count` takes capped to `maxTakes` (#410).
    public func takes(_ count: Int) -> Int { min(count, maxTakes ?? count) }
}

extension PluginManifest {
    /// Voice facts and cloning (P0-C7) belong to `voice.synthesize` providers.
    func validateVoices() throws {
        for provider in providers ?? [] {
            if let voices = provider.voices {
                guard provider.capability == "voice.synthesize", voices.count <= 500,
                    Set(voices.map { $0.id }).count == voices.count,
                    voices.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 80 && !$0.language.isEmpty && $0.language.count <= 16 })
                else {
                    throw PluginError.invalid("Provider \(provider.id): voices need unique IDs and a language, on voice.synthesize")
                }
            }
            if provider.clones != nil, provider.capability != "voice.synthesize" {
                throw PluginError.invalid("Provider \(provider.id): clones is for voice.synthesize")
            }
            if let maxTakes = provider.maxTakes {
                guard provider.capability == "voice.synthesize", (1...8).contains(maxTakes) else {
                    throw PluginError.invalid("Provider \(provider.id): maxTakes is 1–8, for voice.synthesize")
                }
                guard apiVersion >= 8 else {
                    throw PluginError.invalid("Provider \(provider.id): maxTakes needs apiVersion 8 (feature voice.maxTakes)")
                }
            }
        }
    }
}
