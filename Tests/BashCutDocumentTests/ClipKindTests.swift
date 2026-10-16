import BashCutDocument
import BashCutProject
import Testing

struct ClipKindTests {
    private func media(_ kind: String, audio: Bool? = nil, alpha: Bool = false) -> Media {
        var fields: [String: JSONValue] = ["id": .string("m"), "kind": .string(kind)]
        if let audio { fields["hasAudio"] = .bool(audio) }
        if alpha { fields["alpha"] = .bool(true) }
        return Media(fields: fields)
    }

    @Test("Footage, graphics, text, audio, voice and adjustments each get their own colour")
    func colourByKind() {
        let clip = Item(media: "m", at: 0, duration: 30)
        let main = Track(id: "t1", kind: TrackKind.video, role: TrackRole.main)
        let overlay = Track(id: "t2", kind: TrackKind.video, role: TrackRole.overlay)
        #expect(ClipKind(item: clip, track: main, media: media("video", audio: true)) == .footage)
        #expect(ClipKind(item: clip, track: overlay, media: media("video", audio: true)) == .footage)
        #expect(ClipKind(item: clip, track: overlay, media: media("video", audio: false)) == .graphic)
        #expect(ClipKind(item: clip, track: main, media: media("image")) == .graphic)
        #expect(ClipKind(item: clip, track: main, media: media("video", audio: true, alpha: true)) == .graphic)
        var planned = clip
        planned["tag"] = .object(["role": .string("graphic")])
        #expect(ClipKind(item: planned, track: main, media: media("video", audio: true)) == .graphic)

        var text = Item(at: 0, duration: 30)
        text["text"] = .string("Hello")
        for role in [TrackRole.captions, TrackRole.titles] {
            #expect(ClipKind(item: text, track: Track(id: "t3", kind: TrackKind.text, role: role), media: nil) == .text)
        }
        let sound = Item(media: "m", at: 0, duration: 9)
        for (role, kind) in [(TrackRole.music, ClipKind.audio), (TrackRole.sfx, .audio),
                             (TrackRole.voiceover, .voice), (TrackRole.dialogue, .voice)] {
            #expect(ClipKind(item: sound, track: Track(id: "a", kind: TrackKind.audio, role: role), media: media("audio")) == kind)
        }
        let adjustment = Track(id: "t6", kind: TrackKind.adjustment, role: TrackRole.adjustment)
        #expect(ClipKind(item: .adjustment(at: 0, duration: 9), track: adjustment, media: nil) == .adjustment)

        #expect(Set(ClipKind.allCases.map(\.color)).count == ClipKind.allCases.count)
        // Footage teal, graphic indigo, text amber: the hue is in the expected channel.
        let teal = ClipKind.footage.color, indigo = ClipKind.graphic.color, amber = ClipKind.text.color
        #expect(teal.green > teal.red && teal.blue > teal.red)
        #expect(indigo.blue > indigo.green && indigo.blue > indigo.red)
        #expect(amber.red > amber.green && amber.green > amber.blue)
    }

    @Test("The layer role is kept as a stripe; speech shots on the main layer keep theirs")
    func roleStripe() {
        let clip = Item(media: "m", at: 0, duration: 30)
        var speech = clip
        speech["tag"] = .object(["role": .string("speech")])
        let main = Track(id: "t1", kind: TrackKind.video, role: TrackRole.main)
        #expect(ClipKind.roleStripe(track: main, item: clip) != nil)
        #expect(ClipKind.roleStripe(track: main, item: speech) != ClipKind.roleStripe(track: main, item: clip))
        let music = Track(id: "a1", kind: TrackKind.audio, role: TrackRole.music)
        let sfx = Track(id: "a2", kind: TrackKind.audio, role: TrackRole.sfx)
        #expect(ClipKind.roleStripe(track: music, item: clip) != ClipKind.roleStripe(track: sfx, item: clip))
        let adjustment = Track(id: "t6", kind: TrackKind.adjustment, role: TrackRole.adjustment)
        #expect(ClipKind.roleStripe(track: adjustment, item: clip) == nil)
        #expect(ClipKind.roleStripe(track: Track(id: "x", kind: TrackKind.video, role: "custom"), item: clip) == nil)
    }

    @Test("Titles are cut in the middle and keep their ending")
    func middleTruncation() {
        let name = "isometric-flow-diagram-canvas.mov"
        func fitting(_ count: Int) -> String { ClipKind.truncatingMiddle(name) { $0.count <= count } }
        #expect(fitting(100) == name)
        #expect(fitting(name.count) == name)
        #expect(fitting(15) == "isom…canvas.mov")
        #expect(fitting(8) == "is…s.mov")
        #expect(fitting(1) == "…")
        #expect(fitting(0).isEmpty)
    }
}
