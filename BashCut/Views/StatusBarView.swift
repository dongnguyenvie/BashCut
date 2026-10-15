import BashCutDocument
import BashCutProject
import SwiftUI

/// The status bar (P1-5), in three parts: the selection summary, the project length and a jobs indicator that opens
/// the running jobs. A one-off notice (`document.message`) shows between them and clears itself after 8 s.
struct StatusBarView: View {
    @Bindable var document: ProjectDocument
    @State private var showJobs = false
    /// How long a notice stays.
    static let noticeSeconds = 8

    var body: some View {
        let jobs = document.activeJobs
        HStack(spacing: 14) {
            Text(verbatim: document.selectionSummary).foregroundStyle(.secondary).lineLimit(1)
            if !document.message.isEmpty {
                Text(document.message).lineLimit(2).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if document.fileURL != nil {
                Text(String(format: String(localized: "Length %@"), Timecode.string(document.project.duration, fps: document.project.fps)))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            if !jobs.isEmpty { jobsButton(jobs) }
        }
        .font(.caption).padding(6)
        .task(id: document.message) {
            // The notice clears unless a newer one replaced it in the meantime (this task is then cancelled).
            guard !document.message.isEmpty else { return }
            try? await Task.sleep(for: .seconds(Self.noticeSeconds))
            if !Task.isCancelled { document.message = "" }
        }
    }

    private func jobsButton(_ jobs: [Job]) -> some View {
        Button {
            showJobs.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill").font(.system(size: 8))
                Text(jobs.count == 1 ? String(localized: "1 job") : String(format: String(localized: "%lld jobs"), jobs.count))
                if jobs.count == 1, let value = jobs[0].progress {
                    Text(value, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
            }.foregroundStyle(.cyan)
        }
        .buttonStyle(.plain).help("Running jobs")
        .popover(isPresented: $showJobs, arrowEdge: .top) {
            JobsPopover(document: document)
        }
    }
}

/// The running jobs, each with progress, Open and Cancel.
private struct JobsPopover: View {
    let document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Running jobs").font(.caption.bold()).foregroundStyle(.secondary)
            let jobs = document.activeJobs
            if jobs.isEmpty {
                Text("No jobs are running.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(jobs) { job in JobRow(document: document, job: job) }
        }.padding(12).frame(width: 340)
    }
}
