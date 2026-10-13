import BashCutPlugin
import SwiftUI

/// Plugin regions on the viewer (#407): rectangles in 0–1 of the picture, each shown while the playhead is in its
/// frames. The playhead is read only when a region has frames, and the drawing redraws only when the set shown
/// changes, so playback with overlays costs a filter of the regions per frame.
struct PluginViewerOverlays: View {
    let document: ProjectDocument

    /// The regions; reading the revision makes the view follow overlay changes.
    private var regions: [PluginOverlayIndex.Entry] {
        _ = document.ui.pluginOverlayRevision
        return document.ui.pluginOverlays.regions
    }

    var body: some View {
        let regions = regions
        if !regions.isEmpty {
            let timed = regions.contains { $0.overlay.start != nil || $0.overlay.end != nil }
            let shown = timed ? document.ui.pluginOverlays.regions(at: document.playhead) : regions
            PluginRegionsView(
                regions: shown.map(\.overlay),
                aspect: Double(document.project.width) / Double(max(1, document.project.height))
            ).equatable().allowsHitTesting(false)
        }
    }
}

private struct PluginRegionsView: View, Equatable {
    let regions: [PluginOverlay]
    let aspect: Double

    var body: some View {
        GeometryReader { geo in
            let height = min(geo.size.height, geo.size.width / aspect)
            let width = height * aspect
            let origin = CGPoint(x: (geo.size.width - width) / 2, y: (geo.size.height - height) / 2)
            ForEach(regions) { region in
                if let rect = region.rect {
                    let color = Color(nsColor: TimelineCanvas.overlayColor(region.color))
                    let frame = CGRect(
                        x: origin.x + rect.x * width, y: origin.y + rect.y * height, width: rect.width * width,
                        height: rect.height * height)
                    ZStack(alignment: .topLeading) {
                        if region.style == "fill" {
                            Rectangle().fill(color.opacity(0.22))
                        } else {
                            Rectangle().strokeBorder(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                        }
                        if let label = region.label, !label.isEmpty {
                            Text(verbatim: label).font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(color.opacity(0.75), in: RoundedRectangle(cornerRadius: 3)).padding(3)
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
    }
}
