import BashCutDocument
import Foundation
import Testing

/// Inspector and Agent are separate columns (they were two tabs of one right column, P1-6): each is shown or hidden
/// on its own, so selecting a timeline item while the agent works never takes the agent away.
@MainActor
struct RightColumnTests {
    @Test("A project opens with both columns, and each pane's toggle leaves the other as it is")
    func independentToggles() {
        let ui = EditorUIState()
        #expect(ui.inspectorShown && ui.agentColumnShown)
        ui.toggleInspectorTab()
        #expect(!ui.inspectorShown && ui.agentColumnShown)
        ui.toggleAgentTab()
        #expect(!ui.inspectorShown && !ui.agentColumnShown)
        ui.toggleInspectorTab()
        #expect(ui.inspectorShown && !ui.agentColumnShown)
        ui.toggleAgentTab()
        #expect(ui.inspectorShown && ui.agentColumnShown)
    }

    @Test("ui view --right-tab shows that pane and never hides the other")
    func rightTabShowsPane() {
        let ui = EditorUIState()
        ui.showInspector = false
        ui.selectRightTab(.inspector)
        #expect(ui.inspectorShown && ui.agentColumnShown)
        ui.showAgentDock = false
        ui.selectRightTab(.agent)
        #expect(ui.inspectorShown && ui.agentColumnShown)
    }

    @Test("Opening the agent (a new terminal, a question) shows its column and keeps the Inspector")
    func openingAgentKeepsInspector() {
        let ui = EditorUIState()
        ui.showAgentDock = false
        ui.showAgentDock = true
        #expect(ui.inspectorShown && ui.agentColumnShown)
    }

    @Test("A popped-out agent has no column in the editor window until it comes back")
    func poppedOut() {
        let ui = EditorUIState()
        ui.setAgentPoppedOut(true)
        #expect(!ui.agentColumnShown && ui.inspectorShown)
        ui.setAgentPoppedOut(false)
        #expect(ui.agentColumnShown)
    }
}
