import BashCutProject

/// Which empty layers the timeline folds into one row (P1-11): a layer with no clips takes a whole row, so a
/// project with a few unused layers would push the used ones out of view. The main layer and the selected layer
/// are never folded.
public enum TimelineTrackFolding {
    /// The IDs of the layers without clips, in track order, except the main layer.
    public static func emptyTrackIDs(in tracks: [Track]) -> [String] {
        tracks.filter { $0.items.isEmpty && $0.role != TrackRole.main }.map(\.id)
    }

    /// The IDs to leave out of the timeline's rows: the empty layers, unless the user expanded them or `keep`
    /// (the selected layer) names them.
    public static func foldedTrackIDs(in tracks: [Track], expanded: Bool, keep: String? = nil) -> Set<String> {
        guard !expanded else { return [] }
        return Set(emptyTrackIDs(in: tracks)).subtracting(keep.map { [$0] } ?? [])
    }
}
