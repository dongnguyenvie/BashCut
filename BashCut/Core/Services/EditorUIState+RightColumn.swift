import Foundation

// The right column's tab toggles (P1-6).
extension EditorUIState {
    /// ⌘J with the agent in the window: hides the column while the Agent tab shows, otherwise shows that tab.
    public func toggleAgentTab() {
        if rightTab == .agent, showAgentDock { showAgentDock = false } else { showAgentDock = true }
    }

    /// The Inspector toggle: hides the column while the Inspector tab shows, otherwise shows that tab.
    public func toggleInspectorTab() {
        if rightTab == .inspector, showInspector { showInspector = false } else { showInspector = true }
    }

    /// A timeline item was selected: the Inspector comes forward, unless the user just picked the Agent tab.
    public func itemSelected(now: Date = Date()) {
        guard rightTab == .agent, rightColumnVisible else { return }
        if let picked = agentPickedAt, now.timeIntervalSince(picked) < Self.agentTabHold { return }
        showInspector = true
    }

    /// The agent moved to its own window (or came back). A column showing the Agent tab goes back to the Inspector.
    public func setAgentPoppedOut(_ out: Bool) {
        agentPoppedOut = out
        if out, rightTab == .agent { showInspector = true }
    }
}
