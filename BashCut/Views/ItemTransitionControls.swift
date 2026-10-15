import BashCutProject
import SwiftUI

/// Inspector › Video/Text › In and Out: a transition kind as the item's own entrance and exit (`enter`, `exit`),
/// played inside its frame, with its length and easing. Every change is `setItemTransition`, like `clip.transition`.
/// An edge with a cut transition plays that one instead, and says so.
struct ItemTransitionControls: View {
    @Bindable var document: ProjectDocument
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In and Out").font(.caption.bold())
            side("enter", title: "In transition", cut: document.project.transitions.contains { $0.toItemID == item.id })
            side("exit", title: "Out transition", cut: document.project.transitions.contains { $0.fromItemID == item.id })
        }
    }

    @ViewBuilder private func side(_ field: String, title: LocalizedStringKey, cut: Bool) -> some View {
        let current = ItemTransition(json: item[field])
        Picker(title, selection: Binding(
            get: { current?.kind ?? "none" },
            set: { kind in run { try document.setItemTransition(field, kind: kind == "none" ? nil : kind, items: [item.id]) } })
        ) {
            Text("None").tag("none")
            ForEach(TransitionMotion.groups, id: \.name) { group in
                Section(LocalizedStringKey(group.name)) {
                    ForEach(group.kinds, id: \.self) { Text(TransitionLibraryView.title($0)).tag($0) }
                }
            }
            if let kind = current?.kind, !TimelineTransition.renderedKinds.contains(kind) {
                Text(verbatim: kind).tag(kind)
            }
        }
        .help(field == "enter" ? "How the item comes in, inside its own frame" : "How the item leaves, inside its own frame")
        if let current {
            Stepper(
                "Duration: \(current.duration) frames",
                value: Binding(
                    get: { current.duration },
                    set: { frames in run { try document.setItemTransition(field, kind: current.kind, frames: frames, items: [item.id]) } }),
                in: 1...max(1, item.duration))
            Picker("Easing", selection: Binding(
                get: { current.easing },
                set: { easing in run { try document.setItemTransition(field, kind: current.kind, easing: easing, items: [item.id]) } })
            ) {
                ForEach(TransitionLibraryView.easings(with: current.easing), id: \.self) {
                    Text(TransitionLibraryView.easingTitle($0)).tag($0)
                }
            }
            if cut {
                Text("The cut's transition plays here instead.").foregroundStyle(.secondary)
            }
        }
    }

    private func run(_ body: () throws -> Int) {
        do { _ = try body() } catch { document.message = error.localizedDescription }
    }
}
