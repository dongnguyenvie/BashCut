import SwiftUI

struct PrivilegedApprovalView: View {
    let prompt: PrivilegedApprovalPrompt
    let resolve: (Bool) -> Void

    /// Exports are not the only privileged actions: library, knowledge and agent setup changes ask here too.
    private var isExport: Bool { prompt.method == "export.start" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Agent action requires approval", systemImage: "exclamationmark.shield")
                .font(.title2.bold()).foregroundStyle(.orange)
            Text("\(prompt.author.rawValue.capitalized) requested \(prompt.method).")
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(prompt.arguments) { argument in
                    GridRow {
                        Text(argument.name).foregroundStyle(.secondary)
                        Text(argument.value).font(.system(.body, design: .monospaced))
                            .textSelection(.enabled).lineLimit(3)
                    }
                }
            }.padding(12).background(.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 8))
            Text(isExport
                ? "Approving starts a background export and writes the listed output files."
                : "Approving lets the agent make this change with the values above.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Deny") { resolve(false) }.keyboardShortcut(.cancelAction)
                Button(isExport ? "Approve and export" : "Approve") { resolve(true) }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 560).interactiveDismissDisabled()
    }
}
