import BashCutPlugin
import SwiftUI

/// The install approval's Skills part (#506): what installing or updating changes in the skills agents will read, with
/// lines that run commands, point to links or tell the agent to ignore its instructions flagged, so the user reads
/// those before trusting the plugin.
struct PluginSkillReviewSection: View {
    let pending: PendingPluginInstall
    /// The installed copy an update replaces, to compare against.
    let installed: InstalledPlugin?
    let model: PluginManagerModel
    @State private var review: PluginSkillReview?

    var body: some View {
        Group {
            if let review, !review.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Skills for agents").font(.headline)
                        Spacer()
                        if review.flaggedCount > 0 {
                            Label(String(format: String(localized: "%lld lines to check"), review.flaggedCount),
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    ForEach(review.skills, id: \.name) { skill in skillRow(skill) }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.04)).cornerRadius(6)
            }
        }
        .task(id: pending.id) {
            let (plugin, installed) = (pending.plugin, installed)
            let result = await Task.detached(priority: .userInitiated) {
                PluginSkillReview(
                    old: installed.map(PluginSkillReview.texts(of:)) ?? [:], new: PluginSkillReview.texts(of: plugin))
            }.value
            review = result
            model.skillReviews[pending.id] = result
        }
    }

    private func skillRow(_ skill: PluginSkillReview.Skill) -> some View {
        DisclosureGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    // Flagged lines first, then the rest of the change.
                    ForEach(Array((skill.flagged + skill.lines.filter { $0.flags.isEmpty || !$0.added }).enumerated()),
                            id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 4) {
                            Text(verbatim: line.added ? "+" : "−").foregroundStyle(line.added ? .green : .red)
                            Text(verbatim: line.text).textSelection(.enabled)
                            if !line.flags.isEmpty {
                                Spacer(minLength: 4)
                                Text(verbatim: line.flags.map(\.rawValue).joined(separator: ", "))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.caption.monospaced())
                        .background(line.flags.isEmpty ? Color.clear : Color.orange.opacity(0.12))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 180)
        } label: {
            HStack {
                Text(verbatim: skill.name).bold()
                Text(LocalizedStringKey(skill.change)).font(.caption).foregroundStyle(.secondary)
                if !skill.flagged.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                }
            }
        }
    }
}
