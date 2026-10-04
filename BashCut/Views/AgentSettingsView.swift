import AppKit
import BashCutAgent
import BashCutDocument
import SwiftUI

/// Settings › Agents: the agent kit (editing skills) for BashCut's Claude and Codex tabs, setting it up for Claude
/// Code and Codex outside BashCut, and where those agents keep their configuration. `agent status` and
/// `agent setup` do the same from the CLI.
struct AgentSettingsView: View {
    let document: ProjectDocument
    @Bindable var settings: SettingsModel
    @State private var kit: AgentKit?
    @State private var folders: AgentConfigFolders?
    @State private var statuses: [AgentKitSetup.Target: AgentKitSetup.Status] = [:]
    @State private var working: AgentKitSetup.Target?
    @State private var result = ""
    @State private var update = KitUpdate.unknown

    /// The release check for the built-in or downloaded kit; a chosen folder is never updated.
    private enum KitUpdate: Equatable {
        case unknown, checking, upToDate, installing
        case available(AgentKitRelease)
        case failed(String)
    }

    var body: some View {
        Section {
            Toggle("Load the agent kit in Claude and Codex tabs", isOn: $settings.loadAgentKit)
            LabeledContent("Agent kit") {
                HStack {
                    Text(kitSummary).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button("Choose…", action: chooseKit)
                    if settings.agentKitFolder != nil {
                        Button("Use Built-in") {
                            settings.agentKitFolder = nil
                            Task { await load() }
                        }
                    }
                }
            }
            if settings.agentKitFolder == nil { updateRow }
            ForEach(AgentKitSetup.Target.allCases, id: \.self) { target in agentRow(target) }
            if let folders {
                folderRow("Claude Code settings folder", folders.claude, claude: true) { settings.claudeConfigFolder = $0 }
                folderRow("Codex home folder", folders.codex, claude: false) { settings.codexHomeFolder = $0 }
            }
            if !result.isEmpty { Text(result).font(.caption).foregroundStyle(.secondary) }
        } header: {
            HStack {
                Text("Agents")
                Spacer()
                Button {
                    Task { await load() }
                } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Check again")
            }
        } footer: {
            Text("New tabs pick up changes. Claude Code and Codex outside BashCut get the skills and the BashCut MCP server.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task {
            await load()
            if settings.agentKitFolder == nil { await checkForUpdate() }
        }
    }

    private var updateRow: some View {
        LabeledContent("Kit updates") {
            HStack {
                switch update {
                case .unknown: EmptyView()
                case .checking, .installing: ProgressView().controlSize(.small)
                case .upToDate: Text("Up to date").foregroundStyle(.secondary)
                case .available(let release):
                    Text(String(format: String(localized: "Version %@ available"), release.version))
                        .help(release.notes?["en"] ?? "")
                    Button("Download & Update") { install() }.buttonStyle(.borderedProminent)
                case .failed(let message): Text(message).foregroundStyle(.secondary).lineLimit(1).help(message)
                }
                if ![.checking, .installing].contains(update) {
                    Button("Check for Updates") { Task { await checkForUpdate() } }
                }
            }
        }
    }

    private func checkForUpdate() async {
        update = .checking
        do {
            update = try await document.checkAgentKitUpdate().release.map(KitUpdate.available) ?? .upToDate
        } catch { update = .failed(error.localizedDescription) }
    }

    private func install() {
        update = .installing
        Task {
            do {
                result = try await document.updateAgentKit()
                update = .upToDate
            } catch { update = .failed(error.localizedDescription) }
            await load()
        }
    }

    private var kitSummary: String {
        guard let kit else { return String(localized: "Not found") }
        let source = settings.agentKitFolder != nil ? kit.root.path
            : kit.source == .downloaded ? String(localized: "Downloaded") : String(localized: "Built-in")
        return String(localized: "\(kit.skills.count) skills, version \(kit.version) · \(source)")
    }

    private func agentRow(_ target: AgentKitSetup.Target) -> some View {
        let status = statuses[target]
        return LabeledContent(target == .claude ? "Claude Code" : "Codex") {
            HStack {
                Text(summary(status)).foregroundStyle(.secondary).lineLimit(1).help(status?.detail ?? "")
                if working == target {
                    ProgressView().controlSize(.small)
                } else if status?.executable != nil {
                    if status?.installed == true {
                        Button("Update") { run(target, remove: false) }
                        Button("Remove") { run(target, remove: true) }
                    } else {
                        Button("Set Up") { run(target, remove: false) }.disabled(kit == nil)
                    }
                }
            }.disabled(working != nil && working != target)
        }
    }

    private func summary(_ status: AgentKitSetup.Status?) -> String {
        guard let status else { return "…" }
        if status.executable == nil { return String(localized: "Not installed") }
        if status.installed, status.outdated { return String(localized: "Older kit set up: update it") }
        return status.installed ? String(localized: "Kit set up") : String(localized: "Kit not set up")
    }

    /// A menu of the folders found in the home folder, Other… and, once chosen here, Detect.
    private func folderRow(
        _ title: LocalizedStringKey, _ folder: AgentConfigFolders.Folder, claude: Bool,
        set: @escaping (URL?) -> Void
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Menu {
                    ForEach(AgentConfigFolders.candidates(claude: claude), id: \.self) { url in
                        Button(url.path) { update(set, url) }
                    }
                    Divider()
                    Button("Other…") { if let url = choose(directory: folder.url) { update(set, url) } }
                    if folder.origin == .settings { Button("Detect") { update(set, nil) } }
                } label: {
                    Text(folder.url.path).lineLimit(1).truncationMode(.middle)
                }.fixedSize()
                Text(origin(folder.origin)).foregroundStyle(.secondary)
            }
        }
    }

    private func update(_ set: (URL?) -> Void, _ url: URL?) {
        set(url)
        Task { await load() }
    }

    private func origin(_ origin: AgentConfigFolders.Origin) -> String {
        switch origin {
        case .settings: String(localized: "chosen here")
        case .environment: String(localized: "from BashCut's environment")
        case .shell: String(localized: "from your shell profile")
        case .standard: String(localized: "default")
        }
    }

    private func chooseKit() {
        guard let url = choose(directory: settings.agentKitFolder) else { return }
        do {
            try document.chooseAgentKit(url.path)
            result = ""
        } catch { result = error.localizedDescription }
        Task { await load() }
    }

    private func choose(directory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = directory
        return ModalCenter.shared.open(panel, name: "choose-agent-folder")?.first
    }

    private func run(_ target: AgentKitSetup.Target, remove: Bool) {
        working = target
        Task {
            do {
                result = try await document.setUpAgent(target.rawValue, remove: remove)
            } catch { result = error.localizedDescription }
            working = nil
            await load()
        }
    }

    private func load() async {
        kit = try? document.installedAgentKit()
        folders = await document.agentConfigFolders()
        statuses = await document.agentSetupStatuses()
        document.agents.updateKitPrompt(kit: kit, statuses: statuses)
    }
}
