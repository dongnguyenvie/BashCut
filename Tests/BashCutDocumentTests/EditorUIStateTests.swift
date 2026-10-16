import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutProject
import Testing

@MainActor
struct EditorUIStateTests {
    @Test("Plugin overlays replace per plugin, bump the revision only on change, and clear (#407)")
    func pluginOverlays() throws {
        let ui = EditorUIState()
        let marks = try PluginOverlay.parse(.array([
            .object(["id": .string("m"), "kind": .string("marker"), "start": .integer(10)]),
        ]))
        ui.setPluginOverlays("a.one", marks)
        ui.setPluginOverlays("b.two", marks)
        let revision = ui.pluginOverlayRevision
        ui.setPluginOverlays("a.one", marks)
        #expect(ui.pluginOverlayRevision == revision)
        #expect(ui.pluginOverlays.timeline.count == 2)
        ui.setPluginOverlays("a.one", [])
        #expect(Array(ui.pluginOverlaySets.keys) == ["b.two"] && ui.pluginOverlayRevision == revision + 1)
        ui.clearPluginOverlays(keeping: { $0 == "b.two" })
        #expect(ui.pluginOverlayRevision == revision + 1)
        ui.clearPluginOverlays()
        #expect(ui.pluginOverlays.isEmpty && ui.pluginOverlaySets.isEmpty)
    }

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
        ui.timelineViewportWidth = 1180
        ui.timelineLeading = 140
        // 30 fps × 100 s: (1180 − 140 − 40) points / 100 s = 10 points per second.
        ui.zoomToFit(duration: 3000, fps: 30)
        #expect(abs(ui.timelineScale - 10) < 1e-9)
        #expect(ui.timelineZoomAnchor?.frame == 0 && ui.timelineZoomAnchor?.viewOffset == 140)
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
        // `voice` is the old Voice panel; `captions` and `beats` are tools too. Each opens Tools on that tool.
        #expect(CommandCatalog.libraryPanels == LibraryTab.allCases.map(\.panelName) + ToolID.builtIn)
        // Every Media panel source can be chosen with ui view --media-source, library clips too (P2-H5).
        #expect(UIAction.mediaSources == ["footage", "project", "shared", "selects", "clips"])
        #expect(LibraryTab(panelName: "voice") == .tools && LibraryTab.toolForPanelName("voice") == ToolID.voice)
        #expect(LibraryTab(panelName: "tools") == .tools && LibraryTab.toolForPanelName("tools") == nil)
        #expect(LibraryTab(panelName: "Voice") == nil)
    }

    @Test("Tool targets: each built-in tool lists what it supports, a plugin action's follow its condition")
    func toolTargets() {
        #expect(ToolTarget.supported(by: ToolID.captions) == [.selectedClip, .project])
        #expect(ToolTarget.supported(by: ToolID.beats) == [.selectedClip, .project])
        #expect(ToolTarget.supported(by: ToolID.voice) == [.project])
        #expect(ToolTarget.supported(whenCondition: "selection && selection.kind == video", readsTimeline: false) == [.selectedClip])
        #expect(ToolTarget.supported(whenCondition: "project && !playing", readsTimeline: true) == [.wholeTimeline])
        #expect(ToolTarget.supported(whenCondition: nil, readsTimeline: false) == [.project])
        #expect(ToolTarget.supported(whenCondition: "track.kind == audio", readsTimeline: false) == [.project])
    }

    @Test("The rail has eight asset panels, then Tools")
    func railPanels() {
        #expect(LibraryTab.assets.map(\.panelName) == [
            "media", "audio", "text", "stickers", "effects", "transitions", "filters", "brand",
        ])
        #expect(LibraryTab.allCases.last == .tools && !LibraryTab.tools.isAsset)
        #expect(LibraryTab.assets.allSatisfy { $0.isAsset })
    }

    @Test("Named dialogs open their sheet")
    func toggledDialogs() throws {
        let ui = EditorUIState()
        let flag = try #require(EditorUIState.toggledDialogs["doctor"])
        ui[keyPath: flag] = true
        #expect(ui.showDoctor)
        #expect(EditorUIState.toggledDialogs["assets"] == \.showAssetSearch)
        #expect(EditorUIState.toggledDialogs.count == 12)
    }
}
