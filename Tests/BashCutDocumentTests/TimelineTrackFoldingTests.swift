import BashCutDocument
import BashCutProject
import Foundation
import Testing

@MainActor
struct TimelineTrackFoldingTests {
    private func track(_ id: String, role: String, clips: Int = 0) -> Track {
        Track(fields: [
            "id": .string(id), "role": .string(role), "kind": .string("video"),
            "items": .array((0..<clips).map { .object(Item(id: "\(id)-\($0)", at: $0 * 10, duration: 10).fields) }),
        ])
    }

    private var tracks: [Track] {
        [track("main", role: TrackRole.main), track("o1", role: TrackRole.overlay, clips: 1),
         track("o2", role: TrackRole.overlay), track("a1", role: TrackRole.music)]
    }

    @Test("Empty layers are listed in track order and the main layer never counts, even without clips")
    func emptyIDs() {
        #expect(TimelineTrackFolding.emptyTrackIDs(in: tracks) == ["o2", "a1"])
    }

    @Test("Folding hides the empty layers, keeps the selected one, and shows everything once expanded")
    func folding() {
        #expect(TimelineTrackFolding.foldedTrackIDs(in: tracks, expanded: false) == ["o2", "a1"])
        #expect(TimelineTrackFolding.foldedTrackIDs(in: tracks, expanded: false, keep: "o2") == ["a1"])
        #expect(TimelineTrackFolding.foldedTrackIDs(in: tracks, expanded: false, keep: "o1") == ["o2", "a1"])
        #expect(TimelineTrackFolding.foldedTrackIDs(in: tracks, expanded: true).isEmpty)
    }

    @Test("A layer that gets a clip stops being folded")
    func filled() {
        var filled = tracks
        filled[2].items = [Item(id: "x", at: 0, duration: 5)]
        #expect(TimelineTrackFolding.foldedTrackIDs(in: filled, expanded: false) == ["a1"])
    }

    @Test("The header is wide from 1280 pt and compact below")
    func headerDefault() {
        #expect(EditorUIState.defaultTimelineLeading(windowWidth: 1280) == EditorUIState.wideTimelineLeading)
        #expect(EditorUIState.defaultTimelineLeading(windowWidth: 1279) == EditorUIState.compactTimelineLeading)
    }

    @Test("The header width counts as chosen only once the user sets it")
    func headerChosen() throws {
        let suite = "bashcut-fold-tests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsModel(defaults: defaults)
        #expect(!settings.timelineHeaderWidthChosen)
        settings.timelineHeaderWidth = EditorUIState.wideTimelineLeading
        #expect(settings.timelineHeaderWidthChosen)
        #expect(SettingsModel(defaults: defaults).timelineHeaderWidthChosen)
    }
}
