import Foundation
import Testing
@testable import BashCutImport
@testable import BashCutProject

@Test("Legacy EDL imports cuts, picture borrowing, transforms and sections")
func importsLegacyEDL() throws {
    let data = Data(
        """
        {
          "fps": 29.97,
          "total_frames": 150,
          "clips": [
            {"path":"/work/timeline/a.mov","src_in_frame":10,"so_frame":60,"rec_frame":0,
             "zoom":1.2,"sec":"Hook","sub":"Opening|1.0|Detail"},
            {"path":"/work/timeline/a.mov","vpath":"/work/timeline/b.mov",
             "src_in_frame":4,"so_frame":90,"rec_frame":60,"sec":"Body"}
          ],
          "vo": [
            {"path":"/work/timeline/voice.wav","t":1.0,"duration":1.0,"text":"Voice line"}
          ],
          "fx": {"clip": []}
        }
        """.utf8)
    let report = try LegacyEDLImporter.decode(
        data, name: "Imported", destinationDirectory: URL(fileURLWithPath: "/work/timeline"))

    #expect(report.sourceCutCount == 2)
    #expect(report.importedCutCount == 2)
    #expect(report.sourceVoiceoverCount == 1)
    #expect(report.importedVoiceoverCount == 1)
    #expect(report.sourceTotalFrames == 150)
    #expect(report.importedDuration == 150)
    #expect(report.project.media.count == 3)
    #expect(report.project.sectionMarkers.map(\.label) == ["Hook", "Body"])
    #expect(report.project.tracks.first { $0.role == "dialogue" }?.items.count == 2)
    #expect(report.project.tracks.first { $0.role == "main" }?.items.first?.linkedItemID != nil)
    #expect(report.project.tracks.first { $0.role == "main" }?.items.last?.linkedItemID == nil)
    #expect(report.project.tracks.first { $0.role == "voiceover" }?.items.count == 1)
    // The voiceover caption overlaps clip captions, so it lands on a second caption layer.
    #expect(report.project.tracks.filter { $0.role == "captions" }.map { $0.items.map(\.text) }
        == [["Opening", "Detail"], ["Voice line"]])
    #expect(report.project.tracks.first { $0.role == "main" }?.items.first?.fields["transform"] != nil)
    #expect(report.warnings == ["fx requires manual review"])
}

@Test("Legacy EDL rejects missing clip duration without producing a project")
func rejectsIncompleteLegacyEDL() {
    let data = Data(#"{"clips":[{"path":"a.mov"}]}"#.utf8)
    #expect(throws: ProjectError.self) {
        try LegacyEDLImporter.decode(
            data, name: "Broken", destinationDirectory: URL(fileURLWithPath: "/tmp"))
    }
}
