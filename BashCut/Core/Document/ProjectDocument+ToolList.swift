import BashCutDocument
import BashCutPlugin
import Foundation

/// One entry of the Tools list (P1-3): a built-in tool, a plugin's `kind: tool` view or a plugin action placed in
/// `tools`. The Tools panel shows the list and the selected tool under it.
struct ToolListEntry: Identifiable, Equatable {
    enum Source: Equatable {
        case native
        /// `<plugin>/<view>`
        case view(String)
        /// A plugin action id.
        case action(String)
    }

    let id: String
    let title: String
    let icon: String
    /// The plugin that provides the tool, nil for the built-in ones.
    let provider: String?
    let source: Source
}

extension ProjectDocument {
    /// The built-in tools, then the plugin tools: views with `kind: tool`, then actions placed in `tools`.
    /// Plugins that are not ready, or are samples while Developer mode is off, add nothing.
    var toolEntries: [ToolListEntry] {
        var list = [
            ToolListEntry(id: ToolID.captions, title: String(localized: "Auto captions"), icon: "captions.bubble", provider: nil, source: .native),
            ToolListEntry(id: ToolID.voice, title: String(localized: "Voiceover"), icon: "waveform", provider: nil, source: .native),
            ToolListEntry(id: ToolID.beats, title: String(localized: "Beat detection"), icon: "metronome", provider: nil, source: .native),
        ]
        for entry in pluginViews.toolViews {
            list.append(ToolListEntry(
                id: entry.key, title: entry.view.title.text,
                icon: entry.view.icon ?? entry.plugin.manifest.container?.icon ?? "puzzlepiece.extension",
                provider: entry.plugin.manifest.displayName, source: .view(entry.key)))
        }
        for action in plugins.actions(at: PluginActionContribution.toolsPlacement) {
            list.append(ToolListEntry(
                id: action.id, title: action.title, icon: action.spec.icon ?? "play",
                provider: action.plugin.manifest.displayName, source: .action(action.id)))
        }
        return list
    }

    /// The tool the Tools panel shows: the chosen one while it still exists, else the first.
    var selectedTool: ToolListEntry? {
        let list = toolEntries
        return list.first { $0.id == ui.selectedTool } ?? list.first
    }
}
