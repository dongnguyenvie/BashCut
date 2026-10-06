import Foundation

/// A loudness measurement of the mixed timeline, from a normalized export of `revision`.
public struct ReviewLoudness: Sendable, Equatable {
    public let revision: Int
    public let integratedLUFS: Double
    public let truePeakDbTP: Double
    public let loudnessRangeLU: Double?

    public init(revision: Int, integratedLUFS: Double, truePeakDbTP: Double, loudnessRangeLU: Double?) {
        self.revision = revision
        self.integratedLUFS = integratedLUFS
        self.truePeakDbTP = truePeakDbTP
        self.loudnessRangeLU = loudnessRangeLU
    }
}

/// The targets measured checks compare against. The defaults fit short-form social video (TikTok, Reels, Shorts,
/// YouTube): -14 LUFS within 2 LU, true peak at most -1 dBTP; the Reelcrew study (#431) found every finished
/// reference within 0.3 LU of -14.
public struct ReviewTargets: Sendable, Equatable {
    /// Integrated loudness target; nil skips the loudness checks.
    public var integratedLUFS: Double?
    public var toleranceLU: Double
    public var maxTruePeakDbTP: Double
    /// Longest stretch without any audible layer before it counts as dead air.
    public var maxSilenceSeconds: Double
    /// How soon the edit has to hook the viewer: on-screen text or speech within this many seconds.
    public var hookSeconds: Double
    /// The export command a loudness fix suggests (`export.start` arguments), when loudness was not measured.
    public var measureArguments: [String: JSONValue]
    /// Whether to report a picture that was not measured for this revision (with a `review.measure` fix).
    public var measuresPicture: Bool
    /// Pacing: shots shorter or longer than these, and still picture longer than `maxStillSeconds`. Nil uses the
    /// orientation's default; a project's `review` object (`minShotSeconds`, `maxShotSeconds`, `maxStillSeconds`)
    /// overrides both, so a recipe can set its own range.
    public var minShotSeconds: Double?
    public var maxShotSeconds: Double?
    public var maxStillSeconds: Double?

    public init(
        integratedLUFS: Double? = nil, toleranceLU: Double = 2, maxTruePeakDbTP: Double = -1,
        maxSilenceSeconds: Double = 1.5, hookSeconds: Double = 3, measureArguments: [String: JSONValue] = [:],
        measuresPicture: Bool = false, minShotSeconds: Double? = nil, maxShotSeconds: Double? = nil,
        maxStillSeconds: Double? = nil
    ) {
        self.integratedLUFS = integratedLUFS
        self.toleranceLU = toleranceLU
        self.maxTruePeakDbTP = maxTruePeakDbTP
        self.maxSilenceSeconds = maxSilenceSeconds
        self.hookSeconds = hookSeconds
        self.measureArguments = measureArguments
        self.measuresPicture = measuresPicture
        self.minShotSeconds = minShotSeconds
        self.maxShotSeconds = maxShotSeconds
        self.maxStillSeconds = maxStillSeconds
    }

    /// The pacing for `project`: its `review` overrides, then these targets, then the defaults. Vertical short-form
    /// changes picture more often (Reelcrew promos: 4–4.5 s shots, #432) than landscape.
    public func pacing(for project: Project) -> (minShot: Double, maxShot: Double, maxStill: Double) {
        let overrides = project["review"]?.object ?? [:]
        let vertical = project.height > project.width
        return (
            overrides["minShotSeconds"]?.double ?? minShotSeconds ?? 0.4,
            overrides["maxShotSeconds"]?.double ?? maxShotSeconds ?? (vertical ? 8 : 15),
            overrides["maxStillSeconds"]?.double ?? maxStillSeconds ?? (vertical ? 4 : 8))
    }
}

/// What the review knows beyond the project: installed fonts, the text presets' defaults, the last loudness and
/// picture measurements and the targets.
public struct ReviewContext {
    /// Whether a `textStyle.font` name draws on this Mac (the app passes `ProjectFonts.isAvailable`).
    public var fontAvailable: (String) -> Bool
    /// `size` (fraction of the short side) and `positionY` (baseline from the bottom) of a text preset, for items
    /// that do not set them.
    public var textDefaults: (String?) -> (size: Double, positionY: Double)
    public var loudness: ReviewLoudness?
    /// The last picture measurement (`review.measure`); checks use it only for the project's revision.
    public var picture: ReviewPicture?
    public var targets: ReviewTargets

    public init(
        fontAvailable: @escaping (String) -> Bool = { _ in true },
        textDefaults: @escaping (String?) -> (size: Double, positionY: Double) = { _ in (0.055, 0.18) },
        loudness: ReviewLoudness? = nil, picture: ReviewPicture? = nil, targets: ReviewTargets = ReviewTargets()
    ) {
        self.fontAvailable = fontAvailable
        self.textDefaults = textDefaults
        self.loudness = loudness
        self.picture = picture
        self.targets = targets
    }
}
