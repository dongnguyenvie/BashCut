import AppKit
import BashCutAutomation
import BashCutProject
import BashCutStorage
import SwiftUI

/// The agent's run over the editor (#447): its stages, the current one with the agent's step text, progress and
/// time left, and the elapsed time, while the timeline keeps updating underneath. Once the run exported it becomes
/// the result card (#448). `run status` reads the same; the buttons are `ui action run.*` and `export.*`.
struct RunPanelView: View {
    let document: ProjectDocument
    let model: RunPanelModel

    var body: some View {
        if let progress = model.progress {
            VStack(alignment: .leading, spacing: 10) {
                header(progress)
                if !model.collapsed {
                    if let result = model.result, progress.finished {
                        RunResultCard(document: document, model: model, result: result)
                    } else {
                        stages(progress)
                    }
                }
            }
            .padding(12)
            .frame(width: 320, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.3)))
            .shadow(radius: 8)
            .padding(.horizontal, 14).padding(.top, 14)
        }
    }

    private func header(_ progress: RunProgress) -> some View {
        HStack(spacing: 8) {
            Image(systemName: progress.finished ? "checkmark.seal.fill" : "wand.and.stars")
                .foregroundStyle(progress.finished ? .green : .cyan)
            Text(progress.finished ? "Agent run finished" : "Agent run").font(.callout.bold())
            Spacer()
            SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.clock(progress.elapsed(now: context.date))).font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary).help("Elapsed time")
            }
            Button { model.collapsed.toggle() } label: {
                Image(systemName: model.collapsed ? "chevron.down" : "chevron.up")
            }.buttonStyle(.plain).help(model.collapsed ? "Expand" : "Collapse")
            Button { document.run(.dismissRunPanel) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Close until the next run")
        }
    }

    @ViewBuilder private func stages(_ progress: RunProgress) -> some View {
        if let current = progress.current {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title(current)).font(.callout.bold())
                if let text = progress.text { Text(text).font(.caption).lineLimit(2) }
                if let value = progress.progress { ProgressView(value: value) }
                SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        if let seconds = progress.stageElapsed(now: context.date) {
                            Text(String(format: String(localized: "%@ in this stage"), Self.clock(seconds)))
                        }
                        Spacer()
                        if let left = progress.remaining(now: context.date) {
                            Text(String(format: String(localized: "about %@ left"), Self.clock(left)))
                        }
                    }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        VStack(alignment: .leading, spacing: 3) {
            ForEach(progress.stages, id: \.id) { stage in
                HStack(spacing: 6) {
                    Image(systemName: Self.icon(stage.status)).foregroundStyle(Self.tint(stage.status)).frame(width: 14)
                    Text(Self.title(stage.id)).fontWeight(stage.status == .active ? .semibold : .regular)
                        .foregroundStyle(stage.status == .pending ? .secondary : .primary)
                    Spacer()
                    if let start = stage.startedAt, let end = stage.endedAt {
                        Text(Self.clock(end.timeIntervalSince(start))).monospacedDigit().foregroundStyle(.secondary)
                    }
                }.font(.caption)
            }
        }
    }

    static func icon(_ status: RunProgress.Status) -> String {
        switch status {
        case .pending: "circle"
        case .active: "circle.dotted.circle"
        case .started: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        }
    }

    static func tint(_ status: RunProgress.Status) -> Color {
        switch status {
        case .pending, .skipped: .secondary
        case .active, .started: .cyan
        case .done: .green
        }
    }

    /// A stage's name for people; a stage only a plan or plugin knows keeps its ID.
    static func title(_ id: String) -> String {
        let titles: [String: String.LocalizationValue] = [
            "intake": "Brief", "survey": "Survey footage", "story": "Story", "rough-cut": "Cut", "rhythm": "Rhythm",
            "voiceover": "Voiceover", "sound": "Sound", "captions": "Captions", "colour": "Color", "effects": "Effects",
            "review": "Review", "export": "Export", "learn": "Learn",
        ]
        return titles[id].map { String(localized: $0) } ?? id
    }

    /// `m:ss`, or `h:mm:ss` past an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let (hours, minutes, rest) = (total / 3_600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}

/// The result card (#448): the newest export's still, duration, loudness and cuts, the review issues left, every
/// file the run wrote, and what to do next.
struct RunResultCard: View {
    let document: ProjectDocument
    let model: RunPanelModel
    let result: RunResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                thumbnail
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    row("Duration", RunPanelView.clock(result.main.duration))
                    row("Loudness", loudness)
                    row("Cuts", result.cuts.formatted())
                    GridRow {
                        Text("Issues left").foregroundStyle(.secondary)
                        Text(issues).foregroundStyle(result.errors > 0 ? .orange : result.warnings > 0 ? .yellow : .green)
                    }
                }.font(.caption)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(result.outputs, id: \.path) { output in
                    HStack(spacing: 4) {
                        Image(systemName: "film").foregroundStyle(.secondary)
                        Text(URL(fileURLWithPath: output.path).lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            do { try document.revealExport(output.path) } catch { document.message = error.localizedDescription }
                        } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.plain).help("Reveal in Finder")
                            .disabled(!FileManager.default.fileExists(atPath: output.path))
                    }.font(.caption)
                }
            }
            HStack {
                Button("Open") { document.run(.openExportOutput) }.action(.openExportOutput, in: document)
                Button("Reveal") { document.run(.revealExportOutput) }.action(.revealExportOutput, in: document)
                Spacer()
                Button("Export another format…") { document.run(.showExport) }.action(.showExport, in: document)
            }.controlSize(.small)
            HStack {
                Button(result.issuesLeft > 0
                    ? String(format: String(localized: "Fix %d remaining issues"), result.issuesLeft)
                    : String(localized: "No issues left")) { document.run(.fixRunIssues) }
                    .action(.fixRunIssues, in: document)
                Spacer()
                Button("Try another recipe") { document.run(.tryAnotherRecipe) }.action(.tryAnotherRecipe, in: document)
            }.controlSize(.small)
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = model.thumbnail {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(maxWidth: 110, maxHeight: 110).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)).frame(width: 110, height: 62)
                .overlay(Image(systemName: "film").foregroundStyle(.secondary))
        }
    }

    private var loudness: String {
        guard let lufs = result.main.integratedLUFS else { return String(localized: "Not measured") }
        return lufs.formatted(.number.precision(.fractionLength(1))) + " LUFS"
    }

    private var issues: String {
        String(format: String(localized: "%d errors, %d warnings"), result.errors, result.warnings)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
