import BashCutProject
import SwiftUI

/// One row of the Review sheet: severity, detail, the fix hint and its actions.
extension EditorView {
    func reviewRow(_ issue: ReviewIssue) -> some View {
        let tint: Color = switch issue.severity {
        case .error: .red
        case .warning: .orange
        case .info: .secondary
        }
        return VStack(alignment: .leading, spacing: 5) {
            Label(issue.title, systemImage: issue.severity == .info ? "info.circle" : "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(tint)
            Text(issue.detail).font(.caption)
            if let hint = issue.fix?.hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Jump") {
                    document.preview.seek(issue.frame)
                    document.ui.showReview = false
                }
                if let fix = issue.fix, document.canApply(fix) {
                    if fix.command == "review.measure" {
                        Button("Measure picture") { document.apply(fix, label: issue.title) }
                    } else {
                        Button("Fix") { document.apply(fix, label: issue.title) }
                    }
                }
                Button("Ask agent to fix") {
                    document.ui.showAgentDock = true
                    document.agents.fillInput(
                        "Fix this review issue: " + issue.detail + (issue.fix?.hint.map { " (" + $0 + ")" } ?? ""))
                    document.ui.showReview = false
                }.disabled(document.agents.current == nil && document.agents.chatPluginID == nil)
            }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(tint.opacity(0.08)).cornerRadius(6)
    }
}
