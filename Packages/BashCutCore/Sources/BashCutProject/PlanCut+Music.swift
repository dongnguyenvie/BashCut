import Foundation

extension PlanCut {
    /// The music bed (#630): one fixed level by default, `underVoiceDb` under the measured voice (plan apply measures
    /// it; until then, and without a voice, `fallbackVolumeDb`); ducking only when asked (`duck` or `duckDb`), and then
    /// gaps between lines shorter than `duckMinGapSeconds` keep the music down.
    public struct Music: Sendable {
        public static let defaultUnderVoiceDb = 16.0
        public static let fallbackVolumeDb = -20.0
        public static let defaultDuckDb = -14.0

        public var media: String
        public var from: Double
        /// The music clip's level; set, plan apply keeps it instead of measuring.
        public var volumeDb: Double?
        /// The music layer's level under speech (its ducking), in dB.
        public var duckDb: Double?
        /// Ducking on or off; unset, `duckDb` turns it on.
        public var duck: Bool?
        public var duckMinGapSeconds: Double?
        /// How far under the voice's integrated loudness the bed sits, in dB.
        public var underVoiceDb: Double?

        public init(
            media: String, from: Double = 0, volumeDb: Double? = nil, duckDb: Double? = nil, duck: Bool? = nil,
            duckMinGapSeconds: Double? = nil, underVoiceDb: Double? = nil
        ) {
            self.media = media
            self.from = from
            self.volumeDb = volumeDb
            self.duckDb = duckDb
            self.duck = duck
            self.duckMinGapSeconds = duckMinGapSeconds
            self.underVoiceDb = underVoiceDb
        }

        public var ducks: Bool { duck ?? (duckDb != nil) }
        /// Whether plan apply sets the level from the measured voice.
        public var measuresLevel: Bool { volumeDb == nil && !ducks }

        /// A `plan.cut` music row.
        init(_ row: [String: JSONValue]) throws {
            guard let media = row["media"]?.string else { throw ProjectError.invalid("music: give media") }
            let duck = row["duckDb"]?.double
            if let duck, !(-60...0).contains(duck) { throw ProjectError.invalid("music.duckDb: -60…0") }
            let gap = row["duckMinGapSeconds"]?.double
            if let gap, !(0...30).contains(gap) { throw ProjectError.invalid("music.duckMinGapSeconds: 0…30") }
            let under = row["underVoiceDb"]?.double
            if let under, !(0...40).contains(under) { throw ProjectError.invalid("music.underVoiceDb: 0…40") }
            if let value = row["duck"], value != .null, value.bool == nil {
                throw ProjectError.invalid("music.duck: true or false")
            }
            self.init(
                media: media, from: max(0, row["from"]?.double ?? 0), volumeDb: row["volumeDb"]?.double, duckDb: duck,
                duck: row["duck"]?.bool, duckMinGapSeconds: gap, underVoiceDb: under)
        }
    }
}
