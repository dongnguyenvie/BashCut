import Foundation

/// How large a clip's source pixels are drawn (P0-B7): the base scale of its fit or fill, its zoom now and at its
/// largest keyframe, the output pixels per source pixel at both (over 1 = upscaled), the largest zoom that stays at or
/// under one output pixel per source pixel (`maxZoomNative`), and how much of the frame the picture covers. Facts
/// for punch-ins and shrunk screen recordings; no limit on what is "too soft".
public enum ReviewScale {
    /// The fit (whole picture inside the frame) or fill (frame covered) scale of a `width × height` picture.
    public static func baseScale(sourceWidth: Double, sourceHeight: Double, canvasWidth: Double, canvasHeight: Double,
                                 fill: Bool) -> Double {
        let horizontal = canvasWidth / abs(sourceWidth), vertical = canvasHeight / abs(sourceHeight)
        return fill ? max(horizontal, vertical) : min(horizontal, vertical)
    }

    /// Facts for a video or image item, from its media's shown size; nil without one.
    public static func json(_ item: Item, media: Media, project: Project) -> JSONValue? {
        guard let width = media.width, let height = media.height, width > 0, height > 0, project.width > 0,
            project.height > 0
        else { return nil }
        let fill = project.fills(item)
        let base = baseScale(
            sourceWidth: Double(width), sourceHeight: Double(height), canvasWidth: Double(project.width),
            canvasHeight: Double(project.height), fill: fill)
        let zoom = item["transform"]?.object["zoom"]?.double ?? 1
        let keyed = item.pictureMotion?.keys["zoom"]?.map(\.value) ?? []
        let largest = max(keyed.max() ?? zoom, keyed.isEmpty ? zoom : 0)
        let shownWidth = Double(width) * base * zoom, shownHeight = Double(height) * base * zoom
        let covered = min(shownWidth, Double(project.width)) * min(shownHeight, Double(project.height))
        let round = { (value: Double) in JSONValue.number((value * 1_000).rounded() / 1_000) }
        return .object([
            "fit": .string(fill ? "fill" : "fit"), "baseScale": round(base), "zoom": round(zoom),
            "maxZoom": round(largest), "pixelRatio": round(base * zoom), "pixelRatioAtMaxZoom": round(base * largest),
            "maxZoomNative": round(1 / base), "sourceWidth": .integer(width), "sourceHeight": .integer(height),
            "shownWidth": round(shownWidth), "shownHeight": round(shownHeight),
            "frameCoverage": round(covered / Double(project.width * project.height)),
        ])
    }

    /// Facts for every video and image item, by item ID.
    public static func all(_ project: Project) -> JSONValue {
        let media = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: JSONValue] = [:]
        for track in project.tracks where track.kind == TrackKind.video {
            for item in track.items {
                if let asset = item.mediaID.flatMap({ media[$0] }), asset.kind != "audio",
                    let facts = json(item, media: asset, project: project)
                {
                    result[item.id] = facts
                }
            }
        }
        return .object(result)
    }
}
