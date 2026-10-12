import BashCutProject
import Foundation

/// A skill pack plugin made from saved skills (#506, `skills export --as-plugin`): a folder with `plugin.json`
/// (`apiVersion` 7, no entrypoint, `contributes.skills`) and each skill folder under `skills/<name>`, which installs
/// in another BashCut like any local plugin and gives agents those skills while it is trusted.
public enum PluginSkillPack {
    public struct Metadata: Sendable {
        public let id: String
        public let name: String
        public let version: String
        public let author: PluginAuthor?

        public init(id: String, name: String, version: String = "0.1.0", author: PluginAuthor? = nil) {
            self.id = id
            self.name = name
            self.version = version
            self.author = author
        }
    }

    /// Copies `skills` (skill folders, each with a SKILL.md) into `output` (new or empty) and, with `metadata`, writes
    /// the plugin manifest; then reads the result back as a plugin so a pack that would not install is never left
    /// behind. Returns the plugin (nil without `metadata`: plain skill folders).
    @discardableResult
    public static func export(_ skills: [URL], metadata: Metadata?, to output: URL) throws -> InstalledPlugin? {
        let manager = FileManager.default
        guard !skills.isEmpty else { throw PluginError.invalid("No skills to export") }
        guard skills.count <= PluginSkillContribution.maximumSkills || metadata == nil else {
            throw PluginError.invalid("A plugin ships at most \(PluginSkillContribution.maximumSkills) skills")
        }
        let names = skills.map(\.lastPathComponent)
        guard Set(names).count == names.count else { throw PluginError.invalid("Two skills have the same name") }
        if manager.fileExists(atPath: output.path) {
            guard (try manager.contentsOfDirectory(atPath: output.path)).filter({ $0 != ".DS_Store" }).isEmpty else {
                throw PluginError.invalid("\(output.path) is not empty; choose a new or empty folder")
            }
        }
        let folder = metadata == nil ? output : output.appendingPathComponent("skills", isDirectory: true)
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for skill in skills {
                guard manager.fileExists(atPath: skill.appendingPathComponent("SKILL.md").path) else {
                    throw PluginError.invalid("\(skill.lastPathComponent) has no SKILL.md")
                }
                try manager.copyItem(at: skill, to: folder.appendingPathComponent(skill.lastPathComponent, isDirectory: true))
            }
            guard let metadata else { return nil }
            return try writeManifest(metadata, skills: names, in: output)
        } catch {
            try? manager.removeItem(at: output)
            throw error
        }
    }
}

extension PluginSkillPack {
    /// Writes `plugin.json` for the skill folders under `skills/` and reads the folder back as a plugin.
    static func writeManifest(_ metadata: Metadata, skills names: [String], in output: URL) throws -> InstalledPlugin {
        var fields: [String: JSONValue] = [
            "schema": .string(PluginManifest.schema), "id": .string(metadata.id), "name": .string(metadata.name),
            "version": .string(metadata.version), "apiVersion": .integer(7), "category": .string("agents"),
            "contributes": .object(["skills": .array(names.sorted().map { .object(["path": .string("skills/" + $0)]) })]),
        ]
        if let author = metadata.author { fields["author"] = author.json }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(JSONValue.object(fields))
        try data.write(to: output.appendingPathComponent("plugin.json"))
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        let plugin = InstalledPlugin(manifest: manifest, directory: output)
        try plugin.checkEntrypoint()
        if let problem = PluginSkills.skills(of: plugin).problems.first { throw PluginError.invalid(problem) }
        return plugin
    }
}

/// What an install or update changes in a plugin's skills, for the trust sheet (#506): each skill's added and removed
/// lines, and the added lines an agent should not follow blindly flagged (commands, links, instructions to ignore
/// earlier ones). Agents read plugin skills as instructions, so the user sees these before trusting.
public struct PluginSkillReview: Sendable, Equatable {
    public enum Flag: String, Sendable, CaseIterable { case command, url, override }

    public struct Line: Sendable, Equatable {
        public let text: String
        public let added: Bool
        public let flags: [Flag]
    }

    public struct Skill: Sendable, Equatable {
        public let name: String
        /// `added`, `changed` or `removed`.
        public let change: String
        public let lines: [Line]
        public var flagged: [Line] { lines.filter { $0.added && !$0.flags.isEmpty } }
    }

    public let skills: [Skill]

    public var flaggedCount: Int { skills.reduce(0) { $0 + $1.flagged.count } }
    public var isEmpty: Bool { skills.isEmpty }

    /// Most diff lines kept per skill (the sheet shows the flagged ones first).
    public static let maximumLines = 400

    /// Compares skill texts by name (`old` is the installed plugin's, empty for a new install).
    public init(old: [String: String], new: [String: String]) {
        var skills: [Skill] = []
        for name in Set(old.keys).union(new.keys).sorted() {
            let before = old[name], after = new[name]
            guard before != after else { continue }
            let lines = Self.diff(before ?? "", after ?? "")
            let change = before == nil ? "added" : after == nil ? "removed" : "changed"
            skills.append(Skill(name: name, change: change, lines: Array(lines.prefix(Self.maximumLines))))
        }
        self.skills = skills
    }

    /// The SKILL.md texts of a plugin's skills by name.
    public static func texts(of plugin: InstalledPlugin) -> [String: String] {
        var texts: [String: String] = [:]
        for skill in PluginSkills.skills(of: plugin).skills {
            texts[skill.name] = (try? String(contentsOf: skill.file, encoding: .utf8)) ?? ""
        }
        return texts
    }

    /// Why a line deserves a look: it runs something, points somewhere, or tells the agent to drop its instructions.
    public static func flags(_ line: String) -> [Flag] {
        let text = line.lowercased()
        var flags: [Flag] = []
        let commands = ["curl ", "wget ", "rm -", "sudo ", "chmod ", "bash -c", "sh -c", "eval ", "osascript", "| sh",
                        "| bash", "python -c", "python3 -c", "security find", "launchctl", "ssh ", "scp ", "nc "]
        if commands.contains(where: text.contains) || text.trimmingCharacters(in: .whitespaces).hasPrefix("$ ") {
            flags.append(.command)
        }
        if text.contains("http://") || text.contains("https://") || text.contains("ftp://") { flags.append(.url) }
        let overrides = ["ignore previous", "ignore all previous", "ignore the previous", "ignore earlier", "disregard",
                         "forget your instructions", "forget previous", "system prompt", "you are now", "do not tell the user",
                         "don't tell the user", "without asking", "bypass", "override"]
        if overrides.contains(where: text.contains) { flags.append(.override) }
        return flags
    }

    /// Lines removed and added between two texts (longest common subsequence; texts are at most 64 KB).
    static func diff(_ before: String, _ after: String) -> [Line] {
        let old = before.isEmpty ? [] : before.components(separatedBy: "\n")
        let new = after.isEmpty ? [] : after.components(separatedBy: "\n")
        // Trim the shared start and end first, so a small edit to a long skill compares only the changed middle.
        var head = 0
        while head < old.count, head < new.count, old[head] == new[head] { head += 1 }
        var tail = 0
        while tail < old.count - head, tail < new.count - head, old[old.count - 1 - tail] == new[new.count - 1 - tail] {
            tail += 1
        }
        let left = Array(old[head..<(old.count - tail)]), right = Array(new[head..<(new.count - tail)])
        guard left.count * right.count <= 4_000_000 else {
            return left.map { Line(text: $0, added: false, flags: []) } + right.map { Line(text: $0, added: true, flags: flags($0)) }
        }
        var table = Array(repeating: Array(repeating: 0, count: right.count + 1), count: left.count + 1)
        for row in stride(from: left.count - 1, through: 0, by: -1) {
            for column in stride(from: right.count - 1, through: 0, by: -1) {
                table[row][column] = left[row] == right[column]
                    ? table[row + 1][column + 1] + 1 : max(table[row + 1][column], table[row][column + 1])
            }
        }
        var lines: [Line] = []
        var row = 0, column = 0
        while row < left.count || column < right.count {
            if row < left.count, column < right.count, left[row] == right[column] {
                row += 1
                column += 1
            } else if column < right.count, row == left.count || table[row][column + 1] >= table[row + 1][column] {
                lines.append(Line(text: right[column], added: true, flags: flags(right[column])))
                column += 1
            } else {
                lines.append(Line(text: left[row], added: false, flags: []))
                row += 1
            }
        }
        return lines
    }

    public var json: JSONValue {
        .object([
            "flagged": .integer(flaggedCount),
            "skills": .array(skills.map { skill in
                .object([
                    "name": .string(skill.name), "change": .string(skill.change),
                    "added": .integer(skill.lines.filter(\.added).count),
                    "removed": .integer(skill.lines.filter { !$0.added }.count),
                    "flagged": .array(skill.flagged.map { line in
                        .object(["text": .string(String(line.text.prefix(300))),
                                 "flags": .array(line.flags.map { .string($0.rawValue) })])
                    }),
                ])
            }),
        ])
    }
}
