import SwiftUI

/// Asks before Claude Code or Codex starts in a folder it does not trust yet, and before Claude Code first runs in
/// Bypass Permissions mode, in place of the CLI's own menus.
struct AgentFolderTrustView: View {
    let prompt: AgentFolderTrustPrompt
    let resolve: (AgentFolderTrustPrompt.Answer) -> Void
    /// Ticked: one answer covers every project in the projects folder, so it is not asked again.
    @State private var wholeProjectsFolder = true

    private static let bypassText = String(
        localized: """
            BashCut runs %@ in Bypass Permissions mode: it does not ask before each command, so you accept \
            responsibility for what it runs. Allow accepts this once, for every project.
            """)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                prompt.asksFolder
                    ? String(format: String(localized: "Let %@ work in “%@”?"), prompt.agent, prompt.folder.lastPathComponent)
                    : String(format: String(localized: "Let %@ run commands without asking?"), prompt.agent),
                systemImage: prompt.asksFolder ? "folder.badge.questionmark" : "exclamationmark.shield"
            ).font(.title2.bold())
            if prompt.asksFolder {
                Text("It can read, edit and run files there.")
                Text(prompt.folder.path).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(3)
            }
            if prompt.acceptsBypass {
                Text(String(format: Self.bypassText, prompt.agent)).fixedSize(horizontal: false, vertical: true)
            }
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
