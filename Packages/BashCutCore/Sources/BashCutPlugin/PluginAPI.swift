import Foundation

/// Host plugin API versions. Changes are additive: a host serves every version from `minimum` to `current`. Version 2
/// adds `options`, `contributes` (actions and hooks) and the `session` transport. Version 3 adds option `choiceLabels`
/// and the `file` option type, the `BASHCUT_PLUGIN_DATA`/`BASHCUT_PLUGIN_CACHE` folders and `::progress` lines from
/// install recipes. Version 4 adds the `secret` option type and the session host channel (`event` and `call` lines
/// during a request), used by the `agent.chat` capability. Version 5 adds the `agent.terminal` capability and the
/// manifest's `terminal` object. Version 6 adds `contributes.library` (library packs), the `library.search` and
/// `library.generate` capabilities and provider `kinds`. Version 7 adds `contributes.skills` (agent skills). Version 8
/// adds `contributes.container`/`views`, `requires`, `uses` and `features` (`PluginComposition.swift`), version 9 the
/// `review.check` capability; since 8 it goes up at most once per release, and smaller additions are features.
public enum PluginAPI {
    public static let minimum = 1
    public static let current = 9
    /// The chat-agent capability; its requests carry a host channel (API 4).
    public static let agentChat = "agent.chat"
    /// An agent CLI in a dock terminal tab (API 5); its manifest has a `terminal` object.
    public static let agentTerminal = "agent.terminal"
    /// Finds library items online or elsewhere for a panel (API 6); providers may list the `kinds` they serve.
    public static let librarySearch = "library.search"
    /// Makes new library items from a prompt (API 6); providers may list the `kinds` they serve.
    public static let libraryGenerate = "library.generate"
    /// The capabilities whose providers return library item candidates.
    public static let libraryCapabilities = [librarySearch, libraryGenerate]
}
