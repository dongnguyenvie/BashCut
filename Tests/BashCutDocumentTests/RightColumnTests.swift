import BashCutDocument
import Foundation
import Testing

@MainActor
struct RightColumnTests {
    @Test("The column opens on the Agent tab, and the Inspector flag selects the Inspector tab (P1-6)")
    func tabs() {
        let ui = EditorUIState()
        #expect(ui.rightTab == .agent && ui.rightColumnVisible)
        ui.selectRightTab(.inspector)
        #expect(ui.rightTab == .inspector && ui.showInspector)
        ui.showAgentDock = true
        #expect(ui.rightTab == .agent && ui.rightColumnVisible)
    }

    @Test("Cmd+J hides the column while the Agent tab shows, otherwise shows that tab")
    func toggleAgent() {
        let ui = EditorUIState()
        ui.selectRightTab(.inspector)
        ui.toggleAgentTab()
        #expect(ui.rightTab == .agent && ui.rightColumnVisible)
        ui.toggleAgentTab()
        #expect(!ui.rightColumnVisible)
        ui.toggleAgentTab()
        #expect(ui.rightTab == .agent && ui.rightColumnVisible)
        ui.toggleInspectorTab()
        #expect(ui.rightTab == .inspector && ui.rightColumnVisible)
        ui.toggleInspectorTab()
        #expect(!ui.rightColumnVisible)
    }

    @Test("Selecting an item brings the Inspector forward unless the Agent tab was picked in the last 2 s")
    func selectionSwitch() {
        let ui = EditorUIState()
        let now = Date()
        ui.selectRightTab(.agent, now: now)
        ui.itemSelected(now: now.addingTimeInterval(1))
        #expect(ui.rightTab == .agent)
        ui.itemSelected(now: now.addingTimeInterval(EditorUIState.agentTabHold + 1))
        #expect(ui.rightTab == .inspector)
    }

    @Test("A hidden column stays hidden when an item is selected")
    func hiddenStaysHidden() {
        let ui = EditorUIState()
        ui.showAgentDock = true
        ui.showAgentDock = false
        ui.itemSelected(now: Date().addingTimeInterval(10))
        #expect(!ui.rightColumnVisible)
    }

    @Test("A popped-out agent leaves the Inspector in the column, and its tab still opens")
    func poppedOut() {
        let ui = EditorUIState()
        ui.showAgentDock = true
        ui.showAgentDock = false
        ui.setAgentPoppedOut(true)
        ui.selectRightTab(.agent)
        #expect(ui.rightTab == .agent && ui.rightColumnVisible)
        ui.setAgentPoppedOut(false)
        ui.showAgentDock = true // what `attach()` does
        #expect(ui.rightTab == .agent && ui.rightColumnVisible)
    }
}
