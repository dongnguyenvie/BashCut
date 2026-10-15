import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

/// The music bed of `plan.cut` (#630): one fixed level set from the measured voice unless ducking is asked for.
extension ProjectDocument {
    /// What plan check says about the bed before anything is measured.
    static func planMusicSummary(_ music: PlanCut.Music) -> JSONValue {
        if music.ducks {
            return .object([
                "ducking": .bool(true), "duckDb": music.duckDb.map(JSONValue.number) ?? .null,
                "duckMinGapSeconds": .number(music.duckMinGapSeconds ?? MusicDucking.defaultMinGapSeconds),
                "volumeDb": music.volumeDb.map(JSONValue.number) ?? .null,
            ])
        }
        if let volume = music.volumeDb { return .object(["ducking": .bool(false), "volumeDb": .number(volume)]) }
        return .object([
            "ducking": .bool(false), "underVoiceDb": .number(music.underVoiceDb ?? PlanCut.Music.defaultUnderVoiceDb),
            "volumeDb": .string("set on apply from the measured voice"),
        ])
    }

    /// The fixed bed for a `plan.cut` music without `volumeDb` or ducking: the built edit's speech and its music bed
    /// at 0 dB are rendered and measured, and the bed is set `underVoiceDb` under the voice. Without a voice, or when
    /// a measurement fails, the bed keeps the fallback level and the report says why.
    func planMusicBed(_ music: PlanCut.Music?, built: Project) async -> (operations: [EditOperation], report: JSONValue?) {
        guard let music else { return ([], nil) }
        guard music.measuresLevel else { return ([], Self.planMusicSummary(music)) }
        let under = music.underVoiceDb ?? PlanCut.Music.defaultUnderVoiceDb
        var report: [String: JSONValue] = [
            "ducking": .bool(false), "underVoiceDb": .number(under), "volumeDb": .number(PlanCut.Music.fallbackVolumeDb),
            "measured": .bool(false),
        ]
        let bedID = "plan-music"
        guard let musicTrack = built.track(role: TrackRole.music), musicTrack.items.contains(where: { $0.id == bedID }) else {
            return ([], .object(report))
        }
        guard !MusicDucking.speechRanges(in: built).isEmpty else {
            report["reason"] = .string("no voice in the edit; the bed keeps the fallback level")
            return ([], .object(report))
        }
        var bedAlone = built
        for index in bedAlone.tracks.indices where bedAlone.tracks[index].role == TrackRole.music {
            for item in bedAlone.tracks[index].items.indices {
                let isBed = bedAlone.tracks[index].items[item].id == bedID
                bedAlone.tracks[index].items[item]["volumeDb"] = .number(isBed ? 0 : -120)
            }
        }
        do {
            let voice = try await measureRendered(stemProject(.speech, of: built), provider: nil).integratedLUFS
            let bed = try await measureRendered(stemProject(.music, of: bedAlone), provider: nil).integratedLUFS
            report["voiceLUFS"] = .number((voice * 10).rounded() / 10)
            report["musicLUFS"] = .number((bed * 10).rounded() / 10)
            guard voice > MixMeasure.silenceLUFS, bed > MixMeasure.silenceLUFS else {
                report["reason"] = .string("the voice or the music measured silent; the bed keeps the fallback level")
                return ([], .object(report))
            }
            let volume = MusicDucking.bedVolumeDb(voiceLUFS: voice, musicLUFS: bed, underVoiceDb: under)
            report["volumeDb"] = .number(volume)
            report["measured"] = .bool(true)
            return ([.setProperties(item: bedID, patch: ["volumeDb": .number(volume)])], .object(report))
        } catch {
            report["reason"] = .string("could not measure (\(error.localizedDescription)); the bed keeps the fallback level")
            return ([], .object(report))
        }
    }
}
