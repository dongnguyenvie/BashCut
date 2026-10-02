import BashCutProject
import Foundation

/// Turns `bashcut <group> <command> …` words into a validated request using the command specs.
public enum CommandLineParser {
    public struct Invocation: Sendable {
        public let spec: CommandSpec
        public let params: [String: JSONValue]
        /// Global `--format`: `text` prints string results without JSON quoting.
        public let format: String
    }

    public struct Failure: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static var help: String {
        (["Commands:"] + CommandCatalog.specs.map { "  \($0.usage)" }).joined(separator: "\n")
    }

    public static func parse(_ words: [String]) throws -> Invocation {
        var words = words
        let format = try extractFormat(&words)
        guard let spec = CommandCatalog.specs.first(where: { words.starts(with: $0.cliWords) }) else {
            throw Failure(message: "Unknown command: \(words.prefix(2).joined(separator: " "))\n\(help)")
        }
        do {
            var params = try parameters(Array(words.dropFirst(spec.cliWords.count)), for: spec)
            if let format, spec.parameters.contains(where: { $0.name == "format" }) { params["format"] = .string(format) }
            return Invocation(spec: spec, params: try spec.validate(params), format: format ?? "json")
        } catch let failure as RPCFailure {
            throw Failure(message: "\(failure.message)\nUsage: \(spec.usage)")
        } catch let failure as Failure {
            throw Failure(message: "\(failure.message)\nUsage: \(spec.usage)")
        }
    }

    private static func extractFormat(_ words: inout [String]) throws -> String? {
        var format: String?
        var index = 0
        while index < words.count, words[index] != "--" {
            if words[index] == "--format" {
                guard index + 1 < words.count else { throw Failure(message: "--format needs a value") }
                format = words[index + 1]
                words.removeSubrange(index...(index + 1))
            } else if words[index].hasPrefix("--format=") {
                format = String(words[index].dropFirst("--format=".count))
                words.remove(at: index)
            } else {
                index += 1
            }
        }
        if let format, !["json", "text"].contains(format) { throw Failure(message: "--format must be json or text") }
        return format
    }

    private static func parameters(_ words: [String], for spec: CommandSpec) throws -> [String: JSONValue] {
        var params: [String: JSONValue] = [:]
        var positionals = spec.parameters.filter(\.cli.isPositional)[...]
        var index = 0
        var optionsEnded = false
        while index < words.count {
            let word = words[index]
            index += 1
            if !optionsEnded, word == "--" {
                optionsEnded = true
            } else if !optionsEnded, word.hasPrefix("--") {
                let parts = word.dropFirst(2).split(separator: "=", maxSplits: 1).map(String.init)
                guard let parameter = spec.parameters.first(where: { $0.cli == .option(parts[0]) || $0.cli == .flag(parts[0]) })
                else { throw Failure(message: "Unknown option \(word)") }
                if parameter.cli == .flag(parts[0]) {
                    guard parts.count == 1 else { throw Failure(message: "\(word) takes no value") }
                    params[parameter.name] = .bool(true)
                    continue
                }
                let text: String
                if parts.count == 2 {
                    text = parts[1]
                } else {
                    guard index < words.count else { throw Failure(message: "--\(parts[0]) needs a value") }
                    text = words[index]
                    index += 1
                }
                params[parameter.name] = try value(text, for: parameter)
            } else {
                guard let parameter = positionals.popFirst() else { throw Failure(message: "Unexpected argument \(word)") }
                params[parameter.name] = try value(word, for: parameter)
            }
        }
        return params
    }

    private static func value(_ text: String, for parameter: CommandParameter) throws -> JSONValue {
        switch parameter.cli {
        case .positionalJSONFile:
            let url = URL(fileURLWithPath: text)
            do {
                return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
            } catch {
                throw Failure(message: "Cannot read JSON from \(text): \(error.localizedDescription)")
            }
        case .positionalTextFile(let maximumBytes):
            return .string(try readText(text, maximumBytes: maximumBytes))
        case .positional, .option, .flag:
            if parameter.isPath {
                return .string(URL(fileURLWithPath: (text as NSString).expandingTildeInPath).standardizedFileURL.path)
            }
            guard parameter.kind == .integer else { return .string(text) }
            guard let number = Int(text) else { throw Failure(message: "\(parameter.name) must be an integer") }
            return .integer(number)
        }
    }

    private static func readText(_ path: String, maximumBytes: Int) throws -> String {
        let file: FileHandle
        do { file = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)) } catch {
            throw Failure(message: "Cannot open \(path)")
        }
        defer { try? file.close() }
        let data = (try? file.read(upToCount: maximumBytes + 1)) ?? Data()
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw Failure(message: "\(path) must be UTF-8 text of at most \(maximumBytes / 1024) KiB")
        }
        return text
    }
}
