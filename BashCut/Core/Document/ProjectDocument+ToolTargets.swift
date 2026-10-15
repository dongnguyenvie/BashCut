import BashCutProject
import Foundation

/// What the tool cards run on (P1-4): the selected clip's media and the part of it the clip plays.
extension ProjectDocument {
    /// The media of the selected clip and the range of it the clip plays, in source seconds; nil when no clip with
    /// media is selected.
    var selectedClipSource: (media: Media, range: ClosedRange<Double>)? {
        guard let item = selected, let id = item.mediaID, let media = project.media.first(where: { $0.id == id }) else {
            return nil
        }
        let start = Double(item.sourceIn) / media.fps.value
        let end = start + item.sourceSeconds(afterFrames: item.duration, fps: project.fps)
        guard end > start else { return nil }
        return (media, start...end)
    }
}
