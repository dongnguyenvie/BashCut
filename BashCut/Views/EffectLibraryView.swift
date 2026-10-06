import BashCutDocument
import BashCutProject
import SwiftUI

/// The Effects panel (#76): effect presets with their previews; a click applies one to the selected clip, Apply with…
/// changes its parameters or applies it to part of the clip.
struct EffectLibraryView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibraryItemsSection(
                document: document, kinds: [.effectPreset], saveKinds: [.effectPreset],
                itemActions: { item in
                    document.selected == nil ? [] : [LibraryPanelAction(title: "Apply with…") { document.beginEffectApply(item) }]
                },
                tile: tile)
            Text("Select a clip, then click an effect. Apply with… changes its settings or applies it to part of the clip.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: Bindable(document.ui).effectApply) { request in
            EffectApplySheet(
                document: document,
                request: Binding(get: { document.ui.effectApply ?? request }, set: { document.ui.effectApply = $0 }))
        }
    }

    private func tile(_ item: LibraryItem) -> some View {
        HStack(spacing: 6) {
            Button { document.applyFromLibrary(item) } label: {
                HStack(spacing: 6) {
                    if let preview = document.libraryCatalog.previewURL(of: item) {
                        LibraryImage(url: preview).frame(width: 36, height: 24)
                    }
                    LibraryView.title(item).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button("Apply with…", systemImage: "slider.horizontal.3") { document.beginEffectApply(item) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help("Apply with other settings, or to part of the clip")
        }
        .disabled(document.selected == nil)
    }
}
