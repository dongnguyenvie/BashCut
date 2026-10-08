import BashCutDocument
import SwiftUI

/// Where an agent's run stops for you (P1-D4): each gate (built in, or one a skill stopped at) asks, tells you, or is
/// skipped, and the review round limit.
struct WorkflowGatesSettings: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        SettingsSection("Workflow gates") {
            ForEach(settings.workflowGates, id: \.self) { gate in
                SettingsRow(verbatim: gate.label, keywords: ["gate", "checkpoint", "approve", gate.name]) {
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
            Text("Agents wait for your answer in BashCut at a gate set to Ask me, and tell you about one set to Tell me and keep editing. Agents can make a gate ask but cannot loosen it or answer it themselves.")
        }
    }
}
