import BashCutProject
import Foundation

/// What the user said when cloning a voice: `own` (my own voice) or `permission` (I have the speaker's permission).
public enum VoiceConsentStatement: String, Codable, Sendable, CaseIterable { case own, permission }

/// A saved cloned voice ("My voices", #532): a name, the trimmed reference clip next to it, the language, the
/// providers that could clone it when it was made, and who agreed to the cloning and how.
public struct VoiceClone: Codable, Sendable, Equatable, Identifiable {
    public struct Consent: Codable, Sendable, Equatable {
        public var by: String
        public var at: Date
        public var statement: VoiceConsentStatement

        public init(by: String, at: Date = Date(), statement: VoiceConsentStatement) {
            self.by = by
            self.at = at
            self.statement = statement
        }
    }

    public var id: String
    public var name: String
    public var language: String
    /// Provider IDs that could clone from this reference when it was saved.
    public var providers: [String]
    public var createdAt: Date
    public var sourceDescription: String
    public var durationSeconds: Double
    public var consent: Consent
    /// The reference file name inside the clone's folder (`reference.wav`).
    public var reference: String

    public init(
        id: String, name: String, language: String, providers: [String], createdAt: Date = Date(),
        sourceDescription: String, durationSeconds: Double, consent: Consent, reference: String
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.providers = providers
        self.createdAt = createdAt
        self.sourceDescription = sourceDescription
        self.durationSeconds = durationSeconds
        self.consent = consent
        self.reference = reference
    }
}

/// "My voices" (#532): one folder per clone under the user's BashCut folder, `Voices/<id>/voice.json` and
/// `reference.<ext>`, the same in every project.
public final class VoiceCloneStore: @unchecked Sendable {
    public static let shared = VoiceCloneStore(
        root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BashCut/Voices", isDirectory: true))

    public let root: URL
    private let lock = NSLock()

    public init(root: URL) { self.root = root }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Every saved clone, newest first; folders without a readable voice.json or reference are skipped.
    public func list() -> [VoiceClone] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { read($0) }.sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    public func clone(_ id: String) -> VoiceClone? {
        guard Self.isID(id) else { return nil }
        return read(root.appendingPathComponent(id, isDirectory: true))
    }

    /// The reference clip of a saved clone.
    public func referenceURL(_ clone: VoiceClone) -> URL {
        root.appendingPathComponent(clone.id, isDirectory: true).appendingPathComponent(clone.reference)
    }

    private func read(_ folder: URL) -> VoiceClone? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("voice.json")),
            let clone = try? Self.decoder.decode(VoiceClone.self, from: data), clone.id == folder.lastPathComponent,
            FileManager.default.fileExists(atPath: referenceURL(clone).path)
        else { return nil }
        return clone
    }

    /// The ID a new clone named `name` gets: `clone-<slug>`, with `-2`, `-3`… when taken.
    public func newID(for name: String) -> String {
        let base = "clone-" + Self.slug(name)
        var id = base, index = 2
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path) {
            id = "\(base)-\(index)"
            index += 1
        }
        return id
    }

    /// Saves a clone: copies `reference` into its folder as `reference.<ext>` and writes voice.json. The ID, created
    /// date and reference name of `draft` are set here.
    @discardableResult
    public func add(_ draft: VoiceClone, reference: URL) throws -> VoiceClone {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw ProjectError.invalid("Give the voice a name (up to 80 characters)") }
        return try lock.withLock {
            var clone = draft
            clone.name = name
            clone.id = newID(for: name)
            let ext = reference.pathExtension.isEmpty ? "wav" : reference.pathExtension.lowercased()
            clone.reference = "reference." + ext
            let folder = root.appendingPathComponent(clone.id, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try FileManager.default.copyItem(at: reference, to: folder.appendingPathComponent(clone.reference))
                try Self.encoder.encode(clone).write(to: folder.appendingPathComponent("voice.json"), options: .atomic)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
            return clone
        }
    }

    /// Removes a saved clone and its reference clip.
    public func remove(_ id: String) throws {
        guard let clone = clone(id) else { throw ProjectError.invalid("No saved voice \(id)") }
        try lock.withLock { try FileManager.default.removeItem(at: root.appendingPathComponent(clone.id, isDirectory: true)) }
    }

    static func isID(_ id: String) -> Bool {
        id.hasPrefix("clone-") && id.count <= 100 && id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil
    }

    /// Lowercase ASCII letters and digits joined by `-` ("Giọng Nolan" → `giong-nolan`); `voice` when nothing is left.
    public static func slug(_ name: String) -> String {
        let latin = name.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? name
        let words = latin.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        let slug = words.joined(separator: "-")
        return slug.isEmpty ? "voice" : String(slug.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
