import BashCutAutomation
import BashCutDocument
import Testing

@MainActor
struct EditorUIStateTests {
    @Test("Zoom stays inside the timeline zoom range")
    func zoomClamps() {
        let ui = EditorUIState()
        ui.setTimelineZoom(1000)
        #expect(ui.timelineScale == EditorUIState.timelineZoomRange.upperBound)
        #expect(!ui.canZoomIn && ui.canZoomOut)
        ui.setTimelineZoom(0)
        #expect(ui.timelineScale == EditorUIState.timelineZoomRange.lowerBound)
        #expect(ui.canZoomIn && !ui.canZoomOut)
        ui.setTimelineZoom(50)
        ui.zoomIn()
        #expect(ui.timelineScale == 50 * EditorUIState.zoomStep)
        ui.zoomOut()
        #expect(ui.timelineScale == 50)
    }

    @Test("Reveal requests clamp to the timeline and are distinct each time")
    func revealClamps() throws {
        let ui = EditorUIState()
        ui.revealInTimeline(-5, duration: 100)
        let first = try #require(ui.timelineReveal)
        #expect(first.frame == 0)
        ui.revealInTimeline(500, duration: 100)
        #expect(ui.timelineReveal?.frame == 100)
        ui.revealInTimeline(0, duration: 100)
        #expect(ui.timelineReveal != first)
    }

    @Test("Opening another project closes the sheets about the previous one")
    func closeProjectSheets() {
        let ui = EditorUIState()
        ui.showExportReport = true
        ui.showAgentChanges = true
        ui.showExternalChanges = true
        ui.showLegacyImportReport = true
        ui.showSettings = true
        ui.closeProjectSheets()
        #expect(!ui.showExportReport && !ui.showAgentChanges && !ui.showExternalChanges && !ui.showLegacyImportReport)
        #expect(ui.showSettings)
    }

    @Test("Library panels match the `ui.panel` choices")
    func libraryPanels() {
        #expect(CommandCatalog.libraryPanels == LibraryTab.allCases.map(\.panelName))
        #expect(LibraryTab(panelName: "voice") == .voice)
        #expect(LibraryTab(panelName: "Voice") == nil)
    }

    @Test("Named dialogs open their sheet")
    func toggledDialogs() throws {
        let ui = EditorUIState()
        let flag = try #require(EditorUIState.toggledDialogs["doctor"])
        ui[keyPath: flag] = true
        #expect(ui.showDoctor)
        #expect(EditorUIState.toggledDialogs.count == 7)
    }
}
