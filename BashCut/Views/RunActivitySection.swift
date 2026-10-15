import BashCutAutomation
import BashCutDocument
import SwiftUI

/// The run panel's live part (#534): what the agent waits on the user for, its recent steps with their state
/// (queued, running, done, failed), the other running jobs, and Stop. All of it is derived by the app from the
/// agent's requests and jobs; the agent reports nothing extra for it.
struct RunActivitySection: View {
    let document: ProjectDocument
    static let shownSteps = 8

    var body: some View {
        let activity = document.activity
        let steps = Array(activity.steps.suffix(Self.shownSteps))
        let linked = Set(activity.steps.compactMap(\.job))
        let jobs = document.jobs.jobs.filter { $0.isActive && !linked.contains($0.id) }
        VStack(alignment: .leading, spacing: 8) {
            if case .waiting(let wait) = activity.status { waitingCard(wait) }
            if !steps.isEmpty {
                Text("Steps").font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(steps) { step in stepRow(step, state: activity.state(of: step)) }
                    }
                }.frame(maxHeight: 170)
            }
            if !jobs.isEmpty {
                Text("Running jobs").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(jobs) { job in JobRow(document: document, job: job, showsMethod: true) }
            }
            if steps.isEmpty, jobs.isEmpty, document.runPanel.progress == nil {
                Text("No agent activity yet. Steps and jobs show here while an agent works.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Toggle("Follow", isOn: Binding(get: { activity.follow }, set: { _ in document.run(.toggleFollowAgent) }))
                    .toggleStyle(.checkbox).controlSize(.small)
                    .help("Scroll the timeline to where the agent works; scrolling it yourself turns this off")
                Spacer()
                if activity.canStop {
                    Button(role: .destructive) { document.run(.stopAgent) } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .controlSize(.small).help("Stop the agent: cancel its jobs and interrupt its turn")
                    .action(.stopAgent, in: document)
                }
            }
        }
    }

    @ViewBuilder private func waitingCard(_ wait: AgentStatus.Wait) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.bubble.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.waitText(wait)).font(.caption).fixedSize(horizontal: false, vertical: true)
                if case .question(let session) = wait {
                    Button("Show question") { document.activity.showQuestion(session) }.controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.orange.opacity(0.14)))
    }

    static func waitText(_ wait: AgentStatus.Wait) -> String {
        switch wait {
        case .question: String(localized: "The agent asked you a question and waits for the answer.")
        case .checkpoint: String(localized: "The agent waits for your approval at a gate.")
        case .scopeHold: String(localized: "An agent edit outside the attached clips waits for your answer.")
        case .approval: String(localized: "A privileged agent action waits for your approval.")
        }
    }

    private func stepRow(_ step: AgentStep, state: AgentStep.State) -> some View {
        let job = step.job.flatMap { document.jobs.job($0) }
        return HStack(spacing: 6) {
            Image(systemName: Self.icon(state)).foregroundStyle(Self.tint(state)).frame(width: 14)
            Text(step.method).font(.caption.monospaced()).lineLimit(1)
            if let detail = job?.detail { Text(detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            Spacer(minLength: 4)
            if !step.changed.isEmpty {
                Button { document.jumpToAgentItems(step.changed) } label: { Image(systemName: "arrow.right.circle") }
                    .buttonStyle(.plain).foregroundStyle(.cyan)
                    .help(String(format: String(localized: "Jump to the %d items this step changed"), step.changed.count))
            }
            if state == .running, let value = job?.progress {
                Text(value, format: .percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text(Self.stateName(state)).foregroundStyle(Self.tint(state))
            }
        }
        .font(.caption)
        .help(job?.error ?? step.error ?? "")
    }

    static func icon(_ state: AgentStep.State) -> String {
        switch state {
        case .queued: "clock"
        case .running: "circle.dotted.circle"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    static func tint(_ state: AgentStep.State) -> Color {
        switch state {
        case .queued: .secondary
        case .running: .cyan
        case .done: .green
        case .failed: .orange
        }
    }

    static func stateName(_ state: AgentStep.State) -> String {
        switch state {
        case .queued: String(localized: "Queued")
        case .running: String(localized: "Running")
        case .done: String(localized: "Done")
        case .failed: String(localized: "Failed")
        }
    }
}
