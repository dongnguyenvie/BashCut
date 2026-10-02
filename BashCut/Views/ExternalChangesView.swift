import BashCutProject
import SwiftUI

struct ExternalChangesView: View {
    let changes: ProjectChangeSet
    let keepApp: () -> Void
    let loadDisk: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("External project differences").font(.title2)
                    Text("App version → disk version").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: done)
            }
            if changes.isEmpty {
                ContentUnavailableView("No differences", systemImage: "checkmark.circle")
            } else {
                summary
                List(changes.items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.kind.rawValue.capitalized).font(.caption.bold())
                                .foregroundStyle(color(item.kind))
                            Text(item.itemID).font(.body.monospaced())
                            Spacer()
                            Text(trackDescription(item)).font(.caption).foregroundStyle(.secondary)
                        }
                        if !item.changedKeys.isEmpty {
                            Text("Changed: " + item.changedKeys.joined(separator: ", "))
                                .font(.caption.monospaced()).textSelection(.enabled)
                        }
                        HStack {
                            snapshot("App", item.before)
                            snapshot("Disk", item.after)
                        }
                    }.padding(.vertical, 4)
                }
            }
            Divider()
            HStack {
                Text("Choose which complete project version to keep.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Keep app version", action: keepApp)
                Button("Load disk version", action: loadDisk).buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 720, height: 560, alignment: .top).preferredColorScheme(.dark)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !changes.projectKeys.isEmpty {
                Text("Project: " + changes.projectKeys.joined(separator: ", "))
            }
            if !changes.mediaIDs.isEmpty { Text("Media: " + changes.mediaIDs.joined(separator: ", ")) }
            if !changes.trackIDs.isEmpty { Text("Tracks: " + changes.trackIDs.joined(separator: ", ")) }
            Text("Timeline items: \(changes.items.count)")
        }.font(.caption.monospaced()).textSelection(.enabled)
    }

    private func snapshot(_ title: String, _ item: Item?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption.bold())
            Text(item.map { "\($0.at)–\($0.end) · in \($0.sourceIn)" } ?? "—")
                .font(.caption.monospaced())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trackDescription(_ item: ProjectItemChange) -> String {
        let before = item.beforeTrackName ?? "—"
        let after = item.afterTrackName ?? "—"
        return before == after ? after : "\(before) → \(after)"
    }

    private func color(_ kind: ProjectItemChange.Kind) -> Color {
        switch kind {
        case .added: .green
        case .removed: .red
        case .modified: .orange
        }
    }
}
