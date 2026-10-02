import BashCutEngine
import BashCutProject
import Foundation
import Testing

@testable import BashCutAutomation

struct CommandSpecTests {
    @Test("Command names, MCP tool names and CLI bindings are unique and well formed")
    func catalogConsistency() {
        let specs = CommandCatalog.specs
        #expect(Set(specs.map(\.name)).count == specs.count)
        #expect(Set(specs.map(\.mcpToolName)).count == specs.count)
        #expect(CommandCatalog.modes.count == specs.count)
        for spec in specs {
            #expect(spec.cliWords.count == 2, "\(spec.name)")
            #expect(Set(spec.parameters.map(\.name)).count == spec.parameters.count, "\(spec.name)")
            let flags = spec.parameters.compactMap { parameter -> String? in
                switch parameter.cli {
                case .option(let flag), .flag(let flag): flag
                default: nil
                }
            }
            #expect(Set(flags).count == flags.count, "\(spec.name)")
            #expect(!flags.contains("format") || spec.name == "timeline.get", "\(spec.name) reuses the global --format")
            // A required positional after an optional one could never be reached on the command line.
            let positionals = spec.parameters.filter(\.cli.isPositional)
            if let firstOptional = positionals.firstIndex(where: { !$0.required }) {
                #expect(positionals[firstOptional...].allSatisfy { !$0.required }, "\(spec.name)")
            }
            for parameter in spec.parameters where parameter.cli.isFlag {
                #expect(parameter.kind == .boolean, "\(spec.name).\(parameter.name)")
            }
        }
    }

    @Test("Every export preset choice resolves and every preset is offered")
    func exportPresets() {
        let resolved = CommandCatalog.exportPresets.compactMap(ExportPreset.init(argument:))
        #expect(resolved.count == CommandCatalog.exportPresets.count)
        #expect(Set(resolved) == Set(ExportPreset.allCases))
    }

    @Test("MCP schemas mark required fields and give timeline.apply a default label")
    func mcpSchemas() throws {
        let apply = try #require(CommandCatalog.spec(named: "timeline.apply"))
        #expect(apply.mcpToolName == "bashcut_timeline_apply")
        let schema = apply.inputSchema.object
        #expect(schema["required"] == .array([.string("ops"), .string("baseRev")]))
        #expect(schema["additionalProperties"] == .bool(false))
        #expect(schema["properties"]?.object["label"]?.object["default"] == .string("Agent edit"))
        let speak = try #require(CommandCatalog.spec(named: "voice.speak")).inputSchema.object["properties"]?.object
        #expect(speak?["takes"]?.object["minimum"] == .integer(1))
        #expect(speak?["takes"]?.object["maximum"] == .integer(8))
        let export = try #require(CommandCatalog.spec(named: "export.start")).inputSchema.object["properties"]?.object
        #expect(export?["preset"]?.object["enum"]?.array.count == CommandCatalog.exportPresets.count)
        let empty = try #require(CommandCatalog.spec(named: "context.get")).inputSchema.object
        #expect(empty["required"] == nil)
    }

    @Test("Validation applies defaults and rejects unknown, missing, empty and out-of-range values")
    func validation() throws {
        let speak = try #require(CommandCatalog.spec(named: "voice.speak"))
        let values = try speak.validate(["text": .string("Xin chào"), "provider": .null])
        #expect(values == ["text": .string("Xin chào"), "takes": .integer(3)])
        for params: [String: JSONValue] in [
            [:], ["text": .string("  ")], ["text": .string("a"), "takes": .integer(9)],
            ["text": .string("a"), "atFrame": .integer(-1)], ["text": .string("a"), "voice": .string("x")],
            ["text": .integer(1)],
        ] {
            #expect(throws: RPCFailure.self) { try speak.validate(params) }
        }
        let export = try #require(CommandCatalog.spec(named: "export.start"))
        #expect(throws: RPCFailure.self) {
            try export.validate(["preset": .string("vhs"), "name": .string("draft")])
        }
    }

    @Test("The CLI parses positionals, options, flags, files and the global format from specs")
    func commandLine() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bashcut-cli-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ops = directory.appendingPathComponent("ops.json")
        try Data(#"[{"op":"split","item":"c","atFrame":30}]"#.utf8).write(to: ops)

        let apply = try CommandLineParser.parse(["timeline", "apply", ops.path, "--base-rev", "4"])
        #expect(apply.spec.name == "timeline.apply")
        #expect(apply.params["baseRev"] == .integer(4))
        #expect(apply.params["label"] == .string("Agent edit"))
        #expect(apply.params["ops"]?.array.count == 1)
        #expect(apply.format == "json")

        let speak = try CommandLineParser.parse(["voice", "speak", "--takes=2", "--", "--hello"])
        #expect(speak.params == ["text": .string("--hello"), "takes": .integer(2)])

        let export = try CommandLineParser.parse([
            "export", "start", "--preset", "quick-draft", "--name", "draft", "--normalize-audio", "--output-dir", "out",
        ])
        #expect(export.params["normalizeAudio"] == .bool(true))
        #expect(export.params["includeSRT"] == .bool(false))
        #expect(export.params["directory"] == .string("out"))

        let move = try CommandLineParser.parse(["timeline", "move", "clip-1", "--track", "v2", "--at-frame", "90", "--base-rev", "3"])
        #expect(move.params == [
            "item": .string("clip-1"), "track": .string("v2"), "atFrame": .integer(90), "baseRev": .integer(3),
        ])
        let place = try CommandLineParser.parse(["media", "place", "--media", "m1", "--base-rev", "3"])
        #expect(place.spec.mode == .edit)
        #expect(place.params == ["media": .string("m1"), "baseRev": .integer(3)])
        #expect(throws: CommandLineParser.Failure.self) {
            try CommandLineParser.parse(["layers", "add", "--kind", "image", "--base-rev", "3"])
        }

        // Path parameters become absolute against the CLI's working directory.
        let cwd = FileManager.default.currentDirectoryPath
        let create = try CommandLineParser.parse(["project", "create", "--name", "Vlog", "--dir", "projects", "--fps", "30"])
        #expect(create.params["directory"] == .string(URL(fileURLWithPath: cwd).appendingPathComponent("projects").path))
        #expect(create.params["canvas"] == .string("portrait"))
        #expect(create.params["saveCurrent"] == .bool(false))
        let open = try CommandLineParser.parse(["project", "open", "~/clip-project", "--discard-current"])
        #expect(open.params["path"]?.string?.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) == true)
        #expect(open.params["discardCurrent"] == .bool(true))
        #expect(throws: CommandLineParser.Failure.self) {
            try CommandLineParser.parse(["project", "create", "--name", "x", "--dir", "/tmp", "--fps", "25"])
        }

        let text = try CommandLineParser.parse(["--format", "text", "timeline", "get"])
        #expect(text.format == "text")
        #expect(text.params["format"] == .string("text"))
        #expect(try CommandLineParser.parse(["review", "run", "--format=text"]).params.isEmpty)
        #expect(try CommandLineParser.parse(["ui", "select"]).params.isEmpty)
        #expect(try CommandLineParser.parse(["ui", "seek", "48"]).params["frame"] == .integer(48))

        for words in [
            ["timeline", "explode"], ["ui", "seek", "soon"], ["ui", "seek", "1", "2"], ["timeline", "undo"],
            ["captions", "generate", "--media"], ["captions", "generate", "--media", "m", "--replace=yes"],
            ["export", "otio", "--name", "a", "--colour", "red"], ["review", "run", "--format", "yaml"],
        ] {
            #expect(throws: CommandLineParser.Failure.self, "\(words)") { try CommandLineParser.parse(words) }
        }
    }

    @Test("The SubRip import reads the file named on the command line")
    func subRipFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("bashcut-\(UUID().uuidString).srt")
        defer { try? FileManager.default.removeItem(at: file) }
        let srt = "1\n00:00:00,000 --> 00:00:01,000\nXin chào\n"
        try Data(srt.utf8).write(to: file)
        let invocation = try CommandLineParser.parse(["captions", "import", file.path, "--base-rev", "2", "--replace"])
        #expect(invocation.params == ["text": .string(srt), "baseRev": .integer(2), "replace": .bool(true)])
    }

    @Test("Agent instructions list every command and no fixed track IDs")
    func instructions() {
        let text = CommandCatalog.instructions
        for spec in CommandCatalog.specs { #expect(text.contains(spec.usage), "\(spec.name)") }
        #expect(!text.contains(#""v1""#))
        #expect(!text.contains(#""t1""#))
        #expect(text.contains("bashcut timeline get"))
    }
}

extension CLIBinding {
    var isFlag: Bool {
        if case .flag = self { return true }
        return false
    }
}
