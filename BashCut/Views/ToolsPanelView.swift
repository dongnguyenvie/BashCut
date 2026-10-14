import BashCutDocument
import SwiftUI

/// The Tools panel (P1-4): the list of tools on top and the selected tool's card under it. The built-in tools (Auto
/// captions, Voiceover, Beat detection) come first, then the plugins' `kind: tool` views and `tools` actions.
struct ToolsPanelView: View {
    @Bindable var document: ProjectDocument
    @Bindable var pluginManager: PluginManagerModel

    var body: some View {
        let tools = document.toolEntries
        let selected = document.selectedTool
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 2) {
                ForEach(tools) { tool in toolRow(tool, selected: tool.id == selected?.id) }
            }
            Divider()
            if let selected { toolContent(selected).id(selected.id) }
        }
    }

    private func toolRow(_ tool: ToolListEntry, selected: Bool) -> some View {
        Button {
            document.ui.selectedTool = tool.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tool.icon).frame(width: 18)
                Text(verbatim: tool.title).lineLimit(1)
                Spacer(minLength: 4)
                if let provider = tool.provider {
                    Text(verbatim: provider).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(selected ? Color.cyan.opacity(0.14) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).foregroundStyle(selected ? Color.cyan : Color.primary)
        .accessibilityIdentifier("tool-" + tool.id)
    }

    @ViewBuilder private func toolContent(_ tool: ToolListEntry) -> some View {
        switch tool.source {
        case .native:
            switch tool.id {
            case ToolID.captions: CaptionsToolCard(document: document, pluginManager: pluginManager)
            case ToolID.beats: BeatsToolCard(document: document, pluginManager: pluginManager)
            default:
                VoiceToolCard(document: document, pluginManager: pluginManager)
                PluginActionStrip(document: document, placement: "panel.voice")
            }
        case .view(let key):
            if let model = document.pluginViews.model(key: key) { PluginToolViewCard(model: model, entry: tool) }
        case .action(let id):
            if let action = document.plugins.action(id) { PluginToolCard(document: document, action: action) }
        }
    }
}
