import Foundation

/// A loudness measurement of the mixed timeline, from a normalized export of `revision`, with the target that export
/// was normalized to (its preset's, P0-K2).
public struct ReviewLoudness: Sendable, Equatable {
    public let revision: Int
    public let integratedLUFS: Double
    public let truePeakDbTP: Double
    public let loudnessRangeLU: Double?
    public let targetLUFS: Double?
    public let maxTruePeakDbTP: Double?
    public let preset: String?

    public init(
        revision: Int, integratedLUFS: Double, truePeakDbTP: Double, loudnessRangeLU: Double?, targetLUFS: Double? = nil,
        maxTruePeakDbTP: Double? = nil, preset: String? = nil
    ) {
        self.revision = revision
        self.integratedLUFS = integratedLUFS
        self.truePeakDbTP = truePeakDbTP
        self.loudnessRangeLU = loudnessRangeLU
        self.targetLUFS = targetLUFS
        self.maxTruePeakDbTP = maxTruePeakDbTP
        self.preset = preset
    }
}

/// Issues plugin `review.check` providers reported for `revision` (#451), merged into the review of that revision.
public struct ReviewPluginIssues: Sendable {
    public let revision: Int
    public let issues: [ReviewIssue]

    public init(revision: Int, issues: [ReviewIssue]) {
        self.revision = revision
        self.issues = issues
    }
}

/// What the review checks against beyond the project's own `review` profile: the platforms of the project's outputs
/// (#441, #469) and how to measure what is not measured yet. Editorial limits are not here: they are the project's
/// (`ReviewProfile`, #466).
public struct ReviewTargets: Sendable, Equatable {
    /// The export a loudness fix suggests (`export.start` arguments), when loudness was not measured.
    public var measureArguments: [String: JSONValue]
    /// Whether to report a picture that was not measured for this revision (with a `review.measure` fix).
    public var measuresPicture: Bool
    /// The platforms of the project's outputs, in `output.presets` order.
    public var platforms: [OutputPlatform]

    public init(measureArguments: [String: JSONValue] = [:], measuresPicture: Bool = false, platforms: [OutputPlatform] = []) {
        self.measureArguments = measureArguments
        self.measuresPicture = measuresPicture
        self.platforms = platforms
    }

    /// The outputs' platforms of the frame's shape with the project's overrides, as one: the strictest zone of each
    /// side and the shortest length. Nil when no output of that shape is set.
    public func layoutPlatform(for project: Project) -> OutputPlatform? {
        let vertical = project.height > project.width
        var seen = Set<String>()
        let profile = ReviewProfile(project)
        let matching = platforms.filter { $0.vertical == vertical && seen.insert($0.id).inserted }.map(profile.applying)
        guard let first = matching.first else { return nil }
        guard matching.count > 1 else { return first }
        let area = { (path: KeyPath<SafeArea, Double>) in matching.map { $0.safeArea[keyPath: path] }.max() ?? 0 }
        return OutputPlatform(
            id: matching.map(\.id).joined(separator: "+"), title: matching.map(\.title).joined(separator: " and "),
            vertical: vertical, maxSeconds: matching.compactMap(\.maxSeconds).min(),
            targetLUFS: first.targetLUFS, maxTruePeakDbTP: matching.map(\.maxTruePeakDbTP).min() ?? first.maxTruePeakDbTP,
            safeArea: SafeArea(
                top: area(\.top), bottom: area(\.bottom), sideWidth: area(\.sideWidth), sideHeight: area(\.sideHeight),
                margin: area(\.margin)))
    }
}

/// A text item as the renderer lays it out (#465): the fitted font size in pixels, the line count and the bounds of the
/// drawn text and its plates in pixels, with y up from the bottom of the frame.
public struct TextLayout: Sendable, Equatable {
    public let points: Double
    public let lines: Int
    public let minX, maxX, minY, maxY: Double

    public init(points: Double, lines: Int, minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.points = points
        self.lines = lines
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }
}

/// What the review knows beyond the project: installed fonts, the text presets' defaults, the last loudness and
/// picture measurements, plugin check results and the output platforms.
public struct ReviewContext {
    /// Whether a `textStyle.font` name draws on this Mac (the app passes `ProjectFonts.isAvailable`).
    public var fontAvailable: (String) -> Bool
    /// `size` (fraction of the short side) and `positionY` (baseline from the bottom) of a text preset, for items
    /// that do not set them.
    public var textDefaults: (String?) -> (size: Double, positionY: Double)
    /// The rendered layout of a text item on a frame of the given width and height (the app passes `TextRenderer`'s);
    /// nil, or a nil result, falls back to an estimate.
    public var textLayout: ((Item, Double, Double) -> TextLayout?)?
    public var loudness: ReviewLoudness?
    /// The last picture measurement (`review.measure`); checks use it only for the project's revision.
    public var picture: ReviewPicture?
    /// What plugin checks reported on the last `review.measure`; used only for the project's revision.
    public var pluginIssues: ReviewPluginIssues?
    public var targets: ReviewTargets

    public init(
        fontAvailable: @escaping (String) -> Bool = { _ in true },
        textDefaults: @escaping (String?) -> (size: Double, positionY: Double) = { _ in (0.055, 0.18) },
        textLayout: ((Item, Double, Double) -> TextLayout?)? = nil,
        loudness: ReviewLoudness? = nil, picture: ReviewPicture? = nil, pluginIssues: ReviewPluginIssues? = nil,
        targets: ReviewTargets = ReviewTargets()
    ) {
        self.fontAvailable = fontAvailable
        self.textDefaults = textDefaults
        self.textLayout = textLayout
        self.loudness = loudness
        self.picture = picture
        self.pluginIssues = pluginIssues
        self.targets = targets
    }
}
