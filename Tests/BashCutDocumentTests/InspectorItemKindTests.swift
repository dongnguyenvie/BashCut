import BashCutDocument
import BashCutProject
import Testing

struct InspectorItemKindTests {
    private func media(_ kind: String, audio: Bool? = nil) -> Media {
        var fields: [String: JSONValue] = ["id": .string("m"), "kind": .string(kind)]
        if let audio { fields["hasAudio"] = .bool(audio) }
        return Media(fields: fields)
    }

    @Test("A graphic has no Audio, Text or Speed tab; a clip has no Text tab; text has Text and Video")
    func tabsByKind() {
        let clip = Item(media: "m", at: 0, duration: 30)
        let main = Track(id: "t1", kind: TrackKind.video, role: TrackRole.main)
        let overlay = Track(id: "t2", kind: TrackKind.video, role: TrackRole.overlay)
        #expect(InspectorItemKind(item: clip, track: main, media: media("video", audio: true)) == .clip)
        #expect(InspectorItemKind(item: clip, track: main, media: media("video", audio: true)).tabs
            == ["video", "audio", "color", "speed"])
        let graphic = InspectorItemKind(item: clip, track: overlay, media: media("video", audio: false))
        #expect(graphic == .graphic && graphic.tabs == ["video", "color"])
        #expect(InspectorItemKind(item: clip, track: main, media: media("image")) == .graphic)
        #expect(InspectorItemKind(item: clip, track: overlay, media: media("video", audio: true)) == .clip)
    }

    @Test("Captions, titles, audio and adjustment layers")
    func otherKinds() {
        var text = Item(at: 0, duration: 30)
        text["text"] = .string("Hello")
        let captions = Track(id: "t3", kind: TrackKind.text, role: TrackRole.captions)
        let titles = Track(id: "t4", kind: TrackKind.text, role: TrackRole.titles)
        #expect(InspectorItemKind(item: text, track: captions, media: nil) == .caption)
        #expect(InspectorItemKind(item: text, track: titles, media: nil) == .text)
        #expect(InspectorItemKind.text.tabs == ["text", "video"])
        let music = Track(id: "t5", kind: TrackKind.audio, role: TrackRole.music)
        #expect(InspectorItemKind(item: Item(media: "m", at: 0, duration: 9), track: music, media: media("audio")).tabs
            == ["audio", "speed"])
        let adjustment = Track(id: "t6", kind: TrackKind.adjustment, role: TrackRole.adjustment)
        #expect(InspectorItemKind(item: .adjustment(at: 0, duration: 9), track: adjustment, media: nil).tabs == ["color"])
    }
}
