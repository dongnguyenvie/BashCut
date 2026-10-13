import AppKit
import BashCutDocument
import SwiftUI

/// Open Recent › View All… (⌃R): every remembered project in the command palette's look, searched by name and path
/// (#529). Return opens, ⌘Return reveals in Finder, × or the context menu removes; a missing project is greyed out.
struct RecentProjectsView: View {
    let document: ProjectDocument
    let close: () -> Void
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var matches: [RecentProject] { RecentProject.filter(document.settings.recentHistory, query: query) }

    var body: some View {
        let matches = matches
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search recent projects by name or path", text: $query)
                    .textFieldStyle(.plain).font(.title3).focused($focused)
                    .onSubmit { open(at: selection) }
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(keys: [.return]) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        reveal(at: selection)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
                    .onExitCommand(perform: close)
            }.padding(12)
            Divider()
            if matches.isEmpty {
                Text(document.settings.recentHistory.isEmpty ? "No recent projects" : "No matching project")
                    .foregroundStyle(.secondary).padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.url) { index, project in
                                row(project, selected: index == selection)
                                    .onTapGesture { open(at: index) }
                            }
                        }.padding(6)
                    }
                    .frame(maxHeight: 420)
                    .onChange(of: selection) {
                        if matches.indices.contains(selection) { proxy.scrollTo(matches[selection].url) }
                    }
                }
            }
        }
        .paletteChrome()
        .onAppear { focused = true }
        .onChange(of: query) { selection = 0 }
    }

    private func row(_ project: RecentProject, selected: Bool) -> some View {
        let exists = project.exists
        return HStack(spacing: 10) {
            Image(systemName: exists ? "film.stack" : "exclamationmark.triangle")
                .foregroundStyle(exists ? Color.cyan : Color.orange).frame(width: 18)
                .help(exists ? "" : String(localized: "The project file is missing"))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: project.title).lineLimit(1)
                Text(verbatim: project.shortPath()).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .truncationMode(.middle)
            }
            .opacity(exists ? 1 : 0.45)
            Spacer()
            if let date = project.lastOpened {
                Text(date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            }
            Button { remove(project) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from Recent Projects")
        }
        .paletteRow(selected: selected)
        .help(project.folder.path)
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.url]) }.disabled(!exists)
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(project.url.path, forType: .string)
            }
            Divider()
            Button("Remove from Recent Projects") { remove(project) }
        }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let count = matches.count
        guard count > 0 else { return .handled }
        selection = min(max(0, selection + step), count - 1)
        return .handled
    }

    /// Opens the row unless its file is gone; a missing project stays listed until it is removed.
    private func open(at index: Int) {
        let matches = matches
        guard matches.indices.contains(index), matches[index].exists else { return }
        let url = matches[index].url
        close()
        // After the window is gone, so the unsaved-changes alert is not fighting it.
        DispatchQueue.main.async { document.openProject(at: url) }
    }

    private func reveal(at index: Int) {
        let matches = matches
        guard matches.indices.contains(index), matches[index].exists else { return }
        NSWorkspace.shared.activateFileViewerSelecting([matches[index].url])
    }

    private func remove(_ project: RecentProject) {
        document.settings.forgetRecentProject(project.url)
        selection = min(selection, max(0, matches.count - 1))
    }
}
