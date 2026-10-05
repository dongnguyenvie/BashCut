@testable import BashCutPlugin
import Foundation
import Testing

/// "Add Plugin…" from a folder, zip or plugin.json (#83).
struct PluginLocalSourceTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("local-plugins-\(UUID().uuidString)")

    private func folder(
        manifest: String? = nil, executable: Bool = true, link: Bool = false
    ) throws -> URL {
        let folder = root.appendingPathComponent("src/\(UUID().uuidString)/my-plugin")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        if let manifest {
            try Data(manifest.utf8).write(to: folder.appendingPathComponent("plugin.json"))
        } else {
            let value = PluginManifest(
                id: "nolan.private-demo", name: "Private demo", version: "0.1.0", entrypoint: "bin/provider",
                capabilities: ["audio.beats"])
            try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("plugin.json"))
        }
        let entrypoint = folder.appendingPathComponent("bin/provider")
        try Data("#!/bin/sh\n".utf8).write(to: entrypoint)
        try FileManager.default.setAttributes(
            [.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: entrypoint.path)
        if link {
            try FileManager.default.createSymbolicLink(
                at: folder.appendingPathComponent("secrets"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        }
        return folder
    }

    private func zip(_ folder: URL, as name: String = "plugin.zip") throws -> URL {
        let zip = root.appendingPathComponent("\(UUID().uuidString)-\(name)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", folder.path, zip.path]
        try process.run()
        process.waitUntilExit()
        return zip
    }

    @Test("A folder, its plugin.json and a zip are valid; nothing is installed")
    func validSources() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try folder()
        let fromFolder = PluginLocalSource.validate(source)
        #expect(fromFolder.isValid && fromFolder.kind == .folder && fromFolder.sha256 == nil)
        #expect(fromFolder.manifest?.id == "nolan.private-demo")
        let fromManifest = PluginLocalSource.validate(source.appendingPathComponent("plugin.json"))
        #expect(fromManifest.isValid && fromManifest.kind == .manifest)
        let archive = try zip(source, as: "demo.bashcutplugin")
        let fromArchive = PluginLocalSource.validate(archive)
        #expect(fromArchive.isValid && fromArchive.kind == .archive)
        #expect(fromArchive.sha256 == (try PluginArchiveInstaller.sha256(of: archive)))
    }

    @Test("Problems name the field or file and the fix")
    func problems() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let missingKey = PluginLocalSource.validate(try folder(manifest: #"{"schema": "bashcut.plugin/1", "apiVersion": 2}"#))
        #expect(!missingKey.isValid)
        #expect(missingKey.problems.first?.contains("is required") == true)
        let wrongType = PluginLocalSource.validate(try folder(manifest: """
            {"schema": "bashcut.plugin/1", "apiVersion": "two", "id": "a.b", "name": "A", "version": "1.0.0",
             "entrypoint": "bin/provider"}
            """))
        #expect(wrongType.problems.first == "plugin.json: \"apiVersion\" must be an integer")
        let notJSON = PluginLocalSource.validate(try folder(manifest: "{ nope"))
        #expect(notJSON.problems.first?.hasPrefix("plugin.json: not valid JSON") == true)
        let notExecutable = PluginLocalSource.validate(try folder(executable: false))
        #expect(notExecutable.problems == ["entrypoint bin/provider is not executable (chmod +x bin/provider)"])
        let badID = PluginLocalSource.validate(try folder(manifest: """
            {"schema": "bashcut.plugin/1", "apiVersion": 2, "id": "Bad", "name": "A", "version": "1.0.0",
             "entrypoint": "bin/provider", "capabilities": ["audio.beats"], "category": "games"}
            """))
        #expect(badID.problems == ["plugin.json: Plugin id must be reverse-domain style"])
        #expect(badID.warnings.first?.hasPrefix("Unknown category \"games\"") == true)
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(PluginLocalSource.validate(empty).problems.first?.hasPrefix("No plugin.json") == true)
        let text = root.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: text)
        #expect(PluginLocalSource.validate(text).kind == nil)
        #expect(!PluginLocalSource.validate(root.appendingPathComponent("missing")).isValid)
        #expect(!PluginLocalSource.validate(try folder(link: true)).isValid)
    }

    @Test("Staging copies the plugin under its id, so later edits to the source do not change what is installed")
    func stage() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try folder()
        let parent = root.appendingPathComponent("Plugins")
        let staged = try PluginLocalSource.stage(source, stagingParent: parent)
        #expect(staged.kind == .folder && staged.plugin.id == "nolan.private-demo")
        #expect(staged.plugin.directory.lastPathComponent == "nolan.private-demo")
        #expect(staged.plugin.directory.path.hasPrefix(parent.path))
        #expect(!FileManager.default.fileExists(atPath: staged.stagingRoot.appendingPathComponent("source").path))
        try Data("changed".utf8).write(to: source.appendingPathComponent("bin/provider"))
        let copied = try String(contentsOf: staged.plugin.directory.appendingPathComponent("bin/provider"), encoding: .utf8)
        #expect(copied == "#!/bin/sh\n")
        _ = try staged.plugin.entrypointURL()
        staged.discard()
        #expect(!FileManager.default.fileExists(atPath: staged.stagingRoot.path))

        let fromZip = try PluginLocalSource.stage(try zip(try folder()), stagingParent: parent)
        #expect(fromZip.kind == .archive && fromZip.sha256 != nil)
        fromZip.discard()

        #expect(throws: PluginError.self) { try PluginLocalSource.stage(try folder(executable: false), stagingParent: parent) }
        // A refused source leaves no staging folder behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        #expect(leftovers.isEmpty)
    }

    @Test("Link (developer mode) points at the developer's folder only while it holds the reviewed files")
    func linkMode() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try folder()
        let parent = root.appendingPathComponent("Plugins")
        let staged = try PluginLocalSource.stage(source.appendingPathComponent("plugin.json"), stagingParent: parent)
        #expect(staged.sourceFolder?.standardizedFileURL == source.standardizedFileURL)
        try staged.checkSourceUnchanged()
        let link = parent.appendingPathComponent(staged.plugin.id)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        #expect(PluginLocalSource.linkTarget(of: link)?.path == source.resolvingSymlinksInPath().path)
        #expect(PluginLocalSource.linkTarget(of: staged.plugin.directory) == nil)
        try Data("#!/bin/sh\necho changed\n".utf8).write(to: source.appendingPathComponent("bin/provider"))
        #expect(throws: PluginError.self) { try staged.checkSourceUnchanged() }
        // Removing the link keeps the developer's folder.
        try FileManager.default.removeItem(at: link)
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("plugin.json").path))
        staged.discard()

        let fromZip = try PluginLocalSource.stage(try zip(try folder()), stagingParent: parent)
        #expect(fromZip.sourceFolder == nil)
        fromZip.discard()
    }
}
