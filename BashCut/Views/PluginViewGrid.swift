import AppKit
import BashCutPlugin
import BashCutProject
import SwiftUI

/// A `grid` component (`views.grid`): tiles of `list`-style items (lazy, so long grids cost only the tiles on screen).
/// A tile shows a thumbnail (or an SF Symbol), a badge, an audio preview, a title, a subtitle and up to three buttons;
/// `selected` is one item id or an array of them, and `more` draws a load-more button under the grid.
struct PluginGridView: View {
    let node: PluginViewNode
    @Bindable var model: PluginViewModel

    var body: some View {
        let items = Array(node.array("items").prefix(PluginViewTree.maximumListItems))
        let width = min(max(node.double("cellWidth") ?? 120, 64), 320)
        let aspect = min(max(node.double("aspect") ?? 1, 0.3), 3)
        let selected = selectedIDs
        VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty, let empty = node.string("empty") {
                Text(verbatim: empty).font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: width), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    PluginGridCell(
                        item: item.object, aspect: aspect, selected: selected, gridID: node.id, gridDrag: node.string("drag"),
                        model: model)
                }
            }
            if let more = node.string("more") {
                Button {
                    model.send(PluginViewEvent(node: node.id, kind: .click, value: .string("more")))
                } label: {
                    Text(verbatim: more).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private var selectedIDs: Set<String> {
        switch node.props["selected"] {
        case .string(let id)?: [id]
        case .array(let ids)?: Set(ids.compactMap(\.string))
        default: []
        }
    }
}

private struct PluginGridCell: View {
    let item: [String: JSONValue]
    let aspect: Double
    let selected: Set<String>
    let gridID: String
    /// The grid's `drag`; an item's own `drag` wins.
    let gridDrag: String?
    @Bindable var model: PluginViewModel
    @State private var image: NSImage?

    /// A tile with `drag: "download"` (API 11) that is not in the library yet drags as a download: dropped on the
    /// timeline, the plugin downloads it and the host places the library item it answers with.
    private var download: PluginViewDrag.Download? {
        guard (item["drag"]?.string ?? gridDrag) == "download", let id = item["id"]?.string else { return nil }
        return PluginViewDrag.Download(plugin: model.pluginID, view: model.viewID, node: gridID, item: id)
    }

    var body: some View {
        let id = item["id"]?.string ?? ""
        let isSelected = selected.contains(id)
        VStack(alignment: .leading, spacing: 3) {
            thumbnail
            if let title = item["title"]?.string {
                Text(verbatim: title).font(.caption).lineLimit(1)
            }
            if let subtitle = item["subtitle"]?.string {
                Text(verbatim: subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            let actions = Array((item["actions"]?.array ?? []).prefix(3))
            if !actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in actionButton(action.object, item: id) }
                }.font(.caption)
            }
        }
        .padding(4)
        .background(isSelected ? Color.cyan.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.cyan : .clear, lineWidth: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.send(PluginViewEvent(node: gridID, kind: .select, value: .string(id))) }
        .pluginFileDrag(item["file"]?.string, library: item["libraryItem"]?.string, download: download)
    }

    private var thumbnail: some View {
        Color.secondary.opacity(0.12)
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if let icon = item["icon"]?.string {
                    Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .topTrailing) {
                if let badge = item["badge"]?.string {
                    let color = PluginNodeView.color(item["badgeColor"]?.string, fallback: .secondary)
                    Text(verbatim: badge).font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.regularMaterial, in: Capsule())
                        .foregroundStyle(color)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let audio = item["audio"]?.string {
                    PluginAudioButton(path: audio, title: nil, compact: true)
                        .frame(width: 22, height: 22)
                        .background(.regularMaterial, in: Circle())
                        .padding(4)
                }
            }
            .task(id: item["image"]?.string) {
                guard let path = item["image"]?.string else { image = nil; return }
                image = PluginImages.cached(path)
                if image == nil { image = await PluginImages.load(path) }
            }
    }

    private func actionButton(_ fields: [String: JSONValue], item id: String) -> some View {
        Button {
            model.send(PluginViewEvent(node: gridID, kind: .action, value: .object([
                "item": .string(id), "action": fields["id"] ?? .null,
            ])))
        } label: {
            if let icon = fields["icon"]?.string { Image(systemName: icon) } else {
                Text(verbatim: fields["title"]?.string ?? "")
            }
        }
        .buttonStyle(.borderless).help(fields["title"]?.string ?? "")
    }
}
