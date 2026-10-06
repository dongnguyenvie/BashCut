import BashCutPlugin
import BashCutProject
import Foundation

/// `library.search` (#81): library items a provider found for a panel (sounds, stickers, looks…), with their files
/// downloaded into the request folder.
public struct LibrarySearchCapability: CapabilityAdapter {
    public static let capability = PluginAPI.librarySearch
    public let kind: LibraryKind
    public let query: String
    public let limit: Int
    public let page: Int
    public let language: String
    public let outputRoot: URL?

    public init(kind: LibraryKind, query: String, limit: Int = 12, page: Int = 1, language: String = "en", outputRoot: URL) {
        self.kind = kind
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.limit = limit
        self.page = page
        self.language = language
        self.outputRoot = outputRoot
    }

    public func validate() throws {
        guard !query.isEmpty, query.count <= 500 else { throw PluginError.invalid("Search text must be 1–500 characters") }
        try LibraryCandidateParser.checkLimit(limit)
        guard (1...1_000).contains(page) else { throw PluginError.invalid("page must be 1...1000") }
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object([
            "kind": .string(kind.rawValue), "query": .string(query), "limit": .integer(limit), "page": .integer(page),
            "language": .string(language), "outputDirectory": .string(outputDirectory?.path ?? ""),
        ])
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> GeneratedLibraryCandidates {
        try LibraryCandidateParser.output(result, capability: Self.capability, kind: kind, limit: limit, context: context)
    }
}

/// `library.generate` (#81): new library items a provider made from a prompt (AI music, stickers…), written into the
/// request folder.
public struct LibraryGenerateCapability: CapabilityAdapter {
    public static let capability = PluginAPI.libraryGenerate
    public let kind: LibraryKind
    public let prompt: String
    public let limit: Int
    /// Hints for the provider, such as a length in seconds or a style; passed through as `params`.
    public let hints: [String: JSONValue]
    public let language: String
    public let outputRoot: URL?

    public init(
        kind: LibraryKind, prompt: String, limit: Int = 4, hints: [String: JSONValue] = [:], language: String = "en",
        outputRoot: URL
    ) {
        self.kind = kind
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.limit = limit
        self.hints = hints
        self.language = language
        self.outputRoot = outputRoot
    }

    public func validate() throws {
        guard !prompt.isEmpty, prompt.count <= 4_000 else { throw PluginError.invalid("The prompt must be 1–4000 characters") }
        try LibraryCandidateParser.checkLimit(limit)
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object([
            "kind": .string(kind.rawValue), "prompt": .string(prompt), "limit": .integer(limit), "params": .object(hints),
            "language": .string(language), "outputDirectory": .string(outputDirectory?.path ?? ""),
        ])
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> GeneratedLibraryCandidates {
        try LibraryCandidateParser.output(result, capability: Self.capability, kind: kind, limit: limit, context: context)
    }
}

/// One item a library provider offered: library item fields, with `file` and `preview` relative to `directory`
/// (the request folder). Saving it (`library add --from-result`) copies the files into the library.
public struct LibraryCandidate: Sendable, Equatable {
    public var item: LibraryItem
    public let directory: URL

    public var fileURL: URL? { item.file.map { directory.appendingPathComponent($0) } }
    public var previewURL: URL? { item.preview.map { directory.appendingPathComponent($0) } }

    /// The candidate as job results list it: its fields, its `index` and the files' absolute paths.
    public func json(index: Int) -> JSONValue {
        var fields = item.fields
        fields["index"] = .integer(index)
        fields["panel"] = item.kind.map { .string($0.panel) } ?? .null
        fields["fileURL"] = fileURL.map { .string($0.path) } ?? .null
        fields["previewURL"] = previewURL.map { .string($0.path) } ?? .null
        return .object(fields)
    }

    /// The fields to save as a new library item: everything but the ID, kind, name, files and what the store manages.
    public var changes: [String: JSONValue] {
        var fields = item.fields
        for key in ["id", "kind", "name", "file", "preview", "version", "createdBy"] + LibraryStore.managedKeys {
            fields[key] = nil
        }
        return fields
    }

    /// The candidate `index` of a `library.search` or `library.generate` job result.
    public init(jobResult: JSONValue, index: Int) throws {
        let candidates = jobResult.object["candidates"]?.array ?? []
        guard candidates.indices.contains(index) else {
            throw PluginError.invalid("No candidate \(index); the result has \(candidates.count) (counting from 0)")
        }
        var fields = candidates[index].object
        guard let directory = jobResult.object["directory"]?.string else {
            throw PluginError.invalid("The job result has no candidate folder")
        }
        for key in ["index", "panel", "fileURL", "previewURL"] { fields[key] = nil }
        self.init(item: LibraryItem(fields: fields), directory: URL(fileURLWithPath: directory, isDirectory: true))
        for url in [fileURL, previewURL].compactMap({ $0 }) where !FileManager.default.fileExists(atPath: url.path) {
            throw PluginError.invalid("\(url.lastPathComponent) is gone; search or generate again")
        }
    }

    public init(item: LibraryItem, directory: URL) {
        self.item = item
        self.directory = directory
    }
}

/// What a library provider returned, checked.
public struct GeneratedLibraryCandidates: Sendable {
    public let capability: String
    public let kind: LibraryKind
    public let candidates: [LibraryCandidate]
    /// The request folder holding their files.
    public let directory: URL
    public let provenance: PluginProvenance

    /// The job result of `library search` and `library generate`.
    public var json: JSONValue {
        var provider = provenance.json
        provider["capability"] = .string(capability)
        return .object([
            "kind": .string(kind.rawValue), "provider": .object(provider), "directory": .string(directory.path),
            "candidates": .array(candidates.enumerated().map { $0.element.json(index: $0.offset) }),
        ])
    }
}

/// Reads `{"items": [...]}` from a library provider: at most `limit` library item objects of the asked kind whose
/// `file` and `preview` are in the request folder. A missing or repeated `id` becomes `candidate-<n>`.
enum LibraryCandidateParser {
    static let limits = 1...50

    static func checkLimit(_ limit: Int) throws {
        guard limits.contains(limit) else { throw PluginError.invalid("limit must be 1...50") }
    }

    static func output(
        _ result: JSONValue, capability: String, kind: LibraryKind, limit: Int, context: CapabilityContext
    ) throws -> GeneratedLibraryCandidates {
        guard let directory = context.outputDirectory else { throw PluginError.invalid("Library provider has no request directory") }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let candidates = try parse(result, kind: kind, limit: limit, root: root, context: context)
        return GeneratedLibraryCandidates(
            capability: capability, kind: kind, candidates: candidates, directory: root, provenance: context.provenance)
    }

    static func parse(
        _ result: JSONValue, kind: LibraryKind, limit: Int, root: URL, context: CapabilityContext
    ) throws -> [LibraryCandidate] {
        guard case .array(let values) = result.object["items"] ?? .null, values.count <= limit else {
            throw PluginError.invalid("Library provider must return an items array of at most \(limit)")
        }
        var ids: Set<String> = []
        return try values.enumerated().map { index, value in
            var fields = value.object
            let label = "Library provider item \(index)"
            guard !fields.isEmpty else { throw PluginError.invalid("\(label) is not an object") }
            if let given = fields["kind"]?.string, given != kind.rawValue {
                throw PluginError.invalid("\(label) is \(given), not the \(kind.rawValue) asked for")
            }
            fields["kind"] = .string(kind.rawValue)
            fields["version"] = .integer(1)
            for key in ["createdBy", "basedOn", "history", "createdAt", "updatedAt", "fileSHA256"] { fields[key] = nil }
            let id = fields["id"]?.string ?? ""
            if id.range(of: StyleCatalog.idPattern, options: .regularExpression) == nil || !ids.insert(id).inserted {
                fields["id"] = .string("candidate-\(index + 1)")
                ids.insert("candidate-\(index + 1)")
            }
            for key in ["file", "preview"] {
                guard let value = fields[key] else { continue }
                guard let path = value.string else { throw PluginError.invalid("\(label): \(key) must be a path") }
                let url = try context.confinedOutput(path, label: label)
                fields[key] = .string(String(url.path.dropFirst(root.path.count + 1)))
            }
            let item = LibraryItem(fields: fields)
            do { try item.validate(root: root) } catch {
                throw PluginError.invalid("\(label): \(error.localizedDescription)")
            }
            return LibraryCandidate(item: item, directory: root)
        }
    }

    /// Removes request folders older than `age` seconds under `root`.
    static func prune(_ root: URL, olderThan age: TimeInterval = 86_400, now: Date = Date()) {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
        else { return }
        for folder in folders {
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > age { try? manager.removeItem(at: folder) }
        }
    }
}

extension CapabilityService {
    /// Runs `library.search` with a provider that serves `kind`. `provider` is a provider or plugin ID; when given it
    /// must be available.
    public func searchLibrary(
        kind: LibraryKind, query: String, limit: Int = 12, page: Int = 1, language: String = "en", provider: String?,
        projectRoot: URL?, outputRoot: URL = PluginFolders.libraryCandidates
    ) async throws -> GeneratedLibraryCandidates {
        let adapter = LibrarySearchCapability(
            kind: kind, query: query, limit: limit, page: page, language: language, outputRoot: outputRoot)
        return try await runLibraryProvider(adapter, kind: kind, provider: provider, projectRoot: projectRoot)
    }

    /// Runs `library.generate` with a provider that serves `kind`.
    public func generateLibrary(
        kind: LibraryKind, prompt: String, limit: Int = 4, hints: [String: JSONValue] = [:], language: String = "en",
        provider: String?, projectRoot: URL?, outputRoot: URL = PluginFolders.libraryCandidates
    ) async throws -> GeneratedLibraryCandidates {
        let adapter = LibraryGenerateCapability(
            kind: kind, prompt: prompt, limit: limit, hints: hints, language: language, outputRoot: outputRoot)
        return try await runLibraryProvider(adapter, kind: kind, provider: provider, projectRoot: projectRoot)
    }

    private func runLibraryProvider<Adapter: CapabilityAdapter>(
        _ adapter: Adapter, kind: LibraryKind, provider: String?, projectRoot: URL?
    ) async throws -> Adapter.Output {
        try adapter.validate()
        if let root = adapter.outputRoot { LibraryCandidateParser.prune(root) }
        let preferred = provider.map { id in
            catalog(projectRoot: projectRoot).plugins.first { $0.id == id }.flatMap { plugin in
                plugin.manifest.providers?.first { $0.capability == Adapter.capability && $0.serves(kind) }?.id
            } ?? id
        }
        let resolved = try await resolve(Adapter.capability, preferredProvider: preferred, projectRoot: projectRoot, kind: kind)
        if let preferred, resolved.provider.id != preferred {
            throw PluginError.invalid("\(provider ?? preferred) cannot \(Adapter.capability) \(kind.rawValue) items now")
        }
        return try await run(adapter, using: resolved)
    }

    /// Library providers in `plugins` for `capability` that serve `kind`, as `pluginID`/`providerID` pairs.
    public static func libraryProviders(
        _ capability: String, kind: LibraryKind, in plugins: [InstalledPlugin]
    ) -> [ResolvedPluginProvider] {
        plugins.flatMap { plugin in
            (plugin.manifest.providers ?? []).filter { $0.capability == capability && $0.serves(kind) }
                .map { ResolvedPluginProvider(plugin: plugin, provider: $0) }
        }
    }
}
