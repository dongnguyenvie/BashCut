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

    public init(
        integratedLUFS: Double? = nil, toleranceLU: Double = 2, maxTruePeakDbTP: Double = -1,
        maxSilenceSeconds: Double = 1.5, hookSeconds: Double = 3, measureArguments: [String: JSONValue] = [:]
    ) {
        self.integratedLUFS = integratedLUFS
        self.toleranceLU = toleranceLU
        self.maxTruePeakDbTP = maxTruePeakDbTP
        self.maxSilenceSeconds = maxSilenceSeconds
        self.hookSeconds = hookSeconds
        self.measureArguments = measureArguments
    }
}

/// What the review knows beyond the project: installed fonts, the text presets' defaults, the last loudness
/// measurement and the targets.
public struct ReviewContext {
    /// Whether a `textStyle.font` name draws on this Mac (the app passes `ProjectFonts.isAvailable`).
    public var fontAvailable: (String) -> Bool
    /// `size` (fraction of the short side) and `positionY` (baseline from the bottom) of a text preset, for items
    /// that do not set them.
    public var textDefaults: (String?) -> (size: Double, positionY: Double)
    public var loudness: ReviewLoudness?
    public var targets: ReviewTargets

    public init(
        fontAvailable: @escaping (String) -> Bool = { _ in true },
        textDefaults: @escaping (String?) -> (size: Double, positionY: Double) = { _ in (0.055, 0.18) },
        loudness: ReviewLoudness? = nil, targets: ReviewTargets = ReviewTargets()
    ) {
        self.fontAvailable = fontAvailable
        self.textDefaults = textDefaults
        self.loudness = loudness
        self.targets = targets
    }
}
