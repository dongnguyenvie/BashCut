import BashCutDocument
import SwiftUI

/// The viewer over a placeholder (#534): a neutral card with its label where the picture would be black, while a
/// graphic, captions or media are being made at the playhead.
struct ViewerPlaceholderCard: View {
    let document: ProjectDocument

    var body: some View {
        let playhead = document.playhead
        if let placeholder = document.activity.placeholders.items.first(where: { placeholder in
            placeholder.target.kind != .voiceover && placeholder.target.frames?.contains(playhead) == true
                && placeholder.onTimeline
        }) {
            VStack(spacing: 6) {
                if placeholder.failed {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(placeholder.title).font(.caption.bold())
                if !placeholder.target.label.isEmpty {
                    Text(placeholder.target.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15).opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                (placeholder.failed ? Color.orange : Color.cyan).opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .allowsHitTesting(false)
        }
    }
}

/// A media tile's badge while it converts, makes a proxy or is transcribed (#534).
struct MediaWorkBadge: View {
    let document: ProjectDocument
    let mediaID: String

    var body: some View {
        if let placeholder = document.activity.placeholders.placeholder(forMedia: mediaID) {
            VStack(alignment: .leading, spacing: 3) {
                Spacer()
                Text(placeholder.title).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                if let value = placeholder.progress, !placeholder.failed { ProgressView(value: value).controlSize(.mini) }
                if placeholder.failed {
                    let placeholders = document.activity.placeholders
                    HStack(spacing: 6) {
                        if placeholder.canRetry { Button("Retry") { placeholders.retry(placeholder.id) } }
                        Button("Remove") { placeholders.remove(placeholder.id) }
                    }.font(.system(size: 9)).help(placeholder.error ?? "")
                }
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.45))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(
                (placeholder.failed ? Color.orange : Color.cyan).opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .allowsHitTesting(placeholder.failed)
        }
    }
}

/// Library tiles for blocks that have no media yet and no place on the timeline (a graphic rendering, a voiceover
/// take being spoken), with Retry and Remove once failed (#534).
struct PlaceholderTiles: View {
    let document: ProjectDocument

    var body: some View {
        let placeholders = document.activity.placeholders
        ForEach(placeholders.items.filter { !$0.onTimeline && $0.target.mediaIDs.isEmpty }) { placeholder in
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(
                        (placeholder.failed ? Color.orange : Color.cyan).opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .overlay {
                        if placeholder.failed {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        } else if let value = placeholder.progress {
                            ProgressView(value: value).padding(.horizontal, 12)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .frame(height: 70)
                Text(placeholder.target.label.isEmpty ? placeholder.title : placeholder.target.label).font(.caption2).lineLimit(1)
                Text(placeholder.title).font(.system(size: 9)).foregroundStyle(placeholder.failed ? .orange : .secondary).lineLimit(1)
                    .help(placeholder.error ?? "")
                HStack(spacing: 6) {
                    if placeholder.failed, placeholder.canRetry { Button("Retry") { placeholders.retry(placeholder.id) } }
                    Button(placeholder.failed ? "Remove" : "Cancel") { placeholders.remove(placeholder.id) }
                }.font(.caption2)
            }
        }
    }
}
