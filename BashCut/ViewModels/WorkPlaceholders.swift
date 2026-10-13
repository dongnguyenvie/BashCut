import BashCutDocument
import BashCutProject
import Foundation
import Observation

/// Where a job's result will land (#534), worked out by the app from the command that started it: a timeline lane and
/// range, or the media it works on. UI state only: never saved in the project and never exported.
struct PlaceholderTarget: Equatable {
    var kind: WorkPlaceholder.Kind
    var label: String
    var trackID: String?
    var frames: Range<Int>?
    var mediaIDs: [String] = []
}

/// A block being made (#534): a voiceover take, a graphic, media importing or converting, or captions being
/// transcribed, shown at once and filled in when its job ends. A failed one stays with Retry and Remove.
struct WorkPlaceholder: Identifiable, Equatable {
    enum Kind: String { case voiceover, graphic, media, captions }

    let id: String
    let target: PlaceholderTarget
    let state: Job.State
    let progress: Double?
    /// Active jobs of the same command ahead of this one in the queue.
    let ahead: Int
    let error: String?
    let canRetry: Bool

    var failed: Bool { state == .failed }
    var onTimeline: Bool { target.trackID != nil && target.frames != nil }

    /// "Voiceover · queued, 1 ahead", "Graphic · rendering 40%", "Captions · failed".
    var title: String {
        let state: String
        switch self.state {
        case .queued:
            state = ahead > 0 ? String(format: String(localized: "queued, %d ahead"), ahead) : String(localized: "queued")
        case .failed: state = String(localized: "failed")
        default:
            let verb = Self.verb(target.kind)
            state = progress.map { verb + " " + $0.formatted(.percent.precision(.fractionLength(0))) } ?? verb
        }
        return Self.kindName(target.kind) + " · " + state
    }

    static func kindName(_ kind: Kind) -> String {
        switch kind {
        case .voiceover: String(localized: "Voiceover")
        case .graphic: String(localized: "Graphic")
        case .media: String(localized: "Media")
        case .captions: String(localized: "Captions")
        }
    }

    static func verb(_ kind: Kind) -> String {
        switch kind {
        case .voiceover: String(localized: "speaking")
        case .graphic: String(localized: "rendering")
        case .media: String(localized: "converting")
        case .captions: String(localized: "transcribing")
        }
    }
}

/// The placeholders of the jobs running now (#534): targets registered when a job starts, joined with the job
/// center's state. Media conversions and proxies need no registration: their job names the file.
@MainActor @Observable final class WorkPlaceholders {
    typealias Retry = @MainActor () async throws -> String?

    @ObservationIgnored unowned let document: ProjectDocument
    private var targets: [String: PlaceholderTarget] = [:]
    @ObservationIgnored private var retries: [String: Retry] = [:]
    private var removed: Set<String> = []
    static let mediaMethods: Set<String> = ["media.convert", "media.proxy"]

    init(document: ProjectDocument) { self.document = document }

    func track(_ job: String, _ target: PlaceholderTarget, retry: Retry? = nil) {
        targets[job] = target
        retries[job] = retry
    }

    func reset() {
        targets.removeAll()
        retries.removeAll()
        removed.removeAll()
    }

    /// Placeholders for queued, running and failed jobs, oldest first.
    var items: [WorkPlaceholder] {
        let jobs = document.jobs.jobs
        return jobs.compactMap { job in
            guard [.queued, .running, .failed].contains(job.state), !removed.contains(job.id),
                let target = targets[job.id] ?? mediaTarget(job)
            else { return nil }
            let ahead = jobs.filter { $0.method == job.method && $0.isActive && $0.createdAt < job.createdAt }.count
            return WorkPlaceholder(
                id: job.id, target: target, state: job.state, progress: job.progress, ahead: job.state == .queued ? ahead : 0,
                error: job.error, canRetry: retries[job.id] != nil)
        }
    }

    /// A conversion or proxy job's media, found by the file name the job carries.
    private func mediaTarget(_ job: Job) -> PlaceholderTarget? {
        guard Self.mediaMethods.contains(job.method), let name = job.detail else { return nil }
        let ids = document.project.media.filter { URL(fileURLWithPath: $0.path).lastPathComponent == name }.map(\.id)
        guard !ids.isEmpty else { return nil }
        return PlaceholderTarget(kind: .media, label: name, mediaIDs: ids)
    }

    /// The placeholder working on `media`, for its library tile.
    func placeholder(forMedia media: String) -> WorkPlaceholder? { items.first { $0.target.mediaIDs.contains(media) } }

    /// Remove: a failed placeholder goes; an active one cancels its job.
    func remove(_ id: String) {
        if document.jobs.job(id)?.isActive == true { document.jobs.cancel(id) }
        removed.insert(id)
    }

    /// Retry: runs the command again with the same inputs; the new job takes over the placeholder.
    func retry(_ id: String) {
        guard let retry = retries[id], let target = targets[id] else { return }
        removed.insert(id)
        Task { [weak self] in
            do {
                if let job = try await retry() { self?.track(job, target, retry: retry) }
            } catch {
                self?.document.message = error.localizedDescription
            }
        }
    }
}
