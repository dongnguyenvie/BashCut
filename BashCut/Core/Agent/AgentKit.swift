import Foundation

/// The BashCut agent kit (`bashcut-agent-kit`): editing skills for Claude Code and Codex. BashCut ships a copy in
/// `Contents/Resources/AgentKit`; Settings › Agents can point at another folder (a checkout being worked on).
///
/// A kit is a folder with `.claude-plugin/plugin.json` and `skills/<name>/SKILL.md`.
public struct AgentKit: Sendable, Equatable {
    public enum Source: String, Sendable { case bundled, folder }

    public let root: URL
    public let source: Source
    public let version: String
    /// Skill folder names, sorted.
    public let skills: [String]

    /// The kit at `root`, or nil when the folder is not a kit.
    public init?(root: URL, source: Source) {
        let manager = FileManager.default
        let manifest = root.appendingPathComponent(".claude-plugin/plugin.json")
        guard let data = try? Data(contentsOf: manifest),
            let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let skillsFolder = root.appendingPathComponent("skills", isDirectory: true)
        let names = (try? manager.contentsOfDirectory(atPath: skillsFolder.path)) ?? []
        let skills = names.filter {
            manager.fileExists(atPath: skillsFolder.appendingPathComponent("\($0)/SKILL.md").path)
        }.sorted()
        guard !skills.isEmpty else { return nil }
        self.root = root.standardizedFileURL
        self.source = source
        self.version = fields["version"] as? String ?? "0"
        self.skills = skills
    }

    public var skillsFolder: URL { root.appendingPathComponent("skills", isDirectory: true) }

    /// The chosen folder when it holds a kit, else the copy inside the app.
    public static func locate(folder: URL?, resources: URL? = Bundle.main.resourceURL) -> AgentKit? {
        if let folder, let kit = AgentKit(root: folder, source: .folder) { return kit }
        guard let resources else { return nil }
        return AgentKit(root: resources.appendingPathComponent("AgentKit", isDirectory: true), source: .bundled)
    }
}

/// Where the kit is installed for agents. Everything lives in BashCut's support folder, so the paths stay the same
/// when the app moves or updates.
public struct AgentKitInstall: Sendable {
    /// `~/Library/Application Support/BashCut`.
    public let support: URL

    public init(support: URL) { self.support = support }

    /// The kit agents read: a folder kit as it is (edits show up at once), a bundled kit copied to
    /// `agent-kit/` (refreshed when the app brings another version).
    public func stableRoot(for kit: AgentKit) throws -> AgentKit {
        guard kit.source == .bundled else { return kit }
        let destination = support.appendingPathComponent("agent-kit", isDirectory: true)
        if let installed = AgentKit(root: destination, source: .bundled), installed.version == kit.version,
            installed.skills == kit.skills
        {
            return installed
        }
        let manager = FileManager.default
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        let staging = support.appendingPathComponent(".agent-kit-\(UUID().uuidString)", isDirectory: true)
        try manager.copyItem(at: kit.root, to: staging)
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.moveItem(at: staging, to: destination)
        guard let installed = AgentKit(root: destination, source: .bundled) else {
            throw AgentKitError("The agent kit could not be installed in \(destination.path)")
        }
        return installed
    }

    /// A skills-only Claude Code plugin for BashCut's own Claude tabs (`--plugin-dir`). The tabs already get the
    /// BashCut MCP server with their session token, so the kit's own `.mcp.json` is left out.
    public func claudePlugin(for kit: AgentKit) throws -> URL {
        let manager = FileManager.default
        let folder = support.appendingPathComponent("agent-kit-claude", isDirectory: true)
        let manifestFolder = folder.appendingPathComponent(".claude-plugin", isDirectory: true)
        try manager.createDirectory(at: manifestFolder, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "name": "bashcut", "version": kit.version,
            "description": "BashCut editing skills (loaded by BashCut for its Claude tabs).",
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestFolder.appendingPathComponent("plugin.json"), options: .atomic)
        try Self.link(folder.appendingPathComponent("skills"), to: kit.skillsFolder)
        return folder
    }

    /// Links each kit skill into `folder` (an `.agents/skills` folder Codex reads). Links to another copy of the
    /// kit are replaced; files and folders that are not links are never touched. Returns the linked names.
    @discardableResult
    public static func linkSkills(of kit: AgentKit, into folder: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var linked: [String] = []
        for name in kit.skills {
            let target = folder.appendingPathComponent(name)
            if isLink(target) || !FileManager.default.fileExists(atPath: target.path) {
                try link(target, to: kit.skillsFolder.appendingPathComponent(name, isDirectory: true))
                linked.append(name)
            }
        }
        return linked
    }

    /// Removes the links in `folder` that point into a kit's `skills` folder (any copy), leaving everything else.
    @discardableResult
    public static func unlinkSkills(named names: [String], in folder: URL) -> [String] {
        names.filter { name in
            let target = folder.appendingPathComponent(name)
            guard isLink(target) else { return false }
            return (try? FileManager.default.removeItem(at: target)) != nil
        }
    }

    /// Skills of `kit` linked in `folder` to this kit.
    public static func linkedSkills(of kit: AgentKit, in folder: URL) -> [String] {
        kit.skills.filter { name in
            let target = folder.appendingPathComponent(name)
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: target.path) else {
                return false
            }
            return URL(fileURLWithPath: destination).standardizedFileURL
                == kit.skillsFolder.appendingPathComponent(name).standardizedFileURL
        }
    }

    static func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func link(_ url: URL, to destination: URL) throws {
        let manager = FileManager.default
        if isLink(url) { try manager.removeItem(at: url) }
        try manager.createSymbolicLink(at: url, withDestinationURL: destination)
    }
}

public struct AgentKitError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
