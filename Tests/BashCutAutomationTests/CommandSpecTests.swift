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
        #expect(values == ["text": .string("Xin chào"), "takes": .integer(3), "keepTakes": .bool(false)])
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

    @Test("Number parameters parse from the CLI, check their range and publish it to MCP")
    func numbers() throws {
        let add = try CommandLineParser.parse([
            "adjustment", "add", "--look", "vivid", "--exposure", "0.5", "--lut-strength", "1", "--base-rev", "3",
        ])
        #expect(add.params["exposure"] == .number(0.5))
        #expect(add.params["lutStrength"] == .number(1))
        #expect(throws: (any Error).self) {
            try CommandLineParser.parse(["adjustment", "add", "--saturation", "lots", "--base-rev", "3"])
        }
        let spec = try #require(CommandCatalog.spec(named: "adjustment.add"))
        #expect(throws: RPCFailure.self) { try spec.validate(["saturation": .number(9), "baseRev": .integer(1)]) }
        #expect(try spec.validate(["saturation": .integer(2), "baseRev": .integer(1)])["saturation"] == .integer(2))
        let saturation = spec.inputSchema.object["properties"]?.object["saturation"]?.object ?? [:]
        #expect(saturation["type"] == .string("number"))
        #expect(saturation["maximum"] == .number(4))
    }

    @Test("clip speed parses like the Inspector: optional item, number speed, keep-duration flag")
    func clipSpeed() throws {
        let speed = try CommandLineParser.parse(["clip", "speed", "m1", "--speed", "1.5", "--keep-duration", "--base-rev", "7"])
        #expect(speed.spec.mode == .edit)
        #expect(speed.params == [
            "item": .string("m1"), "speed": .number(1.5), "keepDuration": .bool(true), "baseRev": .integer(7),
        ])
        let spec = try #require(CommandCatalog.spec(named: "clip.speed"))
        #expect(throws: RPCFailure.self) { try spec.validate(["speed": .number(40), "baseRev": .integer(1)]) }
        #expect(UIAction.matching("clip.speed-up") == [.speedUp])
        #expect(UIAction.speedLabel(1.5) == "1.5×" && UIAction.speedLabel(2) == "2×" && UIAction.speedLabel(0.25) == "0.25×")
    }

    @Test("Plugin commands take JSON parameters on the CLI and publish an object schema to MCP")
    func pluginCommands() throws {
        let run = try CommandLineParser.parse(["plugins", "run", "example.toolkit.grade", "--params", #"{"mode":"vivid"}"#])
        #expect(run.spec.execution == .job)
        #expect(run.params == ["action": .string("example.toolkit.grade"), "params": .object(["mode": .string("vivid")])])
        #expect(throws: CommandLineParser.Failure.self) {
            try CommandLineParser.parse(["plugins", "run", "example.toolkit.grade", "--params", "{not json"])
        }
        let spec = try #require(CommandCatalog.spec(named: "plugins.run"))
        #expect(spec.inputSchema.object["properties"]?.object["params"]?.object["type"] == .string("object"))
        let set = try CommandLineParser.parse(["plugins", "set", "example.toolkit", "--hooks", "off"])
        #expect(set.params == ["plugin": .string("example.toolkit"), "hooks": .bool(false)])
        #expect(CommandCatalog.spec(named: "plugins.actions")?.mode == .read)
        #expect(CommandCatalog.dialogs.contains("plugin-proposals"))
        let search = try CommandLineParser.parse(["plugins", "search", "silence", "--capability", "audio.beats", "--refresh"])
        #expect(search.params == ["query": .string("silence"), "capability": .string("audio.beats"), "refresh": .bool(true)])
        #expect(search.spec.mode == .read)
        let install = try CommandLineParser.parse(["plugins", "install", "bashcut.silence-markers", "--version", "0.2.0"])
        #expect(install.spec.execution == .job && install.spec.mode == .edit)
        #expect(install.params == ["plugin": .string("bashcut.silence-markers"), "version": .string("0.2.0")])
        // Add Plugin… from this Mac (#83): paths become absolute; validate only reads.
        let local = try CommandLineParser.parse(["plugins", "install", "--path", "~/my-plugin.zip", "--scope", "project"])
        #expect(local.params["path"] == .string(NSHomeDirectory() + "/my-plugin.zip"))
        #expect(local.params["scope"] == .string("project") && local.params["plugin"] == nil)
        #expect(throws: CommandLineParser.Failure.self) {
            try CommandLineParser.parse(["plugins", "install", "--path", "/tmp/p", "--scope", "everywhere"])
        }
        let validate = try CommandLineParser.parse(["plugins", "validate", "/tmp/my-plugin"])
        #expect(validate.spec.mode == .read && validate.params == ["path": .string("/tmp/my-plugin")])
        let remove = try CommandLineParser.parse(["plugins", "remove", "bashcut.vieneu-tts", "--data"])
        #expect(remove.spec.mode == .edit && remove.params["data"] == .bool(true))
        #expect(try CommandLineParser.parse(["plugins", "setup", "bashcut.vieneu-tts"]).params == ["plugin": .string("bashcut.vieneu-tts")])
    }

    @Test("The CLI parses positionals, options, flags, files and the global format from specs")
    func commandLine() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bashcut-cli-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ops = directory.appendingPathComponent("ops.json")
        try Data(#"[{"op":"split","item":"c","atFrame":30}]"#.utf8).write(to: ops)

        let apply = try CommandLineParser.parse(["timeline", "apply", ops.path, "--base-rev", "4", "--dry-run"])
        #expect(apply.spec.name == "timeline.apply")
        #expect(apply.params["baseRev"] == .integer(4))
        #expect(apply.params["dryRun"] == .bool(true))
        #expect(apply.params["label"] == .string("Agent edit"))
        #expect(apply.params["ops"]?.array.count == 1)
        #expect(apply.format == "json")

        let speak = try CommandLineParser.parse(["voice", "speak", "--takes=2", "--", "--hello"])
        #expect(speak.params == ["text": .string("--hello"), "takes": .integer(2), "keepTakes": .bool(false)])

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
        let view = try CommandLineParser.parse(
            ["ui", "view", "--zoom", "480", "--zoom-anchor", "90", "--snap", "off", "--safe-area=on"])
        #expect(view.params == [
            "zoom": .integer(480), "zoomAnchor": .integer(90), "snap": .bool(false), "safeArea": .bool(true),
        ])
        #expect(throws: CommandLineParser.Failure.self) {
            try CommandLineParser.parse(["ui", "view", "--snap", "maybe"])
        }
        let action = try CommandLineParser.parse(["ui", "action", "cmd+b"])
        #expect(action.params == ["action": .string("cmd+b")])
        let skillFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "# Hook\n".write(to: skillFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: skillFile) }
        let skill = try CommandLineParser.parse(["knowledge", "skill", "hook-first", skillFile.path])
        #expect(skill.params == ["name": .string("hook-first"), "text": .string("# Hook\n")])
        let speakKept = try CommandLineParser.parse(["voice", "speak", "Xin chào", "--keep-takes"])
        #expect(speakKept.params["keepTakes"] == .bool(true))
        let inspector = try CommandLineParser.parse(["ui", "view", "--inspector", "color"])
        #expect(inspector.params == ["inspector": .string("color")])

        // Path parameters become absolute against the CLI's working directory.
        let cwd = FileManager.default.currentDirectoryPath
        let create = try CommandLineParser.parse(["project", "create", "--name", "Vlog", "--dir", "projects", "--fps", "30"])
        #expect(create.params["directory"] == .string(URL(fileURLWithPath: cwd).appendingPathComponent("projects").path))
        #expect(create.params["canvas"] == .string("auto"))
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
