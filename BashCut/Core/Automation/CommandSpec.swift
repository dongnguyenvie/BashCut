import BashCutProject
import Foundation

/// How a parameter is written on the `bashcut` command line.
public enum CLIBinding: Sendable, Equatable {
    case positional
    /// A positional path whose file contents become the value: JSON, or UTF-8 text up to a byte limit.
    case positionalJSONFile
    case positionalTextFile(maximumBytes: Int)
    case option(String)
    case flag(String)

    var isPositional: Bool {
        switch self {
        case .positional, .positionalJSONFile, .positionalTextFile: true
        case .option, .flag: false
        }
    }
}

public struct CommandParameter: Sendable {
    public enum Kind: String, Sendable { case string, integer, boolean, array, object }

    public let name: String
    public let kind: Kind
    public let summary: String
    public let required: Bool
    public let defaultValue: JSONValue?
    public let minimum: Int?
    public let maximum: Int?
    public let choices: [String]?
    public let cli: CLIBinding

    public init(
        _ name: String, _ kind: Kind, _ summary: String, required: Bool = false, default defaultValue: JSONValue? = nil,
        minimum: Int? = nil, maximum: Int? = nil, choices: [String]? = nil, cli: CLIBinding
    ) {
        self.name = name
        self.kind = kind
        self.summary = summary
        self.required = required
        self.defaultValue = defaultValue
        self.minimum = minimum
        self.maximum = maximum
        self.choices = choices
        self.cli = cli
    }
}

/// One automation command, declared once. The registry validates requests against it, the CLI parses
/// arguments from it, the MCP bridge publishes it as a tool and agent instructions are rendered from it.
public struct CommandSpec: Sendable {
    public enum Execution: Sendable { case immediate, job, approval }

    public let name: String
    public let mode: CommandMode
    public let summary: String
    public let parameters: [CommandParameter]
    public let execution: Execution

    public init(
        _ name: String, _ mode: CommandMode, _ summary: String, parameters: [CommandParameter] = [],
        execution: Execution = .immediate
    ) {
        self.name = name
        self.mode = mode
        self.summary = summary
        self.parameters = parameters
        self.execution = execution
    }

    public var mcpToolName: String { "bashcut_" + name.replacingOccurrences(of: ".", with: "_") }
    public var cliWords: [String] { name.split(separator: ".").map(String.init) }

    /// JSON Schema for the MCP tool input.
    public var inputSchema: JSONValue {
        var properties: [String: JSONValue] = [:]
        for parameter in parameters {
            var property: [String: JSONValue] = [
                "type": .string(parameter.kind.rawValue), "description": .string(parameter.summary),
            ]
            if let minimum = parameter.minimum { property["minimum"] = .integer(minimum) }
            if let maximum = parameter.maximum { property["maximum"] = .integer(maximum) }
            if let choices = parameter.choices { property["enum"] = .array(choices.map(JSONValue.string)) }
            if let value = parameter.defaultValue { property["default"] = value }
            if parameter.kind == .array { property["items"] = .object(["type": .string("object")]) }
            properties[parameter.name] = .object(property)
        }
        var schema: [String: JSONValue] = [
            "type": .string("object"), "properties": .object(properties), "additionalProperties": .bool(false),
        ]
        let required = parameters.filter(\.required).map { JSONValue.string($0.name) }
        if !required.isEmpty { schema["required"] = .array(required) }
        return .object(schema)
    }

    /// `bashcut captions generate --media <media> [--replace]`
    public var usage: String {
        let arguments = parameters.map { parameter -> String in
            let text: String
            switch parameter.cli {
            case .positional: text = "<\(parameter.name)>"
            case .positionalJSONFile: text = "<\(parameter.name).json>"
            case .positionalTextFile: text = "<\(parameter.name)-file>"
            case .option(let flag): text = "--\(flag) <\(parameter.name)>"
            case .flag(let flag): text = "--\(flag)"
            }
            return parameter.required ? text : "[\(text)]"
        }
        return (["bashcut"] + cliWords + arguments).joined(separator: " ")
    }

    /// Checks types, ranges, choices and required fields, applies defaults and rejects unknown parameters.
    public func validate(_ params: [String: JSONValue]) throws -> [String: JSONValue] {
        var values = params.filter { $0.value != .null }
        if let unknown = values.keys.sorted().first(where: { key in !parameters.contains { $0.name == key } }) {
            throw RPCFailure(-32602, "Unknown parameter \(unknown) for \(name)")
        }
        for parameter in parameters {
            guard let value = values[parameter.name] ?? parameter.defaultValue else {
                if parameter.required { throw RPCFailure(-32602, "Missing \(parameter.name)") }
                continue
            }
            values[parameter.name] = try parameter.checked(value)
        }
        return values
    }
}

extension CommandParameter {
    /// Returns the value, with integral numbers normalized to integers, or throws when it does not fit.
    func checked(_ value: JSONValue) throws -> JSONValue {
        let normalized: JSONValue
        if kind == .integer, case .number(let number) = value, number.rounded() == number, abs(number) < 1e15 {
            normalized = .integer(Int(number))
        } else {
            normalized = value
        }
        let valid: Bool
        switch (kind, normalized) {
        case (.boolean, .bool), (.array, .array), (.object, .object): valid = true
        case (.string, .string(let text)):
            valid = (!required || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                && (choices?.contains(text) ?? true)
        case (.integer, .integer(let number)):
            valid = number >= (minimum ?? .min) && number <= (maximum ?? .max)
        default: valid = false
        }
        guard valid else { throw RPCFailure(-32602, "\(name) must be \(expectation)") }
        return normalized
    }

    var expectation: String {
        if let choices { return "one of " + choices.joined(separator: ", ") }
        switch (kind, minimum, maximum) {
        case (.integer, let low?, let high?): return "an integer in \(low)...\(high)"
        case (.integer, let low?, nil): return "an integer ≥ \(low)"
        case (.string, _, _) where required: return "a nonempty string"
        default: return kind == .integer ? "an integer" : "a \(kind.rawValue)"
        }
    }
}

/// Typed, already validated access to a command's parameters.
public struct CommandArguments: Sendable {
    public let values: [String: JSONValue]
    public init(_ values: [String: JSONValue]) { self.values = values }

    public func string(_ name: String) throws -> String {
        guard let value = values[name]?.string, !value.isEmpty else { throw RPCFailure(-32602, "Missing \(name)") }
        return value
    }
    public func optionalString(_ name: String) -> String? { values[name]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    public func int(_ name: String) throws -> Int {
        guard let value = values[name]?.int else { throw RPCFailure(-32602, "Missing \(name)") }
        return value
    }
    public func optionalInt(_ name: String) -> Int? { values[name]?.int }
    public func bool(_ name: String) -> Bool { values[name] == .bool(true) }
    public func value(_ name: String) throws -> JSONValue {
        guard let value = values[name] else { throw RPCFailure(-32602, "Missing \(name)") }
        return value
    }
    public subscript(name: String) -> JSONValue? { values[name] }
}
