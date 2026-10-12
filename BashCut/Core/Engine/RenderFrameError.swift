import Foundation

/// The timeline item a video layer shows, kept so a frame that cannot be read names the item, its track, its media
/// and the source frame instead of only "code 2".
public struct LayerSource: Sendable, Equatable {
    public var itemID: String
    public var trackID: String
    public var trackName: String
    public var mediaID: String
    public var mediaPath: String
    /// The item's first timeline frame and first source frame.
    public var at: Int
    public var sourceIn: Int
    public var speed: Double
    /// Set when the layer shows one source frame the whole time (freeze frame, transition tail, still image).
    public var heldFrame: Int?
    public var projectFPS: Double
    public var mediaFPS: Double

    public init(
        itemID: String, trackID: String, trackName: String, mediaID: String, mediaPath: String, at: Int, sourceIn: Int,
        speed: Double = 1, heldFrame: Int? = nil, projectFPS: Double, mediaFPS: Double
    ) {
        self.itemID = itemID
        self.trackID = trackID
        self.trackName = trackName
        self.mediaID = mediaID
        self.mediaPath = mediaPath
        self.at = at
        self.sourceIn = sourceIn
        self.speed = speed
        self.heldFrame = heldFrame
        self.projectFPS = projectFPS
        self.mediaFPS = mediaFPS
    }

    /// The source frame shown at timeline `frame`: the picture at the middle of that frame, as the composition samples
    /// it (a speed curve is not followed: the plain speed is used).
    public func sourceFrame(at frame: Int) -> Int {
        if let heldFrame { return heldFrame }
        guard projectFPS > 0 else { return sourceIn }
        let seconds = (Double(frame - at) + 0.5) / projectFPS * speed
        return sourceIn + Int((seconds * mediaFPS).rounded(.down))
    }
}

/// A frame the compositor could not render: which timeline frame, and the layer's item and source frame if known.
public struct RenderFrameError: LocalizedError, Sendable, Equatable {
    public var frame: Int
    public var reason: String
    public var source: LayerSource?

    public init(frame: Int, reason: String, source: LayerSource? = nil) {
        self.frame = frame
        self.reason = reason
        self.source = source
    }

    public var errorDescription: String? {
        var text = "Render failed at project frame \(frame): \(reason)"
        if let source {
            text += " (item \(source.itemID) on track \(source.trackID)"
            if !source.trackName.isEmpty, source.trackName != source.trackID { text += " \"\(source.trackName)\"" }
            text += ", media \(source.mediaID) \(source.mediaPath) source frame \(source.sourceFrame(at: frame)))"
        }
        return text
    }

    /// The same facts as fields, for job status and plugin events.
    public var fields: [String: Any] {
        var fields: [String: Any] = ["frame": frame, "reason": reason]
        if let source {
            fields["itemID"] = source.itemID
            fields["trackID"] = source.trackID
            fields["mediaID"] = source.mediaID
            fields["mediaPath"] = source.mediaPath
            fields["sourceFrame"] = source.sourceFrame(at: frame)
        }
        return fields
    }

    /// The user info of the NSError the compositor finishes a request with; AVFoundation wraps that error, so
    /// `RenderFailures` keeps the typed one for the exporter.
    var userInfo: [String: Any] {
        var info = fields
        info[NSLocalizedDescriptionKey] = errorDescription
        return info
    }
}

/// The first frames a composition failed to render; shared by all of one build's instructions, read by the exporter
/// and preview when AVFoundation reports only a generic failure.
public final class RenderFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [RenderFrameError] = []

    public init() {}

    func record(_ error: RenderFrameError) {
        lock.lock()
        defer { lock.unlock() }
        if recorded.count < 8 { recorded.append(error) }
    }

    public var first: RenderFrameError? {
        lock.lock()
        defer { lock.unlock() }
        return recorded.first
    }

    public var all: [RenderFrameError] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
