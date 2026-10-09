import BashCutPlugin
import BashCutProject
import Foundation
import Testing

/// Plugin API 7 (#376): agent skills in `contributes.skills`.
@Suite("Plugin skills")
struct PluginSkillsTests {
    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("plugin-skills-\(UUID().uuidString)", isDirectory: true)
    }

    private func manifest(_ json: String) throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
    }

    private func base(_ extra: String, apiVersion: Int = 7) -> String {
        """
        {"schema": "bashcut.plugin/1", "id": "example.captions", "name": "Example Captions", "version": "1.0.0",
         "apiVersion": \(apiVersion), "entrypoint": "bin/provider", "capabilities": []\(extra)}
        """
    }

    private static func skillText(name: String, description: String = "Use when captions are needed.") -> String {
        "---\nname: \(name)\ndescription: \(description)\n---\n\n# Captions\n\nRun `bashcut captions generate`.\n"
    }

    /// A plugin folder with skill folders `skills/<name>` (each with `texts[name]` as SKILL.md) listed in its manifest.
    private static func plugin(
        in root: URL, id: String = "example.captions", texts: [String: String], paths: [String]? = nil
    ) throws -> InstalledPlugin {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        for (name, text) in texts {
            let skill = directory.appendingPathComponent("skills/\(name)", isDirectory: true)
            try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: skill.appendingPathComponent("SKILL.md"))
        }
        let manifest = PluginManifest(
            id: id, name: LocalizedText(["en": "Example Captions"]), version: "1.0.0", apiVersion: 7,
            entrypoint: "bin/provider", capabilities: [],
            contributes: PluginContributions(
                skills: (paths ?? texts.keys.sorted().map { "skills/\($0)" }).map(PluginSkillContribution.init(path:))))
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
        return InstalledPlugin(manifest: manifest, directory: directory)
    }

    @Test("A skills plugin validates and needs API 7")
    func validManifest() throws {
        let plugin = try manifest(base(#", "contributes": {"skills": [{"path": "skills/captions"}]}"#))
        try plugin.validate()
        #expect(plugin.skills.map(\.path) == ["skills/captions"])
        #expect(PluginAPI.current >= 7)
        let old = try manifest(base(#", "contributes": {"skills": [{"path": "skills/captions"}]}"#, apiVersion: 6))
        #expect(throws: PluginError.self) { try old.validate() }
        // Older manifests without skills stay valid.
        try manifest(base(#", "contributes": {"library": [{"path": "pack"}]}"#, apiVersion: 6)).validate()
    }

    @Test("Skill paths must stay inside the plugin and be listed once", arguments: [
        #"[{"path": "../other/skill"}]"#, #"[{"path": "/Users/me/skill"}]"#, #"[{"path": "skills/../../x"}]"#,
        #"[{"path": "~/skill"}]"#, #"[{"path": ""}]"#, #"[{"path": "skills/a"}, {"path": "skills/a/"}]"#,
    ])
    func invalidPaths(skills: String) throws {
        let plugin = try manifest(base(#", "contributes": {"skills": \#(skills)}"#))
        #expect(throws: PluginError.self) { try plugin.validate() }
    }

    @Test("Too many skills are refused")
    func tooMany() throws {
        let list = (0...PluginSkillContribution.maximumSkills).map { #"{"path": "skills/s\#($0)"}"# }
        let plugin = try manifest(base(#", "contributes": {"skills": [\#(list.joined(separator: ","))]}"#))
        #expect(throws: PluginError.self) { try plugin.validate() }
    }

    @Test("Skills are read with their front matter and namespaced names")
    func readsSkills() throws {
        let root = Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let plugin = try Self.plugin(in: root, texts: [
            "transcribe": Self.skillText(name: "transcribe", description: "\"Use when speech needs captions.\""),
        ])
        let found = PluginSkills.skills(of: plugin)
        #expect(found.problems.isEmpty)
        let skill = try #require(found.skills.first)
        #expect(skill.name == "transcribe" && skill.id == "example.captions:transcribe")
        #expect(skill.description == "Use when speech needs captions.")
        #expect(skill.linkName == "captions-transcribe")
        #expect(PluginSkills.linkName(pluginID: "bashcut.vlog", skill: "product-ad") == "vlog-product-ad")
        #expect(PluginSkills.linkName(pluginID: "bashcut.whisper-captions", skill: "whisper-captions") == "whisper-captions")
        #expect(skill.file.lastPathComponent == "SKILL.md" && FileManager.default.fileExists(atPath: skill.file.path))
        #expect(skill.pluginName == "Example Captions")
    }

    @Test("Bad skills are reported and left out, the good ones stay")
    func badSkills() throws {
        let root = Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let long = String(repeating: "a", count: PluginSkillContribution.maximumDescriptionLength + 1)
        let plugin = try Self.plugin(in: root, texts: [
            "good": Self.skillText(name: "good"),
            "wrong-name": Self.skillText(name: "other"),
            "no-description": "---\nname: no-description\n---\nBody\n",
            "no-front": "# Just text\n",
            "Upper": Self.skillText(name: "Upper"),
            "long": Self.skillText(name: "long", description: long),
            "huge": Self.skillText(name: "huge") + String(repeating: "x", count: PluginSkillContribution.maximumTextBytes),
        ], paths: ["skills/good", "skills/wrong-name", "skills/no-description", "skills/no-front", "skills/Upper",
                   "skills/long", "skills/huge", "skills/missing"])
        let found = PluginSkills.skills(of: plugin)
        #expect(found.skills.map(\.name) == ["good"])
        #expect(found.problems.count == 7)
        #expect(found.problems.contains { $0.contains("skills/wrong-name") && $0.contains("must match the folder") })
        #expect(found.problems.contains { $0.contains("skills/missing") })
        // plugins validate reports them.
        let report = PluginLocalSource.validate(plugin.directory)
        #expect(report.problems.contains { $0.hasPrefix("contributes.skills:") && $0.contains("no-front") })
    }

    @Test("A skill folder or file that links out of the plugin is refused")
    func symlinksOut() throws {
        let root = Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside/escape", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(Self.skillText(name: "escape").utf8).write(to: outside.appendingPathComponent("SKILL.md"))
        let plugin = try Self.plugin(
            in: root, texts: ["inner": Self.skillText(name: "inner")], paths: ["skills/escape", "skills/inner"])
        let skills = plugin.directory.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: skills.appendingPathComponent("escape"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            at: skills.appendingPathComponent("inner/notes.md"), withDestinationURL: outside.appendingPathComponent("SKILL.md"))
        let found = PluginSkills.skills(of: plugin)
        #expect(found.skills.isEmpty)
        #expect(found.problems.contains { $0.contains("outside the plugin") })
        #expect(found.problems.contains { $0.contains("links outside the plugin") })
    }

    @Test("The catalog lists each plugin's skills once, in order")
    func catalog() throws {
        let root = Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try Self.plugin(in: root, id: "example.one", texts: ["shared": Self.skillText(name: "shared")])
        let second = try Self.plugin(in: root, id: "example.two", texts: ["shared": Self.skillText(name: "shared")])
        let found = PluginSkills.catalog([first, second, first])
        #expect(found.skills.map(\.id) == ["example.one:shared", "example.two:shared"])
    }
}
