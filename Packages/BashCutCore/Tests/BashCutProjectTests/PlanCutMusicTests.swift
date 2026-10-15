import Foundation
import Testing

@testable import BashCutProject

/// The music bed of the edit list (#630).
extension PlanCutTests {
    @Test("Music without duck is one fixed bed with ducking off; duck or duckDb turns ducking on with a 2.5 s hold (#630)")
    func musicBed() throws {
        let project = project()
        func built(_ music: String) throws -> Project {
            let cut = try spec(#"{"clips":[{"id":"a","media":"m","from":0,"to":8}],"music":"# + music + "}")
            return try PlanCut.build(cut, clips: PlanCut.resolve(cut, project: project, transcripts: [:]).clips, on: project)
                .planner.project
        }
        let fixed = try built(#"{"media":"song"}"#)
        let layer = try #require(fixed.track(role: TrackRole.music))
        // A new project's Music layer ducks by default; a plan bed turns it off and sits at the fallback until measured.
        #expect(project.track(role: TrackRole.music)?["duckingEnabled"] == .bool(true))
        #expect(layer["duckingEnabled"] == .bool(false) && MusicDucking.duckDb(layer) == nil)
        #expect(layer.items.first?["volumeDb"] == .number(PlanCut.Music.fallbackVolumeDb))
        #expect(try spec(#"{"clips":[{"media":"m"}],"music":{"media":"song"}}"#).music?.measuresLevel == true)
        #expect(try spec(#"{"clips":[{"media":"m"}],"music":{"media":"song","volumeDb":-22}}"#).music?.measuresLevel == false)

        let ducked = try #require(try built(#"{"media":"song","duck":true}"#).track(role: TrackRole.music))
        #expect(ducked["duckingEnabled"] == .bool(true) && ducked["duckUnderSpeechDb"] == .number(-14))
        #expect(ducked["duckMinGapFrames"] == .integer(Int((2.5 * project.fps.value).rounded())))
        #expect(ducked.items.first?["volumeDb"] == nil)
        let held = try #require(try built(#"{"media":"song","duckDb":-18,"duckMinGapSeconds":4}"#).track(role: TrackRole.music))
        #expect(held["duckUnderSpeechDb"] == .number(-18))
        #expect(held["duckMinGapFrames"] == .integer(Int((4 * project.fps.value).rounded())))
        #expect(try built(#"{"media":"song","duckDb":-18,"duck":false}"#).track(role: TrackRole.music)?["duckingEnabled"] == .bool(false))
        for bad in [#"{"media":"song","underVoiceDb":50}"#, #"{"media":"song","duckMinGapSeconds":-1}"#, #"{"media":"song","duck":"yes"}"#] {
            #expect(throws: ProjectError.self) { try spec(#"{"clips":[{"media":"m"}],"music":"# + bad + "}") }
        }
        // Voice at −18 LUFS, music measured at −10 LUFS at 0 dB: 16 dB under the voice is −24 dB of clip gain.
        #expect(MusicDucking.bedVolumeDb(voiceLUFS: -18, musicLUFS: -10, underVoiceDb: 16) == -24)
        #expect(MusicDucking.bedVolumeDb(voiceLUFS: -18, musicLUFS: 60, underVoiceDb: 16) == -60)
    }
}
