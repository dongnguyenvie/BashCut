import BashCutPlugin
import BashCutProject
import SwiftUI

/// A `split` component (API 11): two or three columns side by side, each `widths` entry a width in points or `"flex"`.
/// Narrower than `PluginViewTree.splitCollapseWidth`, the fixed columns fold into disclosures above and below the
/// flexible ones. With `fills` (the split is the whole view of a window, sheet or dock tab) it takes the height it is
/// given and each column scrolls on its own.
struct PluginSplitView: View {
    let node: PluginViewNode
    @Bindable var model: PluginViewModel
    var fills = false
    @State private var width: CGFloat?

    private enum Width: Equatable {
        case fixed(CGFloat)
        case flex
    }

    private var widths: [Width] {
        let given = node.array("widths")
        return node.children.indices.map { index in
            guard given.indices.contains(index), let points = given[index].double else { return .flex }
            let range = PluginViewTree.splitColumnWidths
            return .fixed(CGFloat(min(max(points, range.lowerBound), range.upperBound)))
        }
    }

    private var collapsed: Bool { (width ?? .infinity) < PluginViewTree.splitCollapseWidth }

    var body: some View {
        Group {
            if collapsed { stacked } else { columns }
        }
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var columns: some View {
        let widths = widths
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                if index > 0 { Divider() }
                let column = column(child)
                switch widths[index] {
                case .fixed(let points): column.frame(width: points)
                case .flex: column.frame(minWidth: 200, maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder private func column(_ child: PluginViewNode) -> some View {
        if fills {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) { PluginNodeView(node: child, model: model) }.padding(10)
            }.frame(maxHeight: .infinity)
        } else {
            PluginNodeView(node: child, model: model).padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// Too narrow for columns: the fixed columns before the first flexible one fold above it, the rest below.
    @ViewBuilder private var stacked: some View {
        let widths = widths
        let content = VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                if widths[index] == .flex {
                    PluginNodeView(node: child, model: model)
                } else {
                    PluginSplitFold(node: child, model: model)
                }
            }
        }.padding(fills ? 10 : 0)
        if fills {
            ScrollView { content }
        } else {
            content
        }
    }
}

/// A fixed `split` column folded into a disclosure in a narrow host; titled by the column's `title` (or `label`).
private struct PluginSplitFold: View {
    let node: PluginViewNode
    let model: PluginViewModel
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            PluginNodeView(node: node, model: model).padding(.top, 4)
        } label: {
            if let title = node.string("title") ?? node.string("label") {
                Text(verbatim: title).font(.caption.bold())
            } else {
                Text("More options").font(.caption.bold())
            }
        }
    }
}

/// A `nav` component (API 11): groups of entries with an icon and a count; clicking one sends `select` with its id.
/// The clicked entry shows as selected at once, until the plugin's answer sets `value`.
struct PluginNavView: View {
    let node: PluginViewNode
    @Bindable var model: PluginViewModel
    @State private var pending: String?

    var body: some View {
        let selected = pending ?? node.string("value")
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(node.array("groups").prefix(PluginViewTree.maximumNavGroups).enumerated()), id: \.offset) { index, group in
                let fields = group.object
                if let title = fields["title"]?.string {
                    Text(verbatim: title).font(.caption.bold()).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.top, index == 0 ? 0 : 8).padding(.bottom, 2)
                }
                ForEach(Array((fields["items"]?.array ?? []).enumerated()), id: \.offset) { _, entry in
                    row(entry.object, selected: selected)
                }
            }
        }
        .onChange(of: node.string("value")) { pending = nil }
    }

    private func row(_ entry: [String: JSONValue], selected: String?) -> some View {
        let id = entry["id"]?.string ?? ""
        let isSelected = id == selected
        return Button {
            pending = id
            model.send(PluginViewEvent(node: node.id, kind: .select, value: .string(id)))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry["icon"]?.string ?? "circle.dashed").frame(width: 18)
                    .foregroundStyle(isSelected ? Color.cyan : .secondary)
                Text(verbatim: entry["title"]?.string ?? id).lineLimit(1)
                Spacer(minLength: 4)
                if let count = Self.count(entry["count"]) {
                    Text(verbatim: count).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .background(isSelected ? Color.cyan.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entry["disabled"]?.bool ?? false)
    }

    private static func count(_ value: JSONValue?) -> String? {
        if let number = value?.int { return "\(number)" }
        return value?.string
    }
}
