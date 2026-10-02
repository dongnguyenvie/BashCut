import BashCutInterchange
import BashCutProject
import Foundation
import Testing

@Test("OTIO export preserves timing, overlapping lanes and BashCut metadata")
func exportsOpenTimelineIO() throws {
    var project = Project(name: "OTIO", fps: FrameRate(30, 1))
    project.media = [
        Media(fields: [
            "id": .string("m1"), "path": .string("footage/a.mov"), "kind": .string("video"),
            "fps": FrameRate(60, 1).json, "frames": .integer(600),
        ]),
    ]
    var tracks = project.tracks
    tracks[0].items = [Item(id: "clip", media: "m1", at: 30, duration: 60, sourceIn: 120)]
    tracks[1].items = [
        Item(id: "over-a", media: "m1", at: 10, duration: 30),
        Item(id: "over-b", media: "m1", at: 20, duration: 30),
    ]
    project.tracks = tracks
    project.markers = [TimelineMarker(id: "section", at: 30, kind: "section", label: "Hook")]

    let data = try OpenTimelineIOExporter.data(for: project)
    let json = try JSONDecoder().decode(JSONValue.self, from: data).object
    #expect(json["OTIO_SCHEMA"] == .string("Timeline.1"))
    #expect(json["tracks"]?.object["markers"]?.array.first?.object["OTIO_SCHEMA"] == .string("Marker.2"))
    let exportedTracks = json["tracks"]?.object["children"]?.array ?? []
    #expect(exportedTracks.count == 8)
    #expect(exportedTracks[0].object["children"]?.array.first?.object["OTIO_SCHEMA"] == .string("Gap.1"))
    #expect(exportedTracks[0].object["children"]?.array.last?.object["media_reference"]?.object["target_url"]
        == .string("footage/a.mov"))
    #expect(exportedTracks[0].object["children"]?.array.last?.object["OTIO_SCHEMA"] == .string("Clip.1"))
    #expect(exportedTracks[0].object["enabled"] == .bool(true))
    #expect(exportedTracks.filter {
        $0.object["metadata"]?.object["bashcut"]?.object["trackID"] == .string("v2")
    }.count == 2)
}
