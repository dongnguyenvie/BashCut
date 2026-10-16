import Foundation

// The side panes' toggles: Inspector and Agent are separate columns, each shown or hidden on its own.
extension EditorUIState {
    /// ⌘J with the agent in the window: shows or hides the agent column.
    public func toggleAgentTab() { showAgentDock.toggle() }

    /// ⌃⌘I: shows or hides the Inspector column.
    public func toggleInspectorTab() { showInspector.toggle() }

    /// The agent moved to its own window (or came back); its column leaves the editor window meanwhile.
    public func setAgentPoppedOut(_ out: Bool) { agentPoppedOut = out }
}
