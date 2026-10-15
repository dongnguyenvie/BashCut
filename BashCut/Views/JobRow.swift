import BashCutDocument
import SwiftUI

/// One running job: its name, the current step, progress, Open and Cancel. The run panel lists the jobs an agent
/// started with it, and the status bar's jobs popover lists all of them.
struct JobRow: View {
    let document: ProjectDocument
    let job: Job
    /// The run panel shows the command name (`captions.generate`); the status bar a friendly title.
    var showsMethod = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: RunActivitySection.icon(job.state == .queued ? .queued : .running))
                .foregroundStyle(.cyan).frame(width: 14)
            if showsMethod {
                Text(job.method).font(.caption.monospaced()).lineLimit(1)
            } else {
                Text(verbatim: document.jobTitle(job)).lineLimit(1)
            }
            if let detail = job.detail, detail != job.method {
                Text(detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if let value = job.progress {
                ProgressView(value: value).frame(width: 50)
            } else {
                Text(job.state == .queued ? RunActivitySection.stateName(.queued) : RunActivitySection.stateName(.running))
                    .foregroundStyle(.secondary)
            }
            if !showsMethod {
                Button { document.openJob(job) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Open where this job runs")
            }
            Button { document.jobs.cancel(job.id) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Cancel this job")
        }.font(.caption)
    }
}
