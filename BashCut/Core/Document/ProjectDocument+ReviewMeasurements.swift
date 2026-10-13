import BashCutAutomation
import BashCutEngine
import BashCutProject
import Foundation

/// The review's picture and loudness measurements and the plugins' `review.check` issues outlive the session
/// (`ReviewMeasurementStore`): stored in the project's cache when measured, found again for content equal to what was
/// measured (after a restart, or an undo).
extension ProjectDocument {
    /// Takes the stored measurements of the open project's content when the session has none for this revision.
    /// The fingerprint (the project's JSON and its media files' dates) is made off the main actor.
    func restoreReviewMeasurements() async {
        guard let root = fileURL?.deletingLastPathComponent() else { return }
        let project = project
        let needsPicture = reviewPicture?.revision != project.revision
        let needsLoudness = reviewLoudness?.revision != project.revision
        // Only the checks still installed and enabled: a removed or disabled plugin's issues stay away.
        let running = Set(plugins.service.reviewCheckProviders(projectRoot: root, disabled: reviewDisabledChecks)
            .map(\.plugin.id))
        let needsPlugins = !running.isEmpty && reviewPluginIssues?.revision != project.revision
        guard needsPicture || needsLoudness || needsPlugins else { return }
        let workspace = settings.workspace
        let stored = await Task.detached(priority: .userInitiated) {
            ReviewMeasurementStore.load(for: project, projectRoot: root, workspace: workspace)
        }.value
        // The project may have moved on while the fingerprint was made.
        guard self.project.revision == project.revision, fileURL?.deletingLastPathComponent() == root else { return }
        if needsPicture, reviewPicture?.revision != project.revision, let picture = stored.picture {
            reviewPicture = picture
            DebugLog.write("review", "picture measurement of rev \(project.revision) restored from the cache")
        }
        if needsLoudness, reviewLoudness?.revision != project.revision, let loudness = stored.loudness {
            reviewLoudness = loudness
            DebugLog.write("review", "loudness of rev \(project.revision) restored from the cache")
        }
        if needsPlugins, reviewPluginIssues?.revision != project.revision, let stored = stored.pluginIssues {
            reviewPluginIssues = ReviewPluginIssues(
                revision: stored.revision, issues: stored.issues.filter { $0.source.map(running.contains) ?? false })
            DebugLog.write("review", "plugin check issues of rev \(project.revision) restored from the cache")
        }
    }

    /// When a project opens: forgets the last project's measurements (its revision numbers could match this one's)
    /// and looks for this content's in the cache.
    func resetReviewMeasurements() {
        reviewPicture = nil
        reviewLoudness = nil
        reviewPluginIssues = nil
        lastRender = nil
        guard fileURL != nil else { return }
        Task { [weak self] in await self?.restoreReviewMeasurements() }
    }

    /// Stores a measurement of `measured` (the project as it was rendered) in the background; a failure only means
    /// it is measured again after a restart.
    func storeReviewMeasurement(
        picture: ReviewPicture? = nil, loudness: ReviewLoudness? = nil, pluginIssues: [ReviewIssue]? = nil,
        of measured: Project
    ) {
        guard let root = fileURL?.deletingLastPathComponent(), picture != nil || loudness != nil || pluginIssues != nil
        else { return }
        let workspace = settings.workspace
        Task.detached(priority: .utility) {
            do {
                if let picture {
                    try ReviewMeasurementStore.store(picture, for: measured, projectRoot: root, workspace: workspace)
                }
                if let loudness {
                    try ReviewMeasurementStore.store(loudness, for: measured, projectRoot: root, workspace: workspace)
                }
                if let pluginIssues {
                    try ReviewMeasurementStore.store(
                        pluginIssues: pluginIssues, for: measured, projectRoot: root, workspace: workspace)
                }
            } catch {
                DebugLog.write("review", "measurement not stored: \(error.localizedDescription)")
            }
        }
    }
}
