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

/// The reference clip a cloning `voice.synthesize` provider accepts (#532): 1–60 seconds and, optionally, the file
/// extensions it reads. BashCut trims saved clones into this range.
public struct PluginCloneRange: Codable, Sendable, Equatable {
    public let minSeconds: Double
    public let maxSeconds: Double
    /// File extensions (`wav`, `m4a`); nil reads the WAV files BashCut writes.
    public let formats: [String]?

    public init(minSeconds: Double, maxSeconds: Double, formats: [String]? = nil) {
        self.minSeconds = minSeconds
        self.maxSeconds = maxSeconds
        self.formats = formats
    }

    /// What a provider that only says `clones: true` accepts.
    public static let standard = PluginCloneRange(minSeconds: 3, maxSeconds: 8)

    /// Whether a reference of `seconds` fits, with a little slack for rounding.
    public func accepts(_ seconds: Double) -> Bool { seconds >= minSeconds - 0.05 && seconds <= maxSeconds + 0.05 }

    var isValid: Bool {
        guard minSeconds >= 1, minSeconds < maxSeconds, maxSeconds <= 60 else { return false }
        guard let formats else { return true }
        return !formats.isEmpty && formats.allSatisfy { !$0.isEmpty && $0.count <= 8 }
    }
}

extension PluginProvider {
    /// `count` takes capped to `maxTakes` (#410).
    public func takes(_ count: Int) -> Int { min(count, maxTakes ?? count) }

    /// The reference range this provider clones from, or nil when it does not clone: its `clone`, else 3–8 s when it
    /// only says `clones: true` (#532).
    public var cloneRange: PluginCloneRange? {
        guard capability == "voice.synthesize" else { return nil }
        if let clone { return clone }
        return clones == true ? .standard : nil
    }
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
            try validateClone(provider)
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

    /// `clone {minSeconds, maxSeconds, formats}` (#532): on voice.synthesize, 1 ≤ min < max ≤ 60, not with
    /// `clones: false`, API 9.
    private func validateClone(_ provider: PluginProvider) throws {
        guard let clone = provider.clone else { return }
        guard provider.capability == "voice.synthesize", clone.isValid, provider.clones != false else {
            throw PluginError.invalid(
                "Provider \(provider.id): clone needs 1 ≤ minSeconds < maxSeconds ≤ 60, on a voice.synthesize provider that clones")
        }
        guard apiVersion >= 9 else {
            throw PluginError.invalid("Provider \(provider.id): clone needs apiVersion 9 (feature voice.savedClones)")
        }
    }
}
