import SwiftUI

/// Asks before Claude Code or Codex starts in a folder it does not trust yet, in place of the CLI's own menu.
struct AgentFolderTrustView: View {
    let prompt: AgentFolderTrustPrompt
    let resolve: (AgentFolderTrustPrompt.Answer) -> Void
    /// Ticked: one answer covers every project in the projects folder, so it is not asked again.
    @State private var wholeProjectsFolder = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                String(format: String(localized: "Let %@ work in “%@”?"), prompt.agent, prompt.folder.lastPathComponent),
                systemImage: "folder.badge.questionmark"
            ).font(.title2.bold())
            Text("It can read, edit and run files there.")
            Text(prompt.folder.path).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled).lineLimit(3)
            if let projects = prompt.projectsFolder {
                Toggle(isOn: $wholeProjectsFolder) {
                    Text(String(format: String(localized: "Always for every project in “%@”"), projects.lastPathComponent))
                }.toggleStyle(.checkbox).help(projects.path)
            }
            Text("BashCut saves your answer where \(prompt.agent) keeps it, so it does not ask again.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Not now") { resolve(.notNow) }.keyboardShortcut(.cancelAction)
                Button("Allow") { resolve(prompt.projectsFolder != nil && wholeProjectsFolder ? .allowProjectsFolder : .allow) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 500).interactiveDismissDisabled()
    }
}
