import Foundation
import Testing
@testable import BashCutImport
@testable import BashCutInterchange
@testable import BashCutProject

@Suite("Timeline formats")
struct TimelineFormatTests {
    private let edl = Data(
        """
        {"fps": 30, "total_frames": 120,
         "clips": [{"path":"/work/timeline/a.mov","src_in_frame":0,"so_frame":60,"rec_frame":0}],
         "fx": {"clip": []}}
        """.utf8)

    @Test("The legacy EDL importer reports source and imported counts, a duration mismatch and warnings")
    func legacyImport() throws {
        let result = try LegacyEDLFormat().importTimeline(
            edl, name: "Imported", destinationDirectory: URL(fileURLWithPath: "/work/timeline"))
        #expect(result.project.name == "Imported")
        #expect(result.counts.map(\.key) == ["cuts", "voiceovers", "duration"])
        #expect(result.counts.first?.source == 1 && result.counts.first?.imported == 1)
        #expect(result.counts.last?.source == 120 && result.counts.last?.imported == 60)
        #expect(result.mismatchNote == "Imported duration differs from the EDL total.")
        #expect(result.warnings == ["fx requires manual review"])
        let json = result.json.object
        #expect(json["cuts"] == .integer(1) && json["sourceCuts"] == .integer(1))
        #expect(json["duration"] == .integer(60) && json["sourceDuration"] == .integer(120))
        #expect(json["warnings"] == .array([.string("fx requires manual review")]))
    }

    @Test("Exporters write OTIO and SubRip through the same protocol")
    func exporters() throws {
        var caption = Item(at: 0, duration: 30)
        caption["text"] = .string("Xin chào")
        let base = Project(name: "Formats")
        let project = try base.applying(.insert(track: base.requireTrack(role: TrackRole.captions).id, item: caption)).project
        let exporters: [any TimelineExporter] = [OpenTimelineIOExporter(), SubRipExporter()]
        #expect(exporters.map(\.id) == ["otio", "srt"])
        let otio = try JSONDecoder().decode(JSONValue.self, from: exporters[0].data(for: project))
        #expect(otio.object["OTIO_SCHEMA"] == .string("Timeline.1"))
        let srt = try #require(String(bytes: try exporters[1].data(for: project), encoding: .utf8))
        #expect(srt.contains("Xin chào"))
        #expect(try SubRip.decode(srt, fps: project.fps).count == 1)
    }
}
