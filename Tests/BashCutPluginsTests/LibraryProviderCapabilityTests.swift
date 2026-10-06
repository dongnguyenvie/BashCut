import BashCutPlugin
import BashCutProject
import Foundation
import Testing

@testable import BashCutPlugins

/// `library.search` and `library.generate` (#81) against fake shell plugins in a temporary folder: no network.
@Suite("Library provider capabilities")
struct LibraryProviderCapabilityTests {
    private struct Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("library-provider-\(UUID().uuidString)")
        var project: URL { root.appendingPathComponent("project", isDirectory: true) }
        var candidates: URL { root.appendingPathComponent("candidates", isDirectory: true) }
        var service: CapabilityService {
            CapabilityService(
                roots: PluginRoots(user: root.appendingPathComponent("user"), bundled: nil),
                transport: PluginProcessRunner(timeout: 10), healthTransport: PluginProcessRunner(timeout: 5))
        }

        init() throws { try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true) }

        func cleanup() { try? FileManager.default.removeItem(at: root) }

        /// `body` runs after `$id`, `$out`, `$query` and `$prompt` are read from the request.
        func addPlugin(_ id: String, providers: [PluginProvider], body: String) throws {
            let directory = project.appendingPathComponent(".bashcut/plugins/\(id)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let script = """
                #!/bin/sh
                input=$(cat)
                id=$(printf '%s' "$input" | sed -E 's/.*"id":"([^"]+)".*/\\1/')
                out=$(printf '%s' "$input" | sed -E 's/.*"outputDirectory":"([^"]+)".*/\\1/' | sed 's#\\\\/#/#g')
                query=$(printf '%s' "$input" | sed -nE 's/.*"query":"([^"]+)".*/\\1/p')
                prompt=$(printf '%s' "$input" | sed -nE 's/.*"prompt":"([^"]+)".*/\\1/p')
                \(body)
                """
            let entrypoint = directory.appendingPathComponent("provider.sh")
            try Data(script.utf8).write(to: entrypoint)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entrypoint.path)
            let manifest = PluginManifest(
                id: id, name: LocalizedText(["en": id]), version: "1.0.0", apiVersion: 6, entrypoint: "provider.sh",
                capabilities: Array(Set(providers.map(\.capability))).sorted(), providers: providers)
            try manifest.validate()
            try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("plugin.json"))
        }
    }

    private static let sounds = """
        printf 'RIFF' > "$out/rain.wav"
        printf 'PNG' > "$out/rain.png"
        printf '{"id":"%s","result":{"items":[{"id":"rain-loop","name":"%s","file":"rain.wav","preview":"rain.png",\
        "license":"CC0","source":"https://example.com/rain","tags":["rain"],"params":{"role":"ambience","loopable":true}},\
        {"name":"No id","kind":"audio","file":"rain.wav"}]}}\n' "$id" "$query"
        """

    @Test("library.search returns confined, checked candidates that save as library items")
    func search() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.sounds", providers: [
                PluginProvider(id: "test.sounds.search", capability: PluginAPI.librarySearch, name: "S", kinds: ["audio"]),
            ], body: Self.sounds)
        let found = try await sandbox.service.searchLibrary(
            kind: .audio, query: "rain", limit: 5, provider: nil, projectRoot: sandbox.project, outputRoot: sandbox.candidates)
        #expect(found.candidates.count == 2)
        #expect(found.provenance == PluginProvenance(pluginID: "test.sounds", pluginVersion: "1.0.0", providerID: "test.sounds.search"))
        let first = try #require(found.candidates.first)
        #expect(first.item.id == "rain-loop" && first.item.name == "rain" && first.item.kind == .audio)
        #expect(first.item.file == "rain.wav" && first.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(found.candidates[1].item.id == "candidate-2")
        #expect(found.directory.path.hasPrefix(sandbox.candidates.resolvingSymlinksInPath().path))

        // The job result lists them with an index and absolute paths; a saved one is read back from it.
        let result = found.json
        #expect(result.object["provider"]?.object["capability"] == .string("library.search"))
        #expect(result.object["candidates"]?.array.first?.object["index"] == .integer(0))
        let chosen = try LibraryCandidate(jobResult: result, index: 0)
        #expect(chosen.item == first.item && chosen.fileURL?.path == first.fileURL?.path)
        #expect(chosen.changes["license"] == .string("CC0") && chosen.changes["file"] == nil && chosen.changes["id"] == nil)
        #expect(throws: PluginError.self) { try LibraryCandidate(jobResult: result, index: 2) }

        // Saving copies the file into the library, with its source and license.
        let catalog = LibraryCatalog(builtIn: [], user: nil, project: .project(root: sandbox.project))
        var item = LibraryItem(id: "rain", kind: .audio, name: chosen.item.name)
        for (key, value) in chosen.changes { item[key] = value }
        let saved = try catalog.add(item, into: .project, file: chosen.fileURL, preview: chosen.previewURL)
        #expect(saved["source"] == .string("https://example.com/rain") && saved.tags == ["rain"])
        let copied = try #require(catalog.fileURL(of: saved))
        #expect(copied.path.hasPrefix(sandbox.project.path) && FileManager.default.fileExists(atPath: copied.path))
        // The candidate folder can go; the library keeps its copy.
        try FileManager.default.removeItem(at: found.directory)
        #expect(FileManager.default.fileExists(atPath: copied.path))
        #expect(throws: PluginError.self) { try LibraryCandidate(jobResult: result, index: 0) }
    }

    @Test("library.generate sends the prompt, limit and hints and reads stickers back")
    func generate() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.maker", providers: [
                PluginProvider(id: "test.maker.stickers", capability: PluginAPI.libraryGenerate, name: "M", kinds: ["sticker"]),
            ],
            body: #"""
                printf '%s' "$input" > "$out/request.json"
                printf '{"id":"%s","result":{"items":[{"name":"%s","params":{"emoji":"🐱"}}]}}\n' "$id" "$prompt"
                """#)
        let made = try await sandbox.service.generateLibrary(
            kind: .sticker, prompt: "cat", limit: 2, hints: ["style": .string("flat")], provider: "test.maker",
            projectRoot: sandbox.project, outputRoot: sandbox.candidates)
        #expect(made.candidates.map(\.item.name) == ["cat"])
        #expect(made.candidates.first?.item.kind == .sticker)
        let request = try JSONDecoder().decode(
            JSONValue.self, from: Data(contentsOf: made.directory.appendingPathComponent("request.json")))
        let params = request.object["params"]?.object
        #expect(request.object["method"] == .string("library.generate"))
        #expect(params?["limit"] == .integer(2) && params?["kind"] == .string("sticker"))
        #expect(params?["params"]?.object["style"] == .string("flat"))
    }

    @Test("Providers are chosen by the kinds they serve; a named provider must be available")
    func kinds() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.sounds", providers: [
                PluginProvider(id: "test.sounds.search", capability: PluginAPI.librarySearch, name: "S", kinds: ["audio"]),
            ], body: Self.sounds)
        let service = sandbox.service
        await #expect(throws: PluginError.self) {
            try await service.searchLibrary(
                kind: .sticker, query: "cat", provider: nil, projectRoot: sandbox.project, outputRoot: sandbox.candidates)
        }
        await #expect(throws: PluginError.self) {
            try await service.searchLibrary(
                kind: .audio, query: "rain", provider: "other.plugin", projectRoot: sandbox.project,
                outputRoot: sandbox.candidates)
        }
        let byPlugin = try await service.searchLibrary(
            kind: .audio, query: "rain", provider: "test.sounds", projectRoot: sandbox.project, outputRoot: sandbox.candidates)
        #expect(byPlugin.provenance.providerID == "test.sounds.search")
        let plugins = service.catalog(projectRoot: sandbox.project).plugins
        #expect(CapabilityService.libraryProviders(PluginAPI.librarySearch, kind: .audio, in: plugins).count == 1)
        #expect(CapabilityService.libraryProviders(PluginAPI.librarySearch, kind: .look, in: plugins).isEmpty)
        #expect(CapabilityService.libraryProviders(PluginAPI.libraryGenerate, kind: .audio, in: plugins).isEmpty)
    }

    @Test("Bad candidates are refused and their request folder removed", arguments: [
        // A file outside the request folder.
        #"printf 'x' > "$out/../leak.wav"; printf '{"id":"%s","result":{"items":[{"name":"Leak","file":"../leak.wav"}]}}\n' "$id""#,
        // Another kind than asked for.
        #"printf '{"id":"%s","result":{"items":[{"name":"Look","kind":"look","params":{"color":{}}}]}}\n' "$id""#,
        // An audio item needs its file.
        #"printf '{"id":"%s","result":{"items":[{"name":"Nothing"}]}}\n' "$id""#,
        // More than the limit (1).
        #"printf '{"id":"%s","result":{"items":[{"name":"A","file":"a.wav"},{"name":"B","file":"a.wav"}]}}\n' "$id""#,
        // No items array.
        #"printf '{"id":"%s","result":{"found":[]}}\n' "$id""#,
    ])
    func refused(body: String) async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.bad", providers: [PluginProvider(id: "test.bad.search", capability: PluginAPI.librarySearch, name: "B")],
            body: #"printf 'RIFF' > "$out/a.wav""# + "\n" + body)
        await #expect(throws: PluginError.self) {
            try await sandbox.service.searchLibrary(
                kind: .audio, query: "x", limit: 1, provider: nil, projectRoot: sandbox.project, outputRoot: sandbox.candidates)
        }
        let left = (try? FileManager.default.contentsOfDirectory(atPath: sandbox.candidates.path)) ?? []
        #expect(left.allSatisfy { !$0.contains("-") || $0 == "leak.wav" })
    }

    @Test("Requests are checked before any plugin runs, and old candidate folders are pruned")
    func requests() throws {
        let root = URL(fileURLWithPath: "/tmp")
        #expect(throws: PluginError.self) { try LibrarySearchCapability(kind: .audio, query: "  ", outputRoot: root).validate() }
        #expect(throws: PluginError.self) { try LibrarySearchCapability(kind: .audio, query: "a", limit: 0, outputRoot: root).validate() }
        #expect(throws: PluginError.self) { try LibraryGenerateCapability(kind: .audio, prompt: "a", limit: 51, outputRoot: root).validate() }
        try LibraryGenerateCapability(kind: .audio, prompt: "calm piano", outputRoot: root).validate()

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prune-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["old", "new"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3 * 86_400)], ofItemAtPath: folder.appendingPathComponent("old").path)
        LibraryCandidateParser.prune(folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["new"])
    }
}
