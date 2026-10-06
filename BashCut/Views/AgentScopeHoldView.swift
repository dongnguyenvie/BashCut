import SwiftUI

/// Asks the user about an agent edit outside the attached clips (#356). The edit waits until they answer.
struct AgentScopeHoldView: View {
    let hold: AgentScopeHold
    let resolve: (AgentScopeChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("\(hold.agent) wants to edit outside the attached clips", systemImage: "scope")
                .font(.title2.bold()).foregroundStyle(.orange)
            Text(verbatim: hold.label).font(.system(.body, design: .monospaced))
            Text("This edit also changes: \(hold.outside)").textSelection(.enabled)
            Text("Allow for This Request lets the agent change anything else until your next message, or until the clips sent to a terminal change.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reject") { resolve(.reject) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Allow for This Request") { resolve(.allowRequest) }
                Button("Allow Once") { resolve(.allowOnce) }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 520).interactiveDismissDisabled()
    }
}
