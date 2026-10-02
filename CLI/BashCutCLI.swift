import ArgumentParser
import BashCutAutomation
import BashCutProject
import Foundation

@main struct BashCutCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bashcut", abstract: "Control the running BashCut editor.")
    @Argument(help: "context, project, timeline, media, captions, beats, voice, plugins, jobs, review, export, or ui")
    var group: String
    @Argument(help: "Command, such as get, apply, select, seek") var command: String
    @Argument(help: "Operations JSON file, item ID, frame, job ID, voiceover text, or notification text")
    var value: String?
    @Option(name: .long, help: "Current timeline revision (required for edits)") var baseRev: Int?
    @Option(name: .long) var label = "Agent edit"
    @Option(name: .long) var format = "json"
    @Option(name: .long, help: "Export preset: tiktok, youtube-1080, youtube-4k, quick-draft, or prores")
    var preset: String?
    @Option(name: .long, help: "Export base name without an extension") var name: String?
    @Option(name: .customLong("output-dir"), help: "Export folder; defaults to the project's render folder")
    var outputDirectory: String?

    @Option(name: .long, help: "Media ID for captions generate or beats detect") var media: String?
    @Option(name: .long, help: "Provider ID overriding the project preference for one request") var provider: String?
    @Option(name: .long, help: "Number of voice takes to generate (1-8)") var takes: Int?
    @Option(name: .customLong("at-frame"), help: "Timeline frame for the generated voiceover") var atFrame: Int?

    @Flag(name: .long, help: "Replace existing captions when importing or generating") var replace = false
    @Flag(name: .customLong("include-srt"), help: "Write a companion SubRip file") var includeSRT = false
    @Flag(name: .customLong("normalize-audio"), help: "Normalize the final mix with an audio.loudness plugin")
    var normalizeAudio = false

    func run() throws {
        let response = try UnixRPCClient.call(
            RPCRequest(
                method: group + "." + command, params: try parameters(),
                token: ProcessInfo.processInfo.environment["BASHCUT_SESSION_TOKEN"]))
        try write(response)
    }

    private func parameters() throws -> [String: JSONValue] {
        var params: [String: JSONValue] = ["label": .string(label), "format": .string(format)]
        if let baseRev { params["baseRev"] = .integer(baseRev) }
        switch (group, command) {
        case ("captions", "import"):
            params["text"] = .string(try readSubRip())
            params["replace"] = .bool(replace)
        case ("timeline", "apply"):
            guard let value else { throw ValidationError("Provide the path to ops.json") }
            params["ops"] = try JSONDecoder().decode(
                JSONValue.self, from: Data(contentsOf: URL(fileURLWithPath: value)))
        case ("export", "start"):
            try addExportParameters(to: &params)
        case ("export", "otio"):
            try addOTIOParameters(to: &params)
        case ("captions", "generate"), ("beats", "detect"), ("voice", "speak"), ("jobs", _):
            try addCapabilityParameters(to: &params)
        case ("ui", _):
            try addUIParameters(to: &params)
        default: break
        }
        return params
    }

    private func addExportParameters(to params: inout [String: JSONValue]) throws {
        guard let preset, let name, !name.isEmpty else {
            throw ValidationError("Export start requires --preset and --name")
        }
        params["preset"] = .string(preset)
        params["name"] = .string(name)
        params["includeSRT"] = .bool(includeSRT)
        params["normalizeAudio"] = .bool(normalizeAudio)
        if let outputDirectory { params["directory"] = .string(outputDirectory) }
    }

    private func addCapabilityParameters(to params: inout [String: JSONValue]) throws {
        if group == "jobs" {
            if let value { params["job"] = .string(value) }
            return
        }
        if let provider { params["provider"] = .string(provider) }
        if command == "speak" {
            guard let value, !value.isEmpty else { throw ValidationError("voice speak requires text") }
            params["text"] = .string(value)
            if let takes { params["takes"] = .integer(takes) }
            if let atFrame { params["atFrame"] = .integer(atFrame) }
            return
        }
        guard let media, !media.isEmpty else { throw ValidationError("\(group) \(command) requires --media") }
        params["media"] = .string(media)
        if command == "generate" { params["replace"] = .bool(replace) }
    }

    private func addOTIOParameters(to params: inout [String: JSONValue]) throws {
        guard let name, !name.isEmpty else { throw ValidationError("OTIO export requires --name") }
        params["name"] = .string(name)
        if let outputDirectory { params["directory"] = .string(outputDirectory) }
    }

    private func addUIParameters(to params: inout [String: JSONValue]) throws {
        if command == "select" { params["item"] = value.map(JSONValue.string) ?? .null }
        if command == "seek" {
            guard let value, let frame = Int(value) else { throw ValidationError("Seek requires an integer frame") }
            params["frame"] = .integer(frame)
        }
        if command == "notify" { params["message"] = .string(value ?? "") }
    }

    private func write(_ response: RPCResponse) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if format == "text", let text = response.result?.string {
            FileHandle.standardOutput.write(Data((text + "\n").utf8))
        } else {
            var data = try encoder.encode(response.result ?? .null)
            data.append(10)
            FileHandle.standardOutput.write(data)
        }
    }
    private func readSubRip() throws -> String {
        guard let value else { throw ValidationError("Provide an SRT file path") }
        let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: value))
        defer { try? file.close() }
        let data = try file.read(upToCount: SubRip.maximumBytes + 1) ?? Data()
        guard data.count <= SubRip.maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw ValidationError("SRT must be UTF-8 and at most 4 MiB")
        }
        return text
    }

}
