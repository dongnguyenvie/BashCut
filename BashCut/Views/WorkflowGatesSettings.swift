import BashCutDocument
import SwiftUI

/// Where an agent's run stops for you (P1-D4): each gate asks, tells you, or is skipped, and the review round limit.
struct WorkflowGatesSettings: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        SettingsSection("Workflow gates") {
            ForEach(WorkflowGate.allCases, id: \.self) { gate in
                SettingsRow(verbatim: "\(gate.rawValue) · \(gate.title)", keywords: ["gate", "checkpoint", "approve", gate.name]) {
                    Picker(gate.title, selection: Binding(get: { settings.gateMode(gate) }, set: { settings.setGateMode(gate, $0) })) {
                        Text("Ask me").tag(WorkflowGate.Mode.ask)
                        Text("Tell me").tag(WorkflowGate.Mode.notify)
                        Text("Skip").tag(WorkflowGate.Mode.skip)
                    }
                    .labelsHidden().fixedSize()
                }
            }
            SettingsRow("Most review rounds", keywords: ["review", "rounds", "critic"]) {
                Stepper(value: $settings.maxReviewRounds, in: WorkflowGate.roundLimits) {
                    Text(verbatim: "\(settings.maxReviewRounds)").monospacedDigit()
                }.fixedSize()
            }
        } footer: {
            // swiftlint:disable:next line_length
            Text("Agents stop at each gate and wait for your answer in BashCut. Agents can make a gate ask again but cannot loosen it or answer it themselves.")
        }
    }
}
