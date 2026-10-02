import Foundation

/// Resume session IDs for one project, keyed by provider ID. Encoded as a flat
/// `{"claude": "…", "codex": "…"}` object, the format earlier builds wrote.
public struct AgentSessionBookmarks: Codable, Sendable, Equatable {
    public private(set) var ids: [AgentProviderID: String]
    public init(_ ids: [AgentProviderID: String] = [:]) { self.ids = ids.filter { !$0.value.isEmpty } }

    public subscript(provider: AgentProviderID) -> String {
        get { ids[provider] ?? "" }
        set { ids[provider] = newValue.isEmpty ? nil : newValue }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer().decode([String: String].self)
        self.init(Dictionary(uniqueKeysWithValues: values.map { (AgentProviderID(rawValue: $0.key), $0.value) }))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: ids.map { ($0.key.rawValue, $0.value) }))
    }
}

public struct AgentSessionStore: Sendable {
    public let url: URL
    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BashCut/agent-sessions.json")
    }

    public func load(project: URL) throws -> AgentSessionBookmarks {
        guard FileManager.default.fileExists(atPath: url.path) else { return AgentSessionBookmarks() }
        let values = try JSONDecoder().decode([String: AgentSessionBookmarks].self, from: Data(contentsOf: url))
        return values[key(project)] ?? AgentSessionBookmarks()
    }

    public func save(_ bookmarks: AgentSessionBookmarks, project: URL) throws {
        var values: [String: AgentSessionBookmarks] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            values = try JSONDecoder().decode(
                [String: AgentSessionBookmarks].self, from: Data(contentsOf: url))
        }
        values[key(project)] = bookmarks
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(values)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func key(_ project: URL) -> String {
        project.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

public struct AgentSessionDiscovery: Sendable {
    private let roots: [AgentProviderID: URL]

    /// `roots` overrides a provider's session folder (tests); others resolve under the home folder.
    public init(roots: [AgentProviderID: URL] = [:]) {
        self.roots = roots
    }

    public func latest(
        provider: any AgentProvider, project: URL, workspace: URL, notBefore: Date? = nil
    ) -> String? {
        guard provider.isAgent,
            let root = roots[provider.id]
                ?? provider.sessionFolder.map({
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0)
                })
        else { return nil }
        let candidates = sessionFiles(in: root, notBefore: notBefore)
        let projectPath = canonical(project)
        let projectRoot = canonical(project.deletingLastPathComponent())
        let workspacePath = canonical(workspace)
        for candidate in candidates {
            guard let record = record(at: candidate) else { continue }
            let hasProject = record.strings.contains { value in
                value.contains(projectPath) || value.contains(projectRoot)
            }
            let hasWorkspace = record.strings.contains { canonicalPath($0) == workspacePath }
            if hasProject || (hasWorkspace && (provider.matchesWorkspaceSessions || notBefore != nil)) {
                return record.id
            }
        }
        return nil
    }

    private func sessionFiles(in root: URL, notBefore: Date?) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var values: [(url: URL, date: Date)] = []
        while values.count < 10_000, let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl",
                let resources = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                resources.isRegularFile == true,
                let date = resources.contentModificationDate,
                notBefore.map({ date >= $0.addingTimeInterval(-2) }) ?? true
            else { continue }
            values.append((url, date))
        }
        return values.sorted { $0.date > $1.date }.prefix(250).map(\.url)
    }

    private func record(at url: URL) -> (id: String, strings: [String])? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 512 * 1_024) else { return nil }
        var strings: [String] = []
        var identifier: String?
        for line in data.split(separator: 0x0A).prefix(80) {
            guard let value = try? JSONSerialization.jsonObject(with: Data(line)) else { continue }
            collectStrings(value, into: &strings)
            if identifier == nil { identifier = sessionID(in: value) }
        }
        if identifier == nil { identifier = url.deletingPathExtension().lastPathComponent }
        guard let identifier, UUID(uuidString: identifier) != nil else { return nil }
        return (identifier.lowercased(), strings)
    }

    private func sessionID(in value: Any) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        if let session = object["sessionId"] as? String { return session }
        if let payload = object["payload"] as? [String: Any] {
            return payload["session_id"] as? String ?? payload["id"] as? String
        }
        return nil
    }

    private func collectStrings(_ value: Any, into output: inout [String]) {
        if let string = value as? String {
            output.append(string)
        } else if let values = value as? [Any] {
            for value in values { collectStrings(value, into: &output) }
        } else if let values = value as? [String: Any] {
            for value in values.values { collectStrings(value, into: &output) }
        }
    }

    private func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func canonicalPath(_ value: String) -> String? {
        guard value.hasPrefix("/") else { return nil }
        return canonical(URL(fileURLWithPath: value))
    }
}
