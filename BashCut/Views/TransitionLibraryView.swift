import BashCutProject
import SwiftUI

struct TransitionLibraryView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transitions").font(.headline)
            Text("Select a video clip beside a cut, then choose a transition.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                ForEach(TimelineTransition.renderedKinds, id: \.self) { kind in
                    Button {
                        document.setSelectedTransition(kind: kind)
                    } label: {
                        Label(title(kind), systemImage: icon(kind))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let active = document.selectedTransition {
                Divider()
                LabeledContent("Active") { Text(title(active.kind)) }
                Stepper(
                    "Duration: \(active.duration) frames",
                    onIncrement: { document.adjustSelectedTransitionDuration(by: 3) },
                    onDecrement: { document.adjustSelectedTransitionDuration(by: -3) })
                Button("Remove transition", role: .destructive) {
                    document.removeSelectedTransition()
                }
            }
        }
    }

    private func title(_ kind: String) -> LocalizedStringKey {
        LocalizedStringKey(kind.capitalized)
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "dissolve": "circle.lefthalf.filled"
        case "whip": "arrow.right"
        case "blink": "sun.max.fill"
        case "zoom": "plus.magnifyingglass"
        case "spin": "arrow.clockwise"
        case "shutter": "camera.aperture"
        default: "rectangle.split.2x1"
        }
    }
}
