import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutProject
import SwiftUI

/// A small determinate ring for the Export button while an export runs.
struct ExportProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.3), lineWidth: 2)
            Circle().trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
        .animation(.linear(duration: 0.2), value: progress)
    }
}

/// The Export button's popover while an export runs: what is being written, its step and progress,
/// how many exports wait, and Cancel. `ui.open export-progress` and `ui.respond` drive it too.
struct ExportProgressPopover: View {
    let document: ProjectDocument

    var body: some View {
        let exports = document.exports
        VStack(alignment: .leading, spacing: 10) {
            Text("Exporting").font(.headline)
            if let job = exports.queue.activeJob, let request = exports.queue.request(for: job) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.output.lastPathComponent).font(.callout.bold())
                        .lineLimit(1).truncationMode(.middle)
                    Text(request.preset.title).font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: exports.progress)
                HStack {
                    if let step = exports.queue.detail, step != request.output.lastPathComponent {
                        Text(step).lineLimit(1)
                    }
                    Spacer()
                    Text(exports.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            if exports.queue.queuedCount > 0 {
                Text(String(format: String(localized: "%d more exports queued"), exports.queue.queuedCount))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel Export") { document.run(.cancelExport) }.action(.cancelExport, in: document)
                Spacer()
                Button("New Export…") {
                    document.ui.showExportProgress = false
                    document.run(.showExport)
                }
            }
        }
        .padding(14).frame(width: 300)
    }
}

/// The toast at the bottom right when an export starts, is queued, finishes, fails or is cancelled, so an
/// export started from the Export sheet or by an agent is noticed.
struct ExportToast: View {
    let notice: ExportNotice
    let document: ProjectDocument

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).imageScale(.large)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.bold()).lineLimit(1).truncationMode(.middle)
                detail
            }
            .frame(minWidth: 180, maxWidth: 280, alignment: .leading)
            buttons
            Button { document.run(.dismissExportNotice) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Dismiss")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.35)))
        .shadow(radius: 8)
        .padding(14)
    }

    private var running: Bool { notice.kind == .started && document.exports.isRunning }

    private var icon: String {
        switch notice.kind {
        case .started, .queued: "square.and.arrow.up"
        case .finished: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .started, .queued: .cyan
        case .finished: .green
        case .cancelled: .secondary
        case .failed: .orange
        }
    }

    private var title: String {
        switch notice.kind {
        case .started: String(format: String(localized: "Exporting %@…"), notice.name)
        case .queued: String(format: String(localized: "Export queued: %@"), notice.name)
        case .finished: String(format: String(localized: "Exported %@"), notice.name)
        case .cancelled: String(format: String(localized: "Export cancelled: %@"), notice.name)
        case .failed: String(format: String(localized: "Export failed: %@"), notice.name)
        }
    }

    @ViewBuilder private var detail: some View {
        switch notice.kind {
        case .started where running:
            HStack(spacing: 6) {
                ProgressView(value: document.exports.progress)
                Text(document.exports.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption).monospacedDigit()
            }
        case .failed(let reason):
            Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        case .queued:
            Text("Starts after the current export").font(.caption).foregroundStyle(.secondary)
        default:
            if notice.author != .user {
                Text(String(format: String(localized: "Started by %@"), notice.author.rawValue.capitalized))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        switch notice.kind {
        case .started, .queued:
            if document.exports.isRunning { Button("Details") { document.run(.showExportProgress) } }
        case .finished:
            Button("Open") { document.run(.openExportOutput) }.action(.openExportOutput, in: document)
            Button("Reveal") { document.run(.revealExportOutput) }.action(.revealExportOutput, in: document)
        default:
            EmptyView()
        }
    }
}

/// Draws export progress over the app icon in the Dock, for long exports while BashCut is in the background.
@MainActor
enum ExportDockTile {
    private static var bar: NSProgressIndicator?

    /// `progress` in 0…1 shows the bar; nil restores the plain icon.
    static func show(_ progress: Double?) {
        let tile = NSApp.dockTile
        guard let progress else {
            guard bar != nil else { return }
            bar = nil
            tile.contentView = nil
            tile.display()
            return
        }
        if bar == nil {
            let icon = NSImageView(frame: NSRect(origin: .zero, size: tile.size))
            icon.image = NSApp.applicationIconImage
            let indicator = NSProgressIndicator(frame: NSRect(
                x: tile.size.width * 0.1, y: tile.size.height * 0.06,
                width: tile.size.width * 0.8, height: max(12, tile.size.height * 0.12)))
            indicator.style = .bar
            indicator.isIndeterminate = false
            indicator.minValue = 0
            indicator.maxValue = 1
            icon.addSubview(indicator)
            tile.contentView = icon
            bar = indicator
        }
        bar?.doubleValue = progress
        tile.display()
    }
}
