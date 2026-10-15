import BashCutAgent
import SwiftUI

/// The New brief sheet's list: Recent (sent in this project), Saved (the user's own templates), then the template
/// groups. Templates that suit the project carry FITS and come first; the others are dimmed but can be picked.
struct BriefListView: View {
    @Bindable var ask: AgentAskModel
    let state: BriefFit

    private var recent: [BriefRecord] { ask.recent.filter(matches) }
    private var saved: [BriefRecord] { ask.saved.filter(matches) }
    private var sections: [(group: BriefGroup, templates: [BriefTemplate])] {
        BriefCatalog.sections(for: state, query: ask.search)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if !recent.isEmpty {
                    heading(String(localized: "RECENT"))
                    ForEach(recent) { record in
                        row(record.title, systemImage: "clock", selected: ask.recordID == record.id) { ask.pick(record) }
                            .help(record.prompt)
                    }
                }
                if !saved.isEmpty {
                    heading(String(localized: "SAVED"))
                    ForEach(saved) { record in
                        row(record.title, systemImage: "star", selected: ask.recordID == record.id) { ask.pick(record) }
                            .help(record.prompt)
                            .contextMenu {
                                Button("Remove from Saved") { removeSaved(record) }
                            }
                    }
                }
                ForEach(sections, id: \.group) { section in
                    heading(section.group.title.uppercased(), count: section.templates.count)
                    ForEach(section.templates) { template in
                        row(template.title, systemImage: template.systemImage,
                            selected: ask.recordID == nil && ask.templateID == template.id,
                            fits: template.fits(state)) { ask.pick(template) }
                            .help(template.detail)
                    }
                }
                if sections.isEmpty, recent.isEmpty, saved.isEmpty {
                    Text(String(format: String(localized: "No template for “%@”"), ask.search))
                        .font(.caption).foregroundStyle(.secondary).padding(12)
                }
            }.padding(8)
        }
    }

    private func matches(_ record: BriefRecord) -> Bool {
        let query = BriefText.normalize(ask.search).trimmingCharacters(in: .whitespaces)
        return query.isEmpty || BriefText.normalize(record.title + " " + record.prompt).contains(query)
    }

    private func removeSaved(_ record: BriefRecord) {
        ask.saved.removeAll { $0.id == record.id }
        BriefHistory.storeSaved(ask.saved)
    }

    private func heading(_ title: String, count: Int? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let count { Text("\(count)") }
        }
        .font(.caption2.monospaced().bold()).foregroundStyle(.tertiary)
        .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
    }

    private func row(
        _ title: String, systemImage: String, selected: Bool, fits: Bool? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 18).foregroundStyle(selected ? Color.cyan : .secondary)
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if fits == true { BriefFitBadge() }
            }
            .opacity(fits == false ? 0.5 : 1)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.cyan.opacity(0.18) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
