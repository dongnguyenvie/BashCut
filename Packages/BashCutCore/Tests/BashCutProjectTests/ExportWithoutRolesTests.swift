import Foundation
import Testing

@testable import BashCutProject

/// An export without some sound (#520): the same timeline with those audio layers muted.
struct ExportWithoutRolesTests {
    @Test("Muting by role silences only those audio layers and keeps every item")
    func muting() throws {
        var project = Project(name: "Mix", fps: FrameRate(30, 1))
        project.media = [
            Media(fields: ["id": .string("m"), "path": .string("m.wav"), "fps": FrameRate(30, 1).json, "frames": .integer(900)])
        ]
        let music = try #require(project.tracks.firstIndex { $0.role == TrackRole.music })
        project.tracks[music].items = [Item(id: "bed", media: "m", at: 0, duration: 90)]
        let muted = project.muting(roles: [TrackRole.music])
        #expect(muted.tracks.filter(\.isMuted).map(\.role) == [TrackRole.music])
        #expect(muted.tracks[music].items.map(\.id) == ["bed"])
        #expect(muted.revision == project.revision)
        #expect(!project.tracks[music].isMuted)
        try muted.validate()
    }
}
