import AVFoundation
import AppKit
import BashCutProject
import BashCutStorage
import Foundation
import Observation

/// The run panel (#447, #448): the agent's stages, the current one and the elapsed time while a run goes, then the
/// result card once it exported. It reads the run log when the file changes (a cheap check the editor makes every
/// second), so stages BashCut logs itself and the agent's `run progress` calls both show.
@MainActor @Observable final class RunPanelModel {
    @ObservationIgnored unowned let document: ProjectDocument
    private(set) var progress: RunProgress?
    private(set) var result: RunResult?
    private(set) var thumbnail: NSImage?
    /// What is hidden: the run the user closed the panel for (`until` nil: until the next run), or a run already
    /// over when the project opened (`until` its last stage entry: a new stage shows it again).
    private var dismissed: (run: Int, until: Date?)?
    var collapsed = false
    /// Shown with Show Agent Run: stays even for a run that ended without an export.
    private var shownByUser = false
    @ObservationIgnored private var stamp: (date: Date?, size: Int, revision: Int)?
    @ObservationIgnored private var thumbnailPath: String?
    /// The project the panel last read, so another project starts fresh.
    @ObservationIgnored private var projectURL: URL?

    /// A run counts as stale (not shown when a project opens) after this long without a stage entry.
    static let staleAfter: TimeInterval = 6 * 3_600

    init(document: ProjectDocument) { self.document = document }

    /// Whether the panel shows: a run with stages that the user did not close, still going or with a result; or the
    /// panel the user opened with the agent button (#534), also without stages (the agent's steps and jobs).
    var visible: Bool {
        guard let progress else { return shownByUser }
        guard !isDismissed(progress) else { return false }
        return !progress.finished || result != nil || shownByUser
    }

    /// Whether the panel could be opened: it is closed (the agent button opens it in any state, #534).
    var canShow: Bool { !visible }

    /// The agent button: opens the panel, or closes it.
    func toggle() {
        if visible { dismiss() } else { show() }
    }

    /// Whether this run is followed: the panel shows or would show it.
    var tracksRun: Bool { progress.map { !isDismissed($0) } ?? false }

    private func isDismissed(_ progress: RunProgress) -> Bool {
        guard let dismissed, dismissed.run == progress.run else { return false }
        guard let until = dismissed.until else { return true }
        return (progress.lastActivity ?? .distantPast) <= until
    }

    /// Reads the run log again when it changed (or the revision did, for the issues left on the card).
    func refresh(force: Bool = false) {
        if document.fileURL != projectURL {
            projectURL = document.fileURL
            projectOpened()
            return
        }
        guard let log = document.runLog else {
            progress = nil
            result = nil
            stamp = nil
            return
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: log.url.path)
        let next = (
            date: attributes?[.modificationDate] as? Date, size: (attributes?[.size] as? Int) ?? 0,
            revision: document.project.revision)
        if !force, let stamp, stamp.date == next.date, stamp.size == next.size,
            stamp.revision == next.revision || result == nil
        { return }
        stamp = next
        progress = RunProgress.make(document.project, entries: log.entries())
        let previous = result
        result = progress.flatMap(document.runResult)
        if result?.run == previous?.run, result?.main == previous?.main { result?.thumbnail = previous?.thumbnail }
        loadThumbnail()
    }

    /// A project opened: a run already over, or idle for hours, does not pop up again.
    private func projectOpened() {
        document.activity.reset()
        dismissed = nil
        shownByUser = false
        thumbnail = nil
        thumbnailPath = nil
        result = nil
        refresh(force: true)
        guard let progress else { return }
        let last = progress.lastActivity ?? .distantPast
        if progress.finished || Date().timeIntervalSince(last) > Self.staleAfter {
            dismissed = (progress.run, progress.lastActivity)
        }
    }

    func dismiss() {
        dismissed = progress.map { ($0.run, nil) }
        shownByUser = false
    }

    func show() {
        dismissed = nil
        shownByUser = true
        collapsed = false
        refresh(force: true)
    }

    /// A still from a third of the newest output, kept in `.bashcut/cache/run-result.jpg` for `run status`.
    private func loadThumbnail() {
        guard let main = result?.main else { return }
        let path = main.path, key = path + "|" + main.completedAt.description
        guard key != thumbnailPath else { return }
        thumbnailPath = key
        thumbnail = nil
        let url = URL(fileURLWithPath: path)
        let cache = document.fileURL?.deletingLastPathComponent().appendingPathComponent(".bashcut/cache/run-result.jpg")
        let duration = result?.main.duration ?? 0
        Task { [weak self] in
            guard let image = await Self.still(of: url, at: duration / 3) else { return }
            guard let self, self.thumbnailPath == key else { return }
            self.thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            if let cache, Self.writeJPEG(image, to: cache) { self.result?.thumbnail = cache }
        }
    }

    private nonisolated static func still(of url: URL, at seconds: Double) async -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        return try? await generator.image(at: CMTime(seconds: max(0, seconds), preferredTimescale: 600)).image
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) -> Bool {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
