import Foundation

/// One agent skill inside the plugin folder (API 7): a folder with a `SKILL.md` in the agent kit's format, whose front
/// matter `name` is the folder's name. Agents get it while the plugin is trusted and enabled; it is read-only and
/// goes away with the plugin.
public struct PluginSkillContribution: Codable, Sendable, Equatable {
    /// The skill folder, relative to the plugin folder.
    public let path: String

    public init(path: String) { self.path = path }

    public static let maximumSkills = 16
    /// Largest `SKILL.md`, and largest skill folder (every file in it).
    public static let maximumTextBytes = 64 * 1024
    public static let maximumFolderBytes = 2 * 1024 * 1024
    public static let maximumNameLength = 64
    public static let maximumDescriptionLength = 1024

    func validate() throws {
        let components = NSString(string: path).pathComponents
        guard !path.isEmpty, path.count <= 512, !path.hasPrefix("/"), !path.hasPrefix("~"), !components.contains(".."),
            !path.contains("\0")
        else { throw PluginError.invalid("Skill path \(path) must stay inside the plugin bundle") }
    }
}

/// A skill a ready plugin ships, as agents and `skills list` see it.
public struct PluginSkill: Sendable, Equatable, Identifiable {
    public let pluginID: String
    public let pluginName: String
    /// The front matter `name`, which is also the folder's name.
    public let name: String
    public let description: String
    /// The skill folder inside the plugin.
    public let folder: URL

    public init(pluginID: String, pluginName: String, name: String, description: String, folder: URL) {
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.name = name
        self.description = description
        self.folder = folder
    }

    /// `<plugin-id>:<name>`: unique across plugins, and never clashes with the kit's `bc:` skills.
    public var id: String { "\(pluginID):\(name)" }
    public var file: URL { folder.appendingPathComponent("SKILL.md") }
    /// The folder name used where the skill is linked for agents (`.claude/skills`, `.agents/skills`).
    public var linkName: String { PluginSkills.linkName(pluginID: pluginID, skill: name) }
}

/// Reads and checks the skills plugins ship in `contributes.skills` (API 7). Each skill folder must resolve inside
/// the plugin folder, hold a `SKILL.md` whose front matter names it and describes it, and stay within the size limits.
public enum PluginSkills {
    /// Every skill one plugin contributes, and why any could not be read (those are left out).
    public static func skills(of plugin: InstalledPlugin) -> (skills: [PluginSkill], problems: [String]) {
        var skills: [PluginSkill] = []
        var problems: [String] = []
        for contribution in plugin.manifest.skills {
            do {
                let skill = try read(contribution, of: plugin)
                guard !skills.contains(where: { $0.name == skill.name }) else {
                    throw PluginError.invalid("another skill is already named \(skill.name)")
                }
                skills.append(skill)
            } catch {
                problems.append("\(plugin.id): skill \(contribution.path): \(error.localizedDescription)")
            }
        }
        return (skills, problems)
    }

    /// The skills of `plugins` (in catalog order), with what could not be read.
    public static func catalog(_ plugins: [InstalledPlugin]) -> (skills: [PluginSkill], problems: [String]) {
        var skills: [PluginSkill] = []
        var problems: [String] = []
        var seen = Set<String>()
        for plugin in plugins where !plugin.manifest.skills.isEmpty && seen.insert(plugin.id).inserted {
            let found = Self.skills(of: plugin)
            skills += found.skills
            problems += found.problems
        }
        return (skills, problems)
    }

    /// One skill, checked.
    public static func read(_ contribution: PluginSkillContribution, of plugin: InstalledPlugin) throws -> PluginSkill {
        try contribution.validate()
        let manager = FileManager.default
        let base = plugin.directory.resolvingSymlinksInPath().standardizedFileURL.path
        let folder = plugin.directory.appendingPathComponent(contribution.path, isDirectory: true)
        let resolved = folder.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(base + "/") else { throw PluginError.invalid("the skill folder is outside the plugin") }
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PluginError.invalid("the skill folder does not exist")
        }
        let file = resolved.appendingPathComponent("SKILL.md")
        let fileResolved = file.resolvingSymlinksInPath().standardizedFileURL.path
        guard fileResolved.hasPrefix(base + "/"), manager.fileExists(atPath: fileResolved) else {
            throw PluginError.invalid("the folder has no SKILL.md")
        }
        try checkSize(of: resolved, base: base)
        let data = try Data(contentsOf: file)
        guard data.count <= PluginSkillContribution.maximumTextBytes else {
            throw PluginError.invalid("SKILL.md is larger than \(PluginSkillContribution.maximumTextBytes / 1024) KB")
        }
        guard let text = String(data: data, encoding: .utf8) else { throw PluginError.invalid("SKILL.md is not UTF-8") }
        let front = frontMatter(text)
        let folderName = resolved.lastPathComponent
        guard let name = front["name"], !name.isEmpty else {
            throw PluginError.invalid("SKILL.md front matter needs a name")
        }
        guard name.count <= PluginSkillContribution.maximumNameLength,
            name.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
        else {
            throw PluginError.invalid(
                "the name \(name) must be lowercase words joined by - (at most \(PluginSkillContribution.maximumNameLength))")
        }
        guard name == folderName else { throw PluginError.invalid("the name \(name) must match the folder \(folderName)") }
        guard let description = front["description"], !description.isEmpty else {
            throw PluginError.invalid("SKILL.md front matter needs a description")
        }
        guard description.count <= PluginSkillContribution.maximumDescriptionLength else {
            throw PluginError.invalid(
                "the description is longer than \(PluginSkillContribution.maximumDescriptionLength) characters")
        }
        return PluginSkill(
            pluginID: plugin.id, pluginName: plugin.manifest.displayName, name: name, description: description,
            folder: folder.standardizedFileURL)
    }

    /// `<plugin>-<skill>` (`vlog-product-ad` for `bashcut.vlog`): the folder name and the front matter name agents
    /// see, so `/vlog-product-ad` names its plugin. `<plugin>` is the last part of the plugin ID; a valid Claude Code
    /// skill name (lowercase letters, digits and `-`, at most 64 characters).
    public static func linkName(pluginID: String, skill: String) -> String {
        let last = pluginID.split(separator: ".").last.map(String.init) ?? pluginID
        let plugin = String(last.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
        return String("\(plugin)-\(skill)".prefix(64))
    }

    /// The front matter fields of a SKILL.md (`---` lines of `key: value` at the top), quotes removed.
    static func frontMatter(_ text: String) -> [String: String] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
            let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return [:] }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            if fields[key] == nil { fields[key] = value }
        }
        return fields
    }

    /// Refuses a skill folder over the size limit, or one holding a link that leaves the plugin.
    private static func checkSize(of folder: URL, base: String) throws {
        let manager = FileManager.default
        guard let walker = manager.enumerator(
            at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        else { return }
        var total = 0
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            if values.isSymbolicLink == true {
                let target = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard target.hasPrefix(base + "/") else {
                    throw PluginError.invalid("\(url.lastPathComponent) links outside the plugin")
                }
            }
            if values.isRegularFile == true { total += values.fileSize ?? 0 }
            guard total <= PluginSkillContribution.maximumFolderBytes else {
                throw PluginError.invalid(
                    "the skill folder is larger than \(PluginSkillContribution.maximumFolderBytes / 1024 / 1024) MB")
            }
        }
    }
}
