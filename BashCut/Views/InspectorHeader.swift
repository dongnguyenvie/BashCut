import BashCutDocument
import BashCutProject
import SwiftUI

extension InspectorItemKind {
    var title: String {
        switch self {
        case .clip: String(localized: "Clip")
        case .graphic: String(localized: "Graphic")
        case .text: String(localized: "Text")
        case .caption: String(localized: "Caption")
        case .audio: String(localized: "Audio")
        case .adjustment: String(localized: "Adjustment")
        }
    }
}

/// The Inspector's header for one item: kind colour bar, name, "Graphic · V2 Graphics" and the range as timecodes
/// with the length. The ID is not shown; the context menu copies it.
struct InspectorHeader: View {
    let item: Item
    let kind: InspectorItemKind
    let track: Track?
    let media: Media?
    let project: Project

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(barColor).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).lineLimit(2).textSelection(.enabled)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(range).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contextMenu {
            Button("Copy ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.id, forType: .string)
            }
        }
    }

    private var barColor: Color {
        guard let track else { return .teal }
        return Color(nsColor: ClipStyle.color(track: track, item: item, media: media))
    }

    /// The text, the media's file name, the adjustment's look; never the ID.
    private var name: String {
        if kind == .adjustment { return String(localized: String.LocalizationValue(item.adjustmentTitle(in: project))) }
        if !item.text.isEmpty { return item.text.split(separator: "\n").first.map(String.init) ?? item.text }
        return media?.fileName ?? kind.title
    }

    private var subtitle: String {
        guard let track else { return kind.title }
        let label = project.trackLabel(track.id).map { $0 + " " } ?? ""
        return kind.title + " · " + label + track.name
    }

    private var range: String {
        let fps = project.fps
        return Timecode.string(item.at, fps: fps) + " – " + Timecode.string(item.end, fps: fps)
            + " · " + Timecode.duration(item.duration, fps: fps)
    }
}
