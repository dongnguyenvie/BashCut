import Foundation
import Testing

@testable import BashCutProject

/// The mix by role without exporting (#471, P0-B9), on synthetic loudness curves.
struct MixMeasureTests {
    /// 10 s at 30 fps; a cut at frame 60, beats every 30 frames, one sound effect at 3.0–3.5 s (frames 90–105).
    func project() -> Project {
        var project = Project(name: "Mix", fps: FrameRate(30, 1))
        project.media = [Media(fields: ["id": .string("m"), "path": .string("m.mp4"), "fps": FrameRate(30, 1).json, "frames": .integer(300)])]
        let main = project.tracks.firstIndex { $0.role == TrackRole.main }!
        project.tracks[main].items = [Item(id: "a", media: "m", at: 0, duration: 60), Item(id: "b", media: "m", at: 60, duration: 240, sourceIn: 60)]
        project.tracks.append(Track(id: "fx", kind: TrackKind.audio, role: TrackRole.sfx))
        project.tracks[project.tracks.count - 1].items = [Item(id: "s", media: "m", at: 90, duration: 15)]
        project["beatGrid"] = .object([
            "media": .string("m"), "bpm": .number(60),
            "frames": .array(stride(from: 0, through: 270, by: 30).map(JSONValue.integer)),
        ])
        return project
    }

    /// Speech −20 LUFS for 0–4 s, silent after; music −29 throughout; the effect −24 at 3.0–3.5 s, else silent.
    func curves() -> (MixMeasure.Curve, MixMeasure.Curve, MixMeasure.Curve) {
        let speech = MixMeasure.Curve(momentary: (0..<100).map { $0 < 40 ? -20 : -100 })
        let music = MixMeasure.Curve(momentary: Array(repeating: -29, count: 100))
        let effect = MixMeasure.Curve(
            momentary: (0..<100).map { (30..<35).contains($0) ? -24 : -100 },
            peakDb: (0..<100).map { $0 == 31 ? -6 : (30..<35).contains($0) ? -12 : -100 })
        return (speech, music, effect)
    }

    @Test("Voice, music under speech and in the gaps; speech windows from the stem")
    func stems() throws {
        let (speech, music, effect) = curves()
        let json = MixMeasure.json(project(), speech: speech, music: music, effects: effect, words: []).object
        #expect(json["speechFrom"] == .string("stem"))
        #expect(json["voice"]?.object["median"] == .number(-20))
        #expect(json["musicUnderSpeech"]?.object["median"] == .number(9))
        #expect(json["musicInGaps"]?.object["median"] == .number(-29))
        let windows = try #require(json["speechWindows"]?.array).map(\.object)
        #expect(windows.count == 1 && windows[0]["end"] == .number(4))
        let fx = try #require(json["effects"]?.array.first).object
        #expect(fx["loudness"] == .number(-24) && fx["peakDb"] == .number(-6))
        #expect(fx["voiceP95"] == .number(-20) && fx["deltaDb"] == .number(-4) && fx["masked"] == .bool(true))
        #expect(fx["onsetOffsets"]?.object["cut"] == .integer(30) && fx["onsetOffsets"]?.object["beat"] == .integer(0))
        #expect(fx["peakFrame"] == .integer(93))
    }

    @Test("Words decide the spoken blocks when there are any")
    func words() {
        let (speech, music, _) = curves()
        // Words only over 1–2 s: the rest of the speech stem counts as gap.
        let json = MixMeasure.json(
            project(), speech: speech, music: music, effects: nil, words: [ReviewSync.WordSpan(at: 30, end: 60, text: "chào")]).object
        #expect(json["speechFrom"] == .string("words"))
        #expect(json["voice"]?.object["blocks"] == .integer(10))
        #expect(json["musicInGaps"]?.object["blocks"] == .integer(90))
    }

    @Test("Silences and sound landmarks follow the −70 LUFS gate")
    func silencesAndLandmarks() throws {
        let curve = MixMeasure.Curve(momentary: [-100, -100, -30, -20, -80, -100], peakDb: [-100, -100, -10, -3, -40, -100])
        let silences = try #require(MixMeasure.silences(curve).array).map(\.object)
        #expect(silences.map { $0["start"] } == [.number(0), .number(0.4)])
        let marks = try #require(MixMeasure.landmarks(curve))
        #expect(abs((marks["onset"] ?? 0) - 0.2) < 1e-9 && abs((marks["peak"] ?? 0) - 0.3) < 1e-9)
        #expect(abs((marks["tail"] ?? 0) - 0.7) < 1e-9)
        #expect(MixMeasure.landmarks(MixMeasure.Curve(momentary: [-100])) == nil)
    }

    @Test("Library sounds keep their landmarks")
    func libraryLandmarks() throws {
        let audio = try LibraryAudio(params: ["landmarks": .object(["onset": .number(0.1), "peak": .number(0.3), "tail": .number(1.25)])])
        #expect(audio.landmarks?["tail"] == 1.25)
        #expect(audio.params()["landmarks"]?.object["onset"] == .number(0.1))
        #expect(throws: ProjectError.self) { try LibraryAudio(params: ["landmarks": .object(["start": .number(1)])]) }
    }
}
