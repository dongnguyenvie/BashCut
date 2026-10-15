import BashCutAgent
import SwiftUI

/// The agent's idle area: a line about the project, quick-start cards for its state (the first one wide) and
/// All templates, which opens the New brief sheet. A card puts its filled request in the agent's input.
struct BriefQuickStartView: View {
    @Bindable var model: AgentDockModel

    private var state: BriefFit { model.briefState }
    private var cards: [BriefTemplate] { BriefCatalog.quickStarts(for: state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hello).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(heading).font(.caption2.monospaced()).foregroundStyle(.tertiary).padding(.top, 2)
            VStack(spacing: 6) {
                ForEach(rows, id: \.first?.id) { row in
                    HStack(spacing: 6) {
                        ForEach(row) { template in
                            BriefCard(template: template, wide: row.count == 1) { model.insert(template) }
                        }
                    }
                }
            }
            Button {
                model.openBrief()
            } label: {
                Text(String(format: String(localized: "All templates (%d) →"), BriefCatalog.all.count))
            }
            .buttonStyle(.link).font(.callout)
            .help("Open New brief with every template")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The first card alone, then pairs; an odd card left at the end takes the row too.
    private var rows: [[BriefTemplate]] {
        guard let first = cards.first else { return [] }
        var rows = [[first]]
        var rest = Array(cards.dropFirst())
        while !rest.isEmpty {
            rows.append(Array(rest.prefix(2)))
            rest = Array(rest.dropFirst(2))
        }
        return rows
    }

    private var heading: String {
        let name = model.document.fileURL == nil ? "" : model.document.project.name
        return name.isEmpty
            ? String(localized: "SUGGESTED")
            : String(format: String(localized: "SUGGESTED FOR %@"), name.uppercased())
    }

    private var hello: String {
        switch state {
        case .none:
            String(localized: "No footage yet? The agent can still make an explainer or a news video from a topic and sources.")
        case .footage: String(localized: "Footage not edited yet. Start from a template, or ask the agent to survey it first.")
        case .talk: String(localized: "One long talk video. It can become several short clips.")
        case .timeline: String(localized: "There is an edit already. Fix it, finish it, or export it.")
        case .selection: String(localized: "A clip is selected. The request applies only to that part.")
        }
    }
}

private struct BriefCard: View {
    let template: BriefTemplate
    let wide: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if wide {
                    HStack(spacing: 10) {
                        icon
                        text
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        icon
                        text
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovered ? 0.08 : 0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(wide ? Color.cyan.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(template.prompt())
        .accessibilityLabel(template.title)
    }

    private var icon: some View {
        Image(systemName: template.systemImage).font(.system(size: 15)).foregroundStyle(.cyan).frame(width: 20)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(template.title).font(.callout.weight(.semibold)).lineLimit(1)
            Text(template.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
