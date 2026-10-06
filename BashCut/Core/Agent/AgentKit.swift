import BashCutPlugin
import CryptoKit
import Foundation

/// The BashCut agent kit (`bashcut-agent-kit`): editing skills for Claude Code and Codex. BashCut ships a copy in
/// `Contents/Resources/AgentKit`, can download newer releases (`AgentKitUpdater`), and Settings › Agents can point
/// at another folder (a checkout being worked on).
///
/// A kit is a folder with `.claude-plugin/plugin.json` and `skills/<name>/SKILL.md`.
public struct AgentKit: Sendable, Equatable {
    public enum Source: String, Sendable { case bundled, downloaded, folder }

    public let root: URL
    public let source: Source
    public let version: String
    /// The plugin name in `plugin.json` (`bc`; `bashcut` before kit 0.1.0). Claude Code and Codex show the skills
    /// as `<name>:<skill>`.
    public let name: String
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
        self.name = fields["name"] as? String ?? "bashcut"
        self.skills = skills
    }

    public var skillsFolder: URL { root.appendingPathComponent("skills", isDirectory: true) }

    /// The name a skill is linked under in a shared skills folder such as `~/.agents/skills`: `bc-audio-mix`, so a
    /// short skill name cannot clash with another skill's folder. Kits before 0.1.0 already carry the prefix.
    public func linkName(_ skill: String) -> String {
        skill.hasPrefix("\(name)-") ? skill : "\(name)-\(skill)"
    }

    /// The Claude Code plugin ID of this kit installed from its marketplace.
    public var claudePluginID: String { "\(name)@\(AgentKitSetup.marketplace)" }

    /// The text of a skill's SKILL.md; nil when the kit has no such skill.
    public func skillText(_ skill: String) -> String? {
        guard skills.contains(skill) else { return nil }
        return try? String(contentsOf: skillsFolder.appendingPathComponent("\(skill)/SKILL.md"), encoding: .utf8)
    }

    /// The `description:` line of a skill's front matter.
    public func description(of skill: String) -> String {
        let url = skillsFolder.appendingPathComponent("\(skill)/SKILL.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let line = text.split(separator: "\n", maxSplits: 30).first { $0.hasPrefix("description:") }
        return line.map { String($0.dropFirst("description:".count)).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// Hash the distributed content, including helper scripts and hidden manifests. Version strings alone do
    /// not identify a kit during development. Length-delimited paths and bytes make additions/deletions visible.
    func contentHash() throws -> String {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let files = manager.enumerator(atPath: root.path) else {
            throw AgentKitError("Cannot read the agent kit at \(root.path)")
        }
        var paths: [String] = []
        for case let path as String in files {
            let file = root.appendingPathComponent(path)
            if [".git", "__pycache__", ".DS_Store"].contains(file.lastPathComponent) {
                files.skipDescendants()
                continue
            }
            let values = try file.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { throw AgentKitError("Bundled agent kits must not contain symbolic links") }
            if values.isRegularFile == true { paths.append(path) }
        }
        var hash = SHA256()
        for path in paths.sorted() {
            let url = root.appendingPathComponent(path)
            let data = try Data(contentsOf: url)
            let executable = manager.isExecutableFile(atPath: url.path) ? "x" : "-"
            hash.update(data: Data("\(path.utf8.count):\(path):\(executable):\(data.count):".utf8))
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The chosen folder when it holds a kit, else the newer of the copy inside the app and the newest downloaded
    /// release (the app's copy on a tie, since it shipped with this build).
    public static func locate(folder: URL?, resources: URL? = Bundle.main.resourceURL, support: URL? = nil) -> AgentKit? {
        if let folder, let kit = AgentKit(root: folder, source: .folder) { return kit }
        let bundled = resources.flatMap {
            AgentKit(root: $0.appendingPathComponent("AgentKit", isDirectory: true), source: .bundled)
        }
        guard let downloaded = support.flatMap({ AgentKitUpdater.downloaded(in: $0).first }) else { return bundled }
        guard let bundled else { return downloaded }
        return (SemanticVersion(downloaded.version) ?? .zero) > (SemanticVersion(bundled.version) ?? .zero)
            ? downloaded : bundled
    }
}

/// Where the kit is installed for agents. Everything lives in BashCut's support folder, so the paths stay the same
/// when the app moves or updates.
public struct AgentKitInstall: Sendable {
    /// `~/Library/Application Support/BashCut`.
    public let support: URL

    public init(support: URL) { self.support = support }

    /// The kit agents read: a folder kit as it is (edits show up at once), a bundled or downloaded kit copied to
    /// `agent-kit/` (refreshed whenever distributed content changes), so agents keep one path across updates.
    public func stableRoot(for kit: AgentKit) throws -> AgentKit {
        guard kit.source != .folder else { return kit }
        let destination = support.appendingPathComponent("agent-kit", isDirectory: true)
        let contentHash = try kit.contentHash()
        if let installed = AgentKit(root: destination, source: kit.source), installed.version == kit.version,
            installed.skills == kit.skills, (try? installed.contentHash()) == contentHash
        {
            return installed
        }
        let manager = FileManager.default
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        let staging = support.appendingPathComponent(".agent-kit-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: kit.root, to: staging)
        guard let staged = AgentKit(root: staging, source: kit.source), try staged.contentHash() == contentHash else {
            throw AgentKitError("The agent kit changed while it was being copied; retry setup")
        }
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try manager.moveItem(at: staging, to: destination)
        }
        guard let installed = AgentKit(root: destination, source: kit.source) else {
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
            "name": kit.name, "version": kit.version,
            "description": "BashCut editing skills (loaded by BashCut for its Claude tabs).",
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestFolder.appendingPathComponent("plugin.json"), options: .atomic)
        try Self.link(folder.appendingPathComponent("skills"), to: kit.skillsFolder)
        return folder
    }

    /// Links each kit skill into `folder` (an `.agents/skills` folder Codex reads) under its `linkName`. Links to
    /// another copy of the kit are replaced, and links left by older kits are removed (`removeStaleLinks`); files and
    /// folders that are not links are never touched. Returns the linked names.
    @discardableResult
    public static func linkSkills(of kit: AgentKit, into folder: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        removeStaleLinks(of: kit, in: folder)
        var linked: [String] = []
        for skill in kit.skills {
            let name = kit.linkName(skill)
            let target = folder.appendingPathComponent(name)
            if isLink(target) || !FileManager.default.fileExists(atPath: target.path) {
                try link(target, to: kit.skillsFolder.appendingPathComponent(skill, isDirectory: true))
                linked.append(name)
            }
        }
        return linked
    }

    /// Makes `folder` (one BashCut owns) hold exactly the kit's skills and `plugins`' skills as links, or none when
    /// `kit` is nil and there are no plugin skills. Files and folders that are not links are left alone.
    public static func syncSkills(of kit: AgentKit?, into folder: URL, plugins: [PluginSkill] = []) throws {
        let present = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let current = Set((kit.map { kit in kit.skills.map(kit.linkName) } ?? []) + plugins.map(\.linkName))
        unlinkSkills(named: present.filter { !current.contains($0) }, in: folder)
        if let kit { try linkSkills(of: kit, into: folder) }
        guard !plugins.isEmpty else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for skill in plugins {
            let target = folder.appendingPathComponent(skill.linkName)
            if isLink(target) || !FileManager.default.fileExists(atPath: target.path) { try link(target, to: skill.folder) }
        }
    }

    /// Removes links in a shared folder that a kit put there but that no longer match `kit`: `bashcut-<skill>` links
    /// from kits before 0.1.0 and `<kit name>-<skill>` links to a skill the kit no longer has. Only links into a kit's
    /// `skills` folder (one with `.claude-plugin/plugin.json` next to it) or links that no longer resolve are removed.
    @discardableResult
    public static func removeStaleLinks(of kit: AgentKit, in folder: URL) -> [String] {
        let manager = FileManager.default
        let current = Set(kit.skills.map(kit.linkName))
        let prefixes = Set(["bashcut-", "\(kit.name)-"])
        let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        let stale = names.filter { name in
            guard !current.contains(name), prefixes.contains(where: name.hasPrefix) else { return false }
            let target = folder.appendingPathComponent(name)
            guard let destination = try? manager.destinationOfSymbolicLink(atPath: target.path) else { return false }
            let skill = URL(fileURLWithPath: destination, relativeTo: folder).standardizedFileURL
            let manifest = skill.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".claude-plugin/plugin.json")
            return !manager.fileExists(atPath: skill.path) || manager.fileExists(atPath: manifest.path)
        }
        return unlinkSkills(named: stale, in: folder)
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

    /// The link names in `folder` that point to `kit`'s skills.
    public static func linkedSkills(of kit: AgentKit, in folder: URL) -> [String] {
        kit.skills.compactMap { skill in
            let name = kit.linkName(skill)
            let target = folder.appendingPathComponent(name)
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: target.path) else {
                return nil
            }
            let linked = URL(fileURLWithPath: destination).standardizedFileURL
                == kit.skillsFolder.appendingPathComponent(skill).standardizedFileURL
            return linked ? name : nil
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
