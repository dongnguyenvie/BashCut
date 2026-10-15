import BashCutAutomation
import BashCutDocument
import SwiftUI

/// The strip over the timeline, in four groups: edit (Split, Delete), Add (layers), view toggles with labels
/// (Snap, Sections, Waveforms) and zoom with Fit. Every button's tooltip names its shortcut.
struct TimelineToolbar: View {
    let document: ProjectDocument
    @State private var newSectionLabel = ""

    var body: some View {
        HStack(spacing: 8) {
            edit
            divider
            addMenu
            divider
            view
            Spacer(minLength: 4)
            zoom
        }.font(.caption).controlSize(.small).padding(.horizontal, 8).padding(.vertical, 6).disabled(document.busy)
    }

    private var divider: some View { Divider().frame(height: 16) }

    /// The tooltip: the title and the action's shortcut as the menus draw it, e.g. "Split (⌘B)".
    private func tip(_ title: String, _ action: UIAction) -> String {
        action.shortcut.map { "\(title) (\(MenuCatalog.label($0)))" } ?? title
    }

    private var edit: some View {
        HStack(spacing: 6) {
            Button { document.run(.split) } label: { Label("Split", systemImage: "scissors") }
                .help(tip(String(localized: "Split at the playhead"), .split)).action(.split, in: document)
            Button { document.run(.delete) } label: { Label("Delete", systemImage: "trash") }
                .help(tip(String(localized: "Delete the selected clips"), .delete)).action(.delete, in: document)
        }
    }

    /// Layers: the four kinds to add, then moving or deleting the selected one.
    private var addMenu: some View {
        Menu {
            Button("Video Layer") { document.run(.addVideoLayer) }
            Button("Adjustment Layer") { document.run(.addAdjustmentLayer) }
            Button("Text Layer") { document.run(.addTextLayer) }
            Button("Audio Layer") { document.run(.addAudioLayer) }
            Divider()
            Button("Move selected layer up") { document.run(.layerUp) }.disabled(!document.canPerform(.layerUp))
            Button("Move selected layer down") { document.run(.layerDown) }.disabled(!document.canPerform(.layerDown))
            Button("Delete selected empty layer", role: .destructive) { document.run(.deleteLayer) }
                .disabled(!document.canPerform(.deleteLayer))
        } label: {
            Label("Add", systemImage: "plus")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Add a layer, or move or delete the selected one")
    }

    private var view: some View {
        HStack(spacing: 6) {
            Toggle(isOn: Bindable(document.ui).snapping) { Label("Snap", systemImage: "magnet") }
                .toggleStyle(.button).help(tip(String(localized: "Snap clips to edges and the playhead"), .toggleSnap))
            Button { document.run(.showSections) } label: { Label("Sections", systemImage: "flag") }
                .help(tip(String(localized: "Name the parts of the video"), .showSections))
                .popover(isPresented: Bindable(document.ui).showSections) {
                    SectionManagerView(
                        document: document, newLabel: $newSectionLabel,
                        done: { document.ui.showSections = false })
                }
            Button { document.run(.refreshWaveforms) } label: { Label("Waveforms", systemImage: "waveform") }
                .help(tip(String(localized: "Refresh waveforms"), .refreshWaveforms)).action(.refreshWaveforms, in: document)
            if document.waveforms.loading { ProgressView().controlSize(.mini) }
            if !document.waveforms.errors.isEmpty {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    .help(document.waveforms.errors.values.sorted().joined(separator: "\n"))
            }
        }
    }

    private var zoom: some View {
        HStack(spacing: 6) {
            Button { document.run(.zoomOut) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.borderless).help(tip(String(localized: "Zoom timeline out"), .zoomOut))
                .action(.zoomOut, in: document)
            Slider(
                value: Binding(
                    get: { document.ui.timelineZoomSliderValue },
                    set: { document.ui.setTimelineZoomSliderValue($0, around: document.playhead) }),
                in: EditorUIState.timelineZoomSliderRange
            ).frame(width: 100).help("Timeline zoom; pinch or ⌘-scroll on the timeline")
            Button { document.run(.zoomIn) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.borderless).help(tip(String(localized: "Zoom timeline in"), .zoomIn))
                .action(.zoomIn, in: document)
            Button { document.run(.zoomFit) } label: { Label("Fit", systemImage: "arrow.left.and.right.square") }
                .help(tip(String(localized: "Zoom timeline to fit"), .zoomFit)).disabled(!document.canPerform(.zoomFit))
        }
    }
}
