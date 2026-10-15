import BashCutEngine
import BashCutProject
import SwiftUI

/// The Filters panel's look previews (P2-B3): the viewer's frame at the playhead, small, and each look's grade of it,
/// rendered when a tile shows and kept until the frame changes. A playhead that moved a few frames or a timeline that
/// changed takes a new frame (and drops every graded still); playback takes none until it stops.
@MainActor @Observable
final class LookPreviews {
    /// The picture the looks grade, and what it is: "frame:revision", or "sample" with no timeline picture.
    private(set) var base: CGImage?
    private(set) var baseKey = ""
    @ObservationIgnored private var baseFrame: Int?
    @ObservationIgnored private var baseRevision: Int?
    @ObservationIgnored private var graded: [String: CGImage] = [:]

    /// How far the playhead moves before the looks are drawn again on the new frame.
    static let meaningfulFrames = 6
    /// The longest side of the frame the looks grade, in pixels.
    static let side = 320

    /// What `refresh` waits on: the playhead and the timeline, none of it while playing.
    static func trigger(_ document: ProjectDocument) -> String {
        document.preview.isPlaying ? "playing" : "\(document.playhead):\(document.project.revision)"
    }

    /// Whether the frame at `frame` of `revision` needs a new base.
    func needsBase(frame: Int, revision: Int) -> Bool {
        guard base != nil, let baseFrame, let baseRevision else { return true }
        return revision != baseRevision || abs(frame - baseFrame) >= Self.meaningfulFrames
    }

    /// Takes the viewer's frame at the playhead when it changed meaningfully; the sample still with no timeline.
    func refresh(_ document: ProjectDocument) async {
        let frame = document.playhead, revision = document.project.revision
        guard needsBase(frame: frame, revision: revision) else { return }
        let image = document.project.duration > 0
            ? try? await document.timelineImages([min(frame, document.project.duration - 1)], maximumSide: Self.side)
                .values.first
            : nil
        guard !Task.isCancelled else { return }
        if let image {
            setBase(image, key: "\(frame):\(revision)", frame: frame, revision: revision)
        } else if base == nil || baseKey != "sample" {
            let sample = await Task.detached { TransitionPreview.samples()?.incoming }.value
            setBase(sample, key: "sample", frame: frame, revision: revision)
        }
    }

    func setBase(_ image: CGImage?, key: String, frame: Int?, revision: Int?) {
        base = image
        baseKey = key
        baseFrame = frame
        baseRevision = revision
        graded = [:]
    }

    /// The base graded by `color` and the LUT at `lut`; nil when there is no base or it cannot be drawn.
    func image(color: [String: JSONValue], lut: URL?) async -> CGImage? {
        guard let base else { return nil }
        let key = Self.key(base: baseKey, color: color, lut: lut)
        if let hit = graded[key] { return hit }
        let made = await Task.detached(priority: .userInitiated) {
            try? LookPreview.render(base: base, color: color, lut: lut)
        }.value
        // The frame may have changed while this one was drawn: keep only what still matches.
        if let made, key == Self.key(base: baseKey, color: color, lut: lut) { graded[key] = made }
        return made
    }

    var count: Int { graded.count }

    static func key(base: String, color: [String: JSONValue], lut: URL?) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let grade = (try? encoder.encode(JSONValue.object(color))).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        return "\(base)|\(grade)|\(lut?.path ?? "")"
    }
}

/// A look's tile picture: the viewer's frame with the look applied; the icon until it is drawn.
struct LookPreviewPicture: View {
    let previews: LookPreviews?
    let color: [String: JSONValue]
    let lut: URL?
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            } else {
                LibraryTileFallback(symbol: LibraryKind.look.tileSymbol)
            }
        }
        .task(id: "\(previews?.baseKey ?? ""):\(LookPreviews.key(base: "", color: color, lut: lut))") {
            guard let previews else { return }
            let made = await previews.image(color: color, lut: lut)
            if !Task.isCancelled { image = made }
        }
        .accessibilityHidden(true)
    }
}

extension LookPreviewPicture {
    /// A library look: its grade and, when it keeps one, its LUT file.
    init(document: ProjectDocument, previews: LookPreviews?, item: LibraryItem) {
        let stack = try? FilterStack(params: item.params)
        self.init(previews: previews, color: stack?.color ?? [:], lut: document.libraryCatalog.fileURL(of: item))
    }

    /// One of the project's 3D LUTs at full strength.
    init(document: ProjectDocument, previews: LookPreviews?, lut: ColorLUT) {
        self.init(
            previews: previews, color: [:],
            lut: document.fileURL?.deletingLastPathComponent().appendingPathComponent(lut.path))
    }
}
