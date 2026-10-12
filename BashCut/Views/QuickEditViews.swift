import AppKit
import BashCutAgent
import SwiftUI

/// Quick Edit next to Send to Agent (#449): one-click requests on the selected clips for the open agent, each
/// followed by a review of that range. `agent quick-edit` does the same from the CLI and MCP.
enum QuickEditChoice {
    /// The one-click kinds in menu order; Other… opens the sheet for custom text.
    static let kinds: [QuickEdit] = [.faster, .remove, .musicLower, .caption, .punchIn]

    static func title(_ kind: QuickEdit) -> String {
        switch kind {
        case .faster: String(localized: "Faster")
        case .remove: String(localized: "Remove this part")
        case .musicLower: String(localized: "Lower the music")
        case .caption: String(localized: "Add a caption")
        case .punchIn: String(localized: "More punch-ins")
        case .custom: String(localized: "Other…")
        }
    }

    static func icon(_ kind: QuickEdit) -> String {
        switch kind {
        case .faster: "hare"
        case .remove: "scissors"
        case .musicLower: "speaker.wave.1"
        case .caption: "captions.bubble"
        case .punchIn: "plus.magnifyingglass"
        case .custom: "text.bubble"
        }
    }

    /// Runs a quick edit on the selection; Other… opens the sheet. Failures go to the status bar.
    @MainActor static func run(_ kind: QuickEdit, in document: ProjectDocument) {
        guard kind != .custom else {
            document.ui.showQuickEdit = true
            return
        }
        do { try document.quickEdit(kind) } catch { document.message = error.localizedDescription }
    }

    /// The clip menus' Quick Edit submenu.
    @MainActor static func menuItem(_ document: ProjectDocument) -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let enabled = !document.selectedItems.isEmpty && document.agents.canDeliver
        for kind in kinds + [.custom] {
            let entry = ClosureMenuItem(title(kind)) { [weak document] in
                guard let document else { return }
                run(kind, in: document)
            }
            entry.isEnabled = enabled
            menu.addItem(entry)
        }
        let item = NSMenuItem(title: String(localized: "Quick Edit"), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// The Inspector's Quick Edit menu, beside Send to Agent.
struct QuickEditMenu: View {
    let document: ProjectDocument

    var body: some View {
        Menu {
            ForEach(QuickEditChoice.kinds, id: \.rawValue) { kind in
                Button { QuickEditChoice.run(kind, in: document) } label: {
                    Label(QuickEditChoice.title(kind), systemImage: QuickEditChoice.icon(kind))
                }
            }
            Divider()
            Button { QuickEditChoice.run(.custom, in: document) } label: {
                Label(QuickEditChoice.title(.custom), systemImage: QuickEditChoice.icon(.custom))
            }
        } label: {
            Label("Quick Edit", systemImage: "bolt")
        }
        .fixedSize()
        .disabled(document.selectedItems.isEmpty || !document.agents.canDeliver)
        .help("Ask the agent for a quick change to the selected clips, then a review of that part")
    }
}

/// Quick Edit › Other…: the request for the selected clips in the user's words.
struct QuickEditSheet: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick edit").font(.title3.bold())
            Text(String(format: String(localized: "%d clips selected"), document.selectedItems.count))
                .foregroundStyle(.secondary)
            TextEditor(text: Bindable(document.ui).quickEditDraft)
                .font(.body).frame(minHeight: 90).scrollContentBackground(.hidden)
                .padding(6).background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            Text("The agent changes only these clips, then reviews this part.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { document.ui.showQuickEdit = false }.keyboardShortcut(.cancelAction)
                Button("Send") {
                    do {
                        try document.quickEdit(.custom, text: document.ui.quickEditDraft)
                        document.ui.quickEditDraft = ""
                        document.ui.showQuickEdit = false
                    } catch {
                        document.message = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(document.ui.quickEditDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || document.selectedItems.isEmpty)
            }
        }
        .padding(20).frame(width: 420)
    }
}
