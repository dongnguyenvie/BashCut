import BashCutProject
import Foundation

/// An interactive zsh in the workspace; its edits are the user's.
public struct ShellAgentProvider: AgentProvider {
    public init() {}
    public let id = AgentProviderID.shell
    public let title = "Shell"
    public let command = "zsh"
    public let author = Author.user
    public let isAgent = false
    public let environmentAllowlist = ["EDITOR", "VISUAL", "PAGER"]

    public func commandLine(for request: AgentLaunchRequest) throws -> AgentCommandLine {
        AgentCommandLine(arguments: ["-i"])
    }
}
