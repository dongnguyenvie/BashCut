import BashCutDocument
import SwiftUI

/// The left rail (P1-3): the eight asset panels, a divider, Tools, and More for plugin panels.
extension EditorView {
    var rail: some View {
        let compact = windowHeight < EditorLayout.railLabelsMinHeight
        return VStack(spacing: 4) {
            ForEach(LibraryTab.assets) { tab in railTab(tab, compact: compact) }
            Divider().frame(width: 36).padding(.vertical, 2)
            railTab(.tools, compact: compact)
            railMore(compact: compact)
            Spacer()
        }.padding(.top, 8)
    }

    private func railTab(_ tab: LibraryTab, compact: Bool) -> some View {
        let selected = libraryTabSelected(tab)
        return Button {
            // The open panel's tab collapses the panel; any other tab shows it.
            if selected, document.ui.showLibraryPanel {
                document.run(.toggleLibraryPanel)
            } else {
                document.showLibraryTab(tab)
            }
        } label: {
            railTile(icon: tab.icon, label: LocalizedStringKey(tab.rawValue), selected: selected, compact: compact)
        }
        .buttonStyle(.plain).foregroundStyle(selected ? .cyan : .secondary)
        .help(Text(LocalizedStringKey(tab.rawValue)) + Text(verbatim: tab.keyHint.map { " (\($0))" } ?? ""))
    }

    /// One rail tile: icon over label, or the icon alone in a short window.
    func railTile(icon: String, label: LocalizedStringKey, selected: Bool, compact: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 16))
            if !compact { Text(label).font(.system(size: 8)) }
        }
        .frame(width: 48, height: compact ? 32 : 42)
        .background(selected ? Color.cyan.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // Plain buttons only hit-test drawn pixels; make the whole tile clickable.
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(Text(label))
    }
}

extension LibraryTab {
    /// The View menu key of the panel: ⌘1…⌘8 for the asset panels, ⌘T for Tools.
    var keyEquivalent: String? {
        if self == .tools { return "t" }
        return Self.assets.firstIndex(of: self).map { String($0 + 1) }
    }

    /// The key as shown in a tooltip.
    var keyHint: String? { keyEquivalent.map { "⌘" + $0.uppercased() } }
}
