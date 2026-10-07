import Foundation
import Testing

@testable import BashCutProject

/// The measured record per media (P0-A1): cuts after corrections, shots like `review.shots`, statistics, file facts
/// and sound spans read from a record with the reader's limits.
struct MediaAnalysisTests {
    /// 10 s at 30 fps sampled every 15 frames; candidates at 3 s (strong), 6 s (weak) and 8 s (strong). The picture
    /// moves only between 3 and 6 s. Sound: 1 s silence, 2 s at -20 dBFS, 0.2 s gap, 1 s at -20, then a -50 floor.
    func record() -> MediaAnalysis {
        let samples = stride(from: 0, to: 300, by: 15).map { frame in
            let moving = frame > 90 && frame < 180
            return MediaAnalysis.Sample(
                frame: frame, luma: frame < 90 ? 0.2 : 0.6, spread: 0.1, change: frame == 0 ? 1 : (moving ? 0.05 : 0.001),
                peak: moving ? 0.2 : 0.01, sharpness: 0.04, colourfulness: frame < 90 ? 0 : 0.3)
        }
        let picture = MediaAnalysis.Picture(
            fps: 30, interval: 15, frames: 300, samples: samples,
            candidates: [.init(frame: 90, score: 0.4), .init(frame: 180, score: 0.07), .init(frame: 240, score: 0.3)],
            candidateFloor: 0.04)
        let levels = [Double](repeating: MediaAnalysis.silenceDb, count: 10) + [Double](repeating: -20, count: 20)
            + [Double](repeating: -50, count: 2) + [Double](repeating: -20, count: 10) + [Double](repeating: -50, count: 58)
        return MediaAnalysis(
            key: "abc", measuredAt: "2026-10-07T00:00:00Z",
            tech: .init(
                seconds: 10, bytes: 1000,
                video: .init(codec: "avc1", width: 1920, height: 1080, nominalFPS: 30, seconds: 10, frames: 300,
                             minFrameSeconds: 1 / 30.0, maxFrameSeconds: 1 / 15.0, meanFrameSeconds: 1 / 30.0,
                             transfer: "ITU_R_2100_HLG", bitDepth: 10),
                audio: .init(codec: "aac", channels: 2, sampleRate: 48_000, seconds: 9.5)),
            picture: picture, sound: .init(window: 0.1, levels: levels, peakDb: -6, stereoCorrelation: 0.9))
    }

    @Test("Cuts at the default limit become shots with the review.shots fields and statistics")
    func shots() throws {
        let json = record().json().object
        let picture = try #require(json["picture"]?.object)
        let cuts = try #require(picture["cuts"]?.array).map(\.object)
        #expect(cuts.map { $0["frame"] } == [.integer(90), .integer(240)])
        #expect(cuts[0]["score"] == .number(0.4))
        #expect(picture["candidatesBelow"] == .integer(1))
        let shots = try #require(picture["shots"]?.array).map(\.object)
        #expect(shots.map { $0["seconds"] } == [.number(3), .number(5), .number(2)])
        #expect(shots[0]["cutDifference"] == nil)
        #expect(shots[1]["cutDifference"] == .number(0.4))
        // Motion leaves out the sample on the cut, like review.shots: 9 samples inside the middle shot.
        let motion = try #require(shots[1]["motion"]?.object)
        #expect(motion["samples"] == .integer(9))
        #expect(shots[0]["picture"]?.object["colourfulness"] == .number(0))
        let summary = try #require(picture["summary"]?.object)
        #expect(summary["count"] == .integer(3))
        #expect(summary["medianSeconds"] == .number(3))
        #expect(summary["cutsPerMinute"] == .number(12))
        let histogram = try #require(summary["histogram"]?.array).map(\.object)
        #expect(histogram.first { $0["from"] == .number(2) }?["count"] == .integer(2))
        #expect(histogram.first { $0["from"] == .number(4) }?["count"] == .integer(1))
        #expect(histogram.last?["to"] == nil)
        let curve = try #require(summary["cutCurve"]?.array).map(\.object)
        #expect(curve.map { $0["cuts"] } == [.integer(2)])
        // A lower limit takes the weak candidate too.
        let low = record().json(limits: .init(minScore: 0.05)).object["picture"]?.object["cuts"]?.array
        #expect(low?.count == 3)
    }

    @Test("Corrections add and remove cuts by seconds, undo each other and refuse times outside the file")
    func corrections() throws {
        var analysis = record()
        try analysis.correct(add: [5], remove: [8.1])
        #expect(analysis.corrections == .init(add: [150], remove: [243]))
        #expect(analysis.cuts(minScore: 0.1).map(\.frame) == [90, 150])
        #expect(analysis.cuts(minScore: 0.1)[1].score == nil)
        let shots = analysis.json().object["picture"]?.object["shots"]?.array ?? []
        #expect(shots.last?.object["cutAdded"] == .bool(true))
        // Removing the added cut takes it back; adding at the removed candidate restores it.
        try analysis.correct(add: [8], remove: [5])
        #expect(analysis.corrections.isEmpty)
        #expect(analysis.cuts(minScore: 0.1).map(\.frame) == [90, 240])
        #expect(throws: ProjectError.self) { try analysis.correct(add: [12], remove: []) }
        try analysis.correct(add: [1], remove: [], clear: true)
        #expect(analysis.corrections.add == [30])
        let encoded = try JSONEncoder().encode(analysis)
        #expect(try JSONDecoder().decode(MediaAnalysis.self, from: encoded) == analysis)
    }

    @Test("File facts: frame timing spread, transfer kind and track lengths")
    func tech() throws {
        let tech = try #require(record().json().object["tech"]?.object)
        let video = try #require(tech["video"]?.object)
        #expect(video["variableFrameRate"] == .bool(true))
        #expect(video["transferKind"] == .string("hlg"))
        #expect(video["bitDepth"] == .integer(10))
        #expect(tech["audioMinusVideoSeconds"] == .number(-0.5))
        #expect(MediaAnalysis.transferKind("ITU_R_709_2") == "sdr")
        #expect(MediaAnalysis.transferKind("SMPTE_ST_2084_PQ") == "pq")
        #expect(MediaAnalysis.transferKind(nil) == "unknown")
    }

    @Test("Sound: percentiles of non-silent windows, active spans bridged over short gaps, per-second curve")
    func sound() throws {
        let sound = try #require(record().json(curve: true).object["sound"]?.object)
        #expect(sound["floorDb"] == .number(-50))
        #expect(sound["silentShare"] == .number(0.1))
        let active = try #require(sound["active"]?.array).map(\.object)
        #expect(active.count == 1)
        #expect(active[0]["start"] == .number(1))
        #expect(active[0]["end"] == .number(4.2))
        let split = record().json(limits: .init(bridgeSeconds: 0.1)).object["sound"]?.object["active"]?.array
        #expect(split?.count == 2)
        let curve = try #require(sound["curve"]?.array)
        #expect(curve.count == 10)
        #expect(curve[0] == .number(MediaAnalysis.silenceDb))
        #expect(curve[1] == .number(-20))
    }

    @Test("The overview line for media.list")
    func overview() {
        let row = record().overviewJSON.object
        #expect(row["measured"] == .bool(true))
        #expect(row["shots"] == .integer(3))
        #expect(row["corrected"] == nil)
    }
}
