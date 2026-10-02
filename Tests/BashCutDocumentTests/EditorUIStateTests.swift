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

    @Test("Zooming keeps an anchor frame: the playhead for buttons, the pointer for pinch and scroll")
    func zoomAnchors() throws {
        let ui = EditorUIState()
        ui.setTimelineZoom(50)
        #expect(ui.timelineZoomAnchor == nil)
        ui.zoomIn(around: 120)
        let button = try #require(ui.timelineZoomAnchor)
        #expect(button.frame == 120 && button.viewOffset == nil)
        ui.magnifyTimeline(by: 2, at: 300, viewOffset: 410)
        let pinch = try #require(ui.timelineZoomAnchor)
        #expect(pinch.frame == 300 && pinch.viewOffset == 410 && pinch.id != button.id)
        #expect(ui.timelineScale == 50 * EditorUIState.zoomStep * 2)
        ui.magnifyTimeline(by: 0, at: 0, viewOffset: 0)
        ui.magnifyTimeline(by: .nan, at: 0, viewOffset: 0)
        #expect(ui.timelineScale == 50 * EditorUIState.zoomStep * 2)
    }

    @Test("The slider is logarithmic: equal slider steps are equal zoom ratios")
    func logSlider() {
        let ui = EditorUIState()
        let range = EditorUIState.timelineZoomSliderRange
        ui.setTimelineZoomSliderValue(range.lowerBound)
        #expect(abs(ui.timelineScale - EditorUIState.timelineZoomRange.lowerBound) < 1e-9)
        ui.setTimelineZoomSliderValue(range.upperBound)
        #expect(abs(ui.timelineScale - EditorUIState.timelineZoomRange.upperBound) < 1e-9)
        ui.setTimelineZoomSliderValue((range.lowerBound + range.upperBound) / 2, around: 10)
        let middle = ui.timelineScale
        #expect(abs(middle / EditorUIState.timelineZoomRange.lowerBound
            - EditorUIState.timelineZoomRange.upperBound / middle) < 1e-6)
        #expect(ui.timelineZoomAnchor?.frame == 10)
    }

    @Test("Zoom to fit shows the whole timeline in the visible width, within the zoom range")
    func zoomToFit() {
        let ui = EditorUIState()
        ui.timelineViewportWidth = 1145
        // 30 fps × 100 s: (1145 − 105 − 40) points / 100 s = 10 points per second.
        ui.zoomToFit(duration: 3000, fps: 30)
        #expect(abs(ui.timelineScale - 10) < 1e-9)
        #expect(ui.timelineZoomAnchor?.frame == 0 && ui.timelineZoomAnchor?.viewOffset == EditorUIState.timelineLeading)
        ui.zoomToFit(duration: 30 * 3600 * 3, fps: 30)
        #expect(ui.timelineScale == EditorUIState.timelineZoomRange.lowerBound)
        ui.zoomToFit(duration: 1, fps: 30)
        #expect(ui.timelineScale == EditorUIState.timelineZoomRange.upperBound)
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
