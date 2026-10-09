import BashCutProject
import SwiftUI

/// The project's selects in the Media panel (P1-D8): what the agent proposed, with its quote and reason, for the user
/// to keep, reject or mark must-keep, and to place the kept ones on Main.
struct SelectsListView: View {
    let document: ProjectDocument

    private var selects: [ProjectSelect] { document.project.selects.sorted { ($0.order, $0.from) < ($1.order, $1.from) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let kept = selects.filter { $0.status == "kept" }
                Text("\(kept.count) kept of \(selects.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Place kept") { place(kept) }.disabled(kept.isEmpty).font(.caption)
            }
            if selects.isEmpty {
                Text("No selects yet. Agents propose them with selects set.").foregroundStyle(.secondary).font(.caption)
            }
            ForEach(selects, id: \.id) { select in row(select) }
        }
    }

    private func row(_ select: ProjectSelect) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon(select.status)).foregroundStyle(tint(select.status))
                Text(verbatim: mediaName(select.media)).font(.caption2.bold()).lineLimit(1)
                Text(verbatim: String(format: "%.1f–%.1f s", select.from, select.to))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button { mark(select, mustKeep: !select.mustKeep) } label: {
                    Image(systemName: select.mustKeep ? "star.fill" : "star")
                }.buttonStyle(.plain).help("Must keep")
            }
            if let quote = select.quote { Text(verbatim: "“\(quote)”").font(.caption).lineLimit(2) }
            if let reason = select.reason { Text(verbatim: reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            if let statusReason = select.statusReason {
                Text(verbatim: "→ " + statusReason).font(.caption2.italic()).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 6) {
                Button("Keep") { mark(select, status: "kept") }.disabled(select.status == "kept")
                Button("Reject") { mark(select, status: "rejected") }.disabled(select.status == "rejected")
                Button("Preview") { preview(select) }
            }.font(.caption2)
        }
        .padding(6).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func icon(_ status: String) -> String {
        switch status {
        case "kept": "checkmark.circle.fill"
        case "rejected": "xmark.circle"
        default: "circle.dashed"
        }
    }

    private func tint(_ status: String) -> Color {
        switch status {
        case "kept": .green
        case "rejected": .secondary
        default: .orange
        }
    }

    private func mediaName(_ id: String) -> String {
        document.project.media.first { $0.id == id }.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? id
    }

    private func mark(_ select: ProjectSelect, status: String? = nil, mustKeep: Bool? = nil) {
        do {
            let all = try document.project.markingSelects([select.id], status: status, mustKeep: mustKeep, reason: nil)
            _ = try document.saveSelects(all, label: "Mark select", author: .user, base: nil)
        } catch {
            document.message = error.localizedDescription
        }
    }

    private func place(_ kept: [ProjectSelect]) {
        do { try document.placeSelects(kept, at: nil) } catch { document.message = error.localizedDescription }
    }

    private func preview(_ select: ProjectSelect) {
        guard let media = document.project.media.first(where: { $0.id == select.media }) else { return }
        document.previewSource(media)
    }
}
