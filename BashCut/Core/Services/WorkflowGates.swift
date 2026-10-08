import BashCutProject
import Foundation

/// A point where an agent's run stops for the user (P1-D4, T00 §9). Five are built in: G1 brief, G2 strategy, G3
/// rough-cut sheet, G4 script before speech is made, G5 draft before export. Any other name is a gate too (a skill's
/// own stop, flexibility audit A6). Each is `ask`, `notify` or `skip`, set by the user; every gate is skipped until the
/// user changes it, so an agent's run goes on without stopping.
public struct WorkflowGate: Hashable, Sendable {
    /// `G1`…`G5`, or the name of a gate a skill asked for.
    public let id: String

    public enum Mode: String, CaseIterable, Sendable { case ask, notify, skip }

    public static let brief = WorkflowGate(id: "G1", builtIn: ())
    public static let strategy = WorkflowGate(id: "G2", builtIn: ())
    public static let roughCut = WorkflowGate(id: "G3", builtIn: ())
    public static let script = WorkflowGate(id: "G4", builtIn: ())
    public static let draft = WorkflowGate(id: "G5", builtIn: ())
    public static let builtIns = [brief, strategy, roughCut, script, draft]

    private static let builtInNames = ["G1": "brief", "G2": "strategy", "G3": "roughCut", "G4": "script", "G5": "draft"]

    private init(id: String, builtIn: Void) { self.id = id }

    /// `G3` or `roughCut` for a built-in gate; else any name of 1–40 letters, digits, `.`, `-` or `_` that does not
    /// look like a built-in ID (`G9`).
    public init?(id: String) {
        let text = id.trimmingCharacters(in: .whitespaces)
        if let gate = Self.builtIns.first(where: { $0.id == text.uppercased() || $0.name == text }) {
            self = gate
            return
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        guard (1...40).contains(text.count), text.unicodeScalars.allSatisfy(allowed.contains),
            text.range(of: #"^[Gg]\d+$"#, options: .regularExpression) == nil
        else { return nil }
        self.id = text
    }

    public var isBuiltIn: Bool { Self.builtInNames[id] != nil }

    /// The mode of every gate until the user changes it.
    public static let defaultMode = Mode.skip

    public var name: String { Self.builtInNames[id] ?? id }

    public var title: String {
        switch id {
        case "G1": String(localized: "Brief")
        case "G2": String(localized: "Story and plan")
        case "G3": String(localized: "Rough-cut sheet")
        case "G4": String(localized: "Script before voiceover")
        case "G5": String(localized: "Draft before export")
        default: id
        }
    }

    /// `G3 · Rough-cut sheet`, or a skill's gate by its name.
    public var label: String { isBuiltIn ? "\(id) · \(title)" : id }

    public static let roundLimits = 1...10
}

extension SettingsModel {
    public func gateMode(_ gate: WorkflowGate) -> WorkflowGate.Mode {
        workflowGatesRaw[gate.id].flatMap(WorkflowGate.Mode.init(rawValue:)) ?? WorkflowGate.defaultMode
    }

    /// A built-in gate at the default mode is not stored; a skill's gate is always stored, so Settings lists it.
    public func setGateMode(_ gate: WorkflowGate, _ mode: WorkflowGate.Mode) {
        workflowGatesRaw[gate.id] = mode == WorkflowGate.defaultMode && gate.isBuiltIn ? nil : mode.rawValue
    }

    /// Lists a skill's gate in Settings (at the default mode) the first time an agent stops at it.
    public func noteGate(_ gate: WorkflowGate) {
        if !gate.isBuiltIn, workflowGatesRaw[gate.id] == nil { workflowGatesRaw[gate.id] = WorkflowGate.defaultMode.rawValue }
    }

    /// The built-in gates, then the skills' gates seen so far by name.
    public var workflowGates: [WorkflowGate] {
        WorkflowGate.builtIns + workflowGatesRaw.keys.compactMap(WorkflowGate.init(id:)).filter { !$0.isBuiltIn }
            .sorted { $0.id < $1.id }
    }

    /// `{gates: [{id, name, mode}], maxReviewRounds}` for `workflow.gates` and `context.get`.
    public var workflowJSON: JSONValue {
        .object([
            "gates": .array(workflowGates.map { gate in
                .object(["id": .string(gate.id), "name": .string(gate.name), "mode": .string(gateMode(gate).rawValue)])
            }),
            "maxReviewRounds": .integer(maxReviewRounds),
        ])
    }
}
