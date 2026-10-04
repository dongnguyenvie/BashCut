import BashCutAutomation
import SwiftUI

/// What the viewer shows: the timeline (the edit) or Source (a clip from Media, before it is on the timeline). Both
/// viewers put this switch in the same place, so which picture is on screen is never a guess.
struct ViewerModeSwitch: View {
    let document: ProjectDocument

    private var source: SourceViewerModel { document.sourceViewer }

    var body: some View {
        HStack(spacing: 2) {
            segment(String(localized: "Timeline"), systemImage: "film.stack", active: !source.visible, tint: .accentColor) {
                document.run(.sourceClose)
            }
            .help(source.visible ? String(localized: "Back to the timeline (Esc)") : String(localized: "Showing the timeline"))
            .modifier(EscapeReturnsToTimeline(document: document, enabled: source.visible))
            segment(sourceTitle, systemImage: "photo.on.rectangle", active: source.visible, tint: .cyan) {
                document.run(.sourceShow)
            }
            .disabled(source.media == nil)
            .help(source.media == nil
                ? String(localized: "Click a clip in Media to preview it here before adding it to the timeline")
                : String(localized: "Preview the Media clip last opened, before adding it to the timeline"))
        }
        .padding(2)
        .background(Color.secondary.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Viewer mode")
    }

    private var sourceTitle: String {
        guard let media = source.media else { return String(localized: "Source") }
        return String(localized: "Source") + " · " + Self.shortName(URL(fileURLWithPath: media.path).lastPathComponent)
    }

    /// Long camera file names keep their start and end, so the switch stays one compact row.
    static func shortName(_ name: String, limit: Int = 28) -> String {
        guard name.count > limit else { return name }
        let half = (limit - 1) / 2
        return String(name.prefix(half)) + "…" + String(name.suffix(limit - 1 - half))
    }

    private func segment(
        _ title: String, systemImage: String, active: Bool, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(active ? Color.white : Color.secondary)
                .background(active ? tint.opacity(0.85) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Esc closes the source viewer only while it is shown, so it never steals Esc from the timeline.
private struct EscapeReturnsToTimeline: ViewModifier {
    let document: ProjectDocument
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.shortcut(.sourceClose) } else { content }
    }
}
