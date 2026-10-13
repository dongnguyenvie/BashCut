import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation
import Observation

/// One thing an agent did this session (#534): an edit, UI or privileged command it sent, or the job such a command
/// started. Reads are not steps; they only show the agent is working.
struct AgentStep: Identifiable, Equatable {
    enum State: String { case queued, running, done, failed }

    let id: UUID
    let method: String
    let author: Author
    let token: String?
    let startedAt: Date
    var endedAt: Date?
    /// The command's own state; a step with a job follows the job instead (`AgentActivityModel.state(of:)`).
    var state: State
    var job: String?
    var error: String?
    /// The items the command added or changed, for Jump and the flash (#534).
    var changed: [String] = []
}

/// What the toolbar's agent button shows (#534).
enum AgentStatus: Equatable {
    /// Why the agent waits for the user.
    enum Wait: Equatable {
        case question(UUID)
        case checkpoint
        case scopeHold
        case approval
    }

    case idle
    case working(String)
    case waiting(Wait)
    case finished
}

/// The agent's activity, derived by the app from the requests it sends, the jobs they start, the run log's stages
/// and the sessions' question cards (#534). Agents are never asked for anything extra: nothing here adds to a
/// command's result, `jobs status`, `timeline get` or the agent's instructions.
@MainActor @Observable final class AgentActivityModel {
    @ObservationIgnored unowned let document: ProjectDocument
    private(set) var steps: [AgentStep] = []
    private(set) var status: AgentStatus = .idle
    /// Requests still being handled.
    @ObservationIgnored private(set) var inFlight = 0
    /// When an agent last sent a request, and each session token's last request (Stop interrupts those).
    @ObservationIgnored private(set) var lastCall: Date?
    @ObservationIgnored private(set) var lastCallByToken: [String: Date] = [:]
    /// The revision each running request started at, so its step picks up only the changes it made.
    @ObservationIgnored private var running: [UUID: Int] = [:]

    static let stepLimit = 40
    /// An agent counts as working this long after its last request (it thinks between commands).
    static let recentWindow: TimeInterval = 20
    /// A stage the agent reported stays "working" this long without another stage entry or request.
    static let stageWindow: TimeInterval = 10 * 60
    /// Methods that are bookkeeping, not steps: run log entries and job polls.
    static let quietPrefixes = ["run.", "jobs.", "context.", "agent.status", "checkpoint.status"]

    init(document: ProjectDocument) { self.document = document }

    /// Called by the command registry as an agent request starts and ends.
    func record(_ activity: CommandActivity) {
        let now = Date()
        lastCall = now
        if let token = activity.token { lastCallByToken[token] = now }
        guard let finished = activity.finished else {
            inFlight += 1
            running[activity.id] = document.project.revision
            if Self.isStep(activity) {
                steps.append(AgentStep(
                    id: activity.id, method: activity.method, author: activity.author, token: activity.token,
                    startedAt: now, state: .running))
                if steps.count > Self.stepLimit { steps.removeFirst(steps.count - Self.stepLimit) }
            }
            refreshStatus(now: now)
            return
        }
        inFlight = max(0, inFlight - 1)
        let startRevision = running.removeValue(forKey: activity.id)
        if let index = steps.lastIndex(where: { $0.id == activity.id }) {
            steps[index].endedAt = now
            steps[index].state = finished ? .done : .failed
            steps[index].error = activity.error
            steps[index].job = activity.job
            if finished, let change = document.agentChange, change.command == activity.method,
                let startRevision, change.beforeRevision >= startRevision
            {
                steps[index].changed = change.changes.compactMap { $0.after == nil ? nil : $0.itemID }
            }
        }
        refreshStatus(now: now)
    }

    static func isStep(_ activity: CommandActivity) -> Bool {
        activity.mode != .read && !quietPrefixes.contains { activity.method.hasPrefix($0) }
    }

    /// A step's state, following its job while it has one.
    func state(of step: AgentStep) -> AgentStep.State {
        guard let id = step.job, let job = document.jobs.job(id) else { return step.state }
        switch job.state {
        case .queued: return .queued
        case .running: return .running
        case .completed: return .done
        case .failed, .cancelled: return .failed
        }
    }

    /// The jobs agents started that are still queued or running.
    var activeAgentJobs: [Job] { document.jobs.jobs.filter { $0.isActive && $0.author.isAgent } }

    /// Forgets the steps when another project opens.
    func reset() {
        steps.removeAll()
        refreshStatus()
    }

    /// Called every second by the editor and after each request.
    func refreshStatus(now: Date = Date()) {
        let next = computeStatus(now: now)
        if next != status { status = next }
    }

    private func computeStatus(now: Date) -> AgentStatus {
        if let wait = waiting { return .waiting(wait) }
        let progress = document.runPanel.progress
        let recent = lastCall.map { now.timeIntervalSince($0) < Self.recentWindow } ?? false
        let stageLive = progress?.current != nil
            && (progress?.lastActivity).map { now.timeIntervalSince($0) < Self.stageWindow } == true
        let chatting = document.chatAgents.all.contains(where: \.running)
        let jobs = activeAgentJobs
        if inFlight > 0 || recent || stageLive || chatting || !jobs.isEmpty {
            if let current = progress?.current, progress?.finished == false { return .working(RunPanelView.title(current)) }
            if let job = jobs.first { return .working(job.method) }
            if let step = steps.last { return .working(step.method) }
            return .working(String(localized: "Working"))
        }
        if progress?.finished == true { return .finished }
        return .idle
    }

    /// The first thing the agent waits on the user for: its question card, a gate, a held edit or an approval.
    private var waiting: AgentStatus.Wait? {
        if let session = document.agents.sessions.first(where: { $0.question != nil }) { return .question(session.id) }
        if document.checkpoint != nil { return .checkpoint }
        if document.scopeHold != nil { return .scopeHold }
        if document.privilegedApproval != nil { return .approval }
        return nil
    }

    /// Whether Stop has something to stop.
    var canStop: Bool {
        if case .working = status { return true }
        return !activeAgentJobs.isEmpty
    }

    /// Stop (`ui action run.stop`): cancels the agents' jobs, stops chat turns and interrupts the terminal agents that
    /// sent requests in the last two minutes (Escape, as a person would press it).
    func stop(now: Date = Date()) {
        for job in activeAgentJobs { document.jobs.cancel(job.id) }
        for chat in document.chatAgents.all where chat.running { chat.stop() }
        let live = Set(lastCallByToken.filter { now.timeIntervalSince($0.value) < 120 }.keys)
        for session in document.agents.sessions where live.contains(session.token) { session.interrupt() }
        lastCall = nil
        lastCallByToken.removeAll()
        refreshStatus(now: now)
        document.message = String(localized: "Stopped the agent")
    }

    /// Shows the agent's question card: the dock, on the tab that asks.
    func showQuestion(_ session: UUID) {
        document.ui.showAgentDock = true
        document.agents.chatPluginID = nil
        document.agents.selectedSession = session
    }
}
