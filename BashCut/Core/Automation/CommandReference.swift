import BashCutProject
import Foundation

/// `docs/reference/commands.md`, generated from `CommandCatalog` so the published list of CLI commands and MCP
/// tools can never miss one. `scripts/update-commands.sh` rewrites it; `CommandReferenceTests` fails when stale.
public enum CommandReference {
    public static func markdown(_ specs: [CommandSpec] = CommandCatalog.specs) -> String {
        var lines = [
            "# Command reference",
            "",
            "<!-- Generated from CommandCatalog by scripts/update-commands.sh. Do not edit by hand. -->",
            "",
            "Every automation command, \(specs.count) in all. Each is the same command on the CLI (`bashcut …`), as an",
            "MCP tool (`bashcut_<group>_<command>`, same parameter names as JSON-RPC) and over the socket. Modes and",
            "approval are explained in the [automation guide](../guides/automation.md#permission-modes).",
        ]
        var groups: [String] = []
        for spec in specs where !groups.contains(spec.cliWords[0]) { groups.append(spec.cliWords[0]) }
        for group in groups {
            lines += ["", "## \(group)"]
            for spec in specs where spec.cliWords[0] == group {
                lines += ["", "### `\(spec.usage)`", ""] + entry(spec).dropFirst(2)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One command: usage, description, mode and parameters (`bashcut help GROUP COMMAND` prints it).
    public static func entry(_ spec: CommandSpec) -> [String] {
        var lines = [spec.usage, "", spec.summary, ""]
        lines.append("- Mode: \(spec.mode.rawValue) · Runs: \(runs(spec.execution)) · MCP: `\(spec.mcpToolName)`")
        for parameter in spec.parameters {
            lines.append("- `\(parameter.name)`: \(details(parameter)). \(parameter.summary)")
        }
        return lines
    }

    private static func runs(_ execution: CommandSpec.Execution) -> String {
        switch execution {
        case .immediate: "immediately"
        case .job: "as a background job (`jobs wait` until it ends)"
        case .approval: "after the user approves in the app"
        }
    }

    private static func details(_ parameter: CommandParameter) -> String {
        var parts = [parameter.kind.rawValue + (parameter.required ? ", required" : "")]
        if let choices = parameter.choices { parts.append("one of " + choices.joined(separator: ", ")) }
        switch (parameter.minimum, parameter.maximum) {
        case (let low?, let high?): parts.append("\(low)…\(high)")
        case (let low?, nil): parts.append("≥ \(low)")
        case (nil, let high?): parts.append("≤ \(high)")
        case (nil, nil): break
        }
        if let range = parameter.range { parts.append("\(number(range.lowerBound))…\(number(range.upperBound))") }
        if let value = parameter.defaultValue, let data = try? JSONEncoder().encode(value),
            let text = String(data: data, encoding: .utf8)
        {
            parts.append("default \(text)")
        }
        if parameter.isPath { parts.append("path") }
        return parts.joined(separator: ", ")
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
