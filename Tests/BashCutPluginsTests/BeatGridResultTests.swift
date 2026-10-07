import BashCutProject
import Foundation
import Testing

@testable import BashCutPlugins

/// Grid v2 fields from an `audio.beats` provider (P0-B10): kept when they check out, dropped otherwise.
struct BeatGridResultTests {
    @Test("Valid grid fields are kept, invalid ones dropped, and a beats-only result still works")
    func gridFields() {
        let beats = [0.5, 1.0, 1.5, 2.0]
        let grid = BeatDetectionCapability.grid([
            "strengths": .array([.number(1), .number(0.4), .number(0.5), .number(0.3)]),
            "downbeats": .array([.number(0.5), .number(2.0)]), "beatsPerBar": .integer(4),
            "phaseScores": .array([.number(1), .number(0.2), .number(0.1), .number(0.3)]), "confidence": .number(0.6),
            "fit": .object(["periodSeconds": .number(0.5), "rmsErrorMs": .number(3)]),
            "alternates": .array([.object(["bpm": .number(60), "relative": .number(0.8)])]),
        ], beats: beats)
        #expect(grid.keys.sorted() == ["alternates", "beatsPerBar", "confidence", "downbeats", "fit", "phaseScores", "strengths"])
        let bad = BeatDetectionCapability.grid([
            "strengths": .array([.number(2)]), "downbeats": .array([.number(0.7)]), "confidence": .number(3),
        ], beats: beats)
        #expect(bad.isEmpty)
        #expect(BeatDetectionCapability.grid([:], beats: beats).isEmpty)
    }
}
