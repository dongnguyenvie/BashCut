import BashCutProject
import SwiftUI

struct AgentChangeToast: View {
    let change: AgentChangeRecord
    let canUndo: Bool
    let show: () -> Void
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(change.author.rawValue.capitalized): \(change.label)").font(.callout.bold())
                Text("\(change.changes.count) timeline changes").font(.caption).foregroundStyle(.secondary)
            }
            Button("Undo", action: undo).disabled(!canUndo)
            Button("Show Changes", action: show)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.cyan.opacity(0.3)))
        .shadow(radius: 8)
        .padding(14)
    }
}

struct AgentChangesView: View {
    let change: AgentChangeRecord
    let canUndo: Bool
    let jump: (ProjectItemChange) -> Void
    let undo: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Show Changes").font(.title2)
                    Text("\(change.author.rawValue.capitalized) · \(change.label)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Undo", action: undo).disabled(!canUndo)
                Button("Done", action: done)
            }
            if change.changes.isEmpty {
                ContentUnavailableView("No item changes", systemImage: "checkmark.circle")
            } else {
                List(change.changes) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.kind.rawValue.capitalized)
                                .font(.caption.bold())
                                .foregroundStyle(color(item.kind))
                            Text(item.itemID).font(.body.monospaced())
                            Spacer()
                            if item.after != nil { Button("Jump") { jump(item) } }
                        }
                        Text(trackDescription(item)).font(.caption).foregroundStyle(.secondary)
                        if !item.changedKeys.isEmpty {
                            Text("Changed: " + item.changedKeys.joined(separator: ", "))
                                .font(.caption.monospaced()).textSelection(.enabled)
                        }
                        HStack(alignment: .top) {
                            snapshot("Before", item.before)
                            snapshot("After", item.after)
                        }
                    }.padding(.vertical, 5)
                }
            }
        }.padding(20).frame(width: 680, height: 520, alignment: .top).preferredColorScheme(.dark)
    }

    private func snapshot(_ title: String, _ item: Item?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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
