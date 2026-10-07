import BashCutProject
import Foundation

/// The five points where an agent's run stops for the user (P1-D4, T00 §9): G1 brief, G2 strategy, G3 rough-cut
/// sheet, G4 script before speech is made, G5 draft before export. Each is `ask`, `notify` or `skip`, set by the user;
/// every gate asks until the user changes it.
public enum WorkflowGate: String, CaseIterable, Sendable {
    case brief = "G1", strategy = "G2", roughCut = "G3", script = "G4", draft = "G5"

    public enum Mode: String, CaseIterable, Sendable { case ask, notify, skip }

    public var name: String {
        switch self {
        case .brief: "brief"
        case .strategy: "strategy"
        case .roughCut: "roughCut"
        case .script: "script"
        case .draft: "draft"
        }
    }

    public var title: String {
        switch self {
        case .brief: String(localized: "Brief")
        case .strategy: String(localized: "Story and plan")
        case .roughCut: String(localized: "Rough-cut sheet")
        case .script: String(localized: "Script before voiceover")
        case .draft: String(localized: "Draft before export")
        }
    }

    /// `G3` or `roughCut`.
    public init?(id: String) {
        guard let gate = Self.allCases.first(where: { $0.rawValue == id.uppercased() || $0.name == id }) else { return nil }
        self = gate
    }

    public static let roundLimits = 1...10
}

extension SettingsModel {
    public func gateMode(_ gate: WorkflowGate) -> WorkflowGate.Mode {
        workflowGatesRaw[gate.rawValue].flatMap(WorkflowGate.Mode.init(rawValue:)) ?? .ask
    }

    public func setGateMode(_ gate: WorkflowGate, _ mode: WorkflowGate.Mode) {
        workflowGatesRaw[gate.rawValue] = mode == .ask ? nil : mode.rawValue
    }

    /// `{gates: [{id, name, mode}], maxReviewRounds}` for `workflow.gates` and `context.get`.
    public var workflowJSON: JSONValue {
        .object([
            "gates": .array(WorkflowGate.allCases.map { gate in
                .object(["id": .string(gate.rawValue), "name": .string(gate.name), "mode": .string(gateMode(gate).rawValue)])
            }),
            "maxReviewRounds": .integer(maxReviewRounds),
        ])
    }
}
