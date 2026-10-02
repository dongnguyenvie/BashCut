import AVFoundation
import BashCutEngine
import BashCutProject
import Foundation
import Observation

/// The editor viewer: the program player, the color-comparison player, the composition they play and
/// the playhead. The document hands it each new project revision through `rebuild`; seeking, playback
/// and the comparison toggle work against the last project it was given.
@MainActor @Observable
public final class PreviewController {
    public let player = AVPlayer()
    public let comparisonPlayer = AVPlayer()
    /// Current frame of the program viewer.
    public private(set) var playhead = 0
    /// Whether the viewer shows the ungraded original beside the graded program.
    public private(set) var showColorComparison = false
    /// The composition the program player is playing, for frame grabs.
    @ObservationIgnored public private(set) var snapshot: CompositionSnapshot?
    /// Status-bar text: an error, or "" once a preview is ready.
    @ObservationIgnored public var onMessage: (@MainActor (String) -> Void)?

    private let engine: any RenderEngine
    @ObservationIgnored private var project = Project(name: "Untitled")
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var workspace: URL?
    @ObservationIgnored private var comparisonSnapshot: CompositionSnapshot?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    /// Number of compositions built; tests use it to see that a rebuild ran.
    @ObservationIgnored public private(set) var buildCount = 0

    public init(engine: any RenderEngine) {
        self.engine = engine
        comparisonPlayer.isMuted = true
    }

    public var isPlaying: Bool { player.rate != 0 }

    /// Forgets the previous project's preview and moves the playhead to the start.
    public func reset(_ project: Project) {
        rebuildTask?.cancel()
        rebuildTask = nil
        clearPlayers()
        showColorComparison = false
        self.project = project
        root = nil
        playhead = 0
    }

    /// Builds the preview for `project` (after a short debounce); a newer call cancels an older one.
    public func rebuild(_ project: Project, root: URL?, workspace: URL?) {
        self.project = project
        self.root = root
        self.workspace = workspace
        rebuildTask?.cancel()
        clearPlayers()
        playhead = min(playhead, project.duration)
        guard let root, project.duration > 0 else { return }
        let compare = showColorComparison
        rebuildTask = Task { [engine] in
            do {
                try await Task.sleep(for: .milliseconds(50))
                let built = try await engine.build(project, root: root, workspace: workspace)
                let comparisonBuilt = compare
                    ? try await engine.build(project.withoutColorEffects(), root: root, workspace: workspace)
                    : nil
                try Task.checkCancellation()
                guard project.revision == self.project.revision, compare == showColorComparison else { return }
                buildCount += 1
                try await show(built, comparison: comparisonBuilt)
                seek(playhead)
                onMessage?("")
            } catch is CancellationError {} catch { onMessage?(error.localizedDescription) }
        }
    }

    public func seek(_ frame: Int) {
        playhead = min(max(0, frame), project.duration)
        let time = project.fps.time(playhead)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        if showColorComparison {
            comparisonPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    public func togglePlayback() {
        if player.rate == 0 {
            player.play()
            if showColorComparison { comparisonPlayer.play() }
        } else {
            pause()
        }
    }

    public func pause() {
        player.pause()
        comparisonPlayer.pause()
    }

    public func setColorComparison(_ enabled: Bool) {
        guard showColorComparison != enabled else { return }
        showColorComparison = enabled
        rebuild(project, root: root, workspace: workspace)
    }

    /// Follows the player while it plays and keeps the comparison player within a frame of it.
    public func updatePlayhead() {
        if let error = player.currentItem?.error { onMessage?(error.localizedDescription) }
        guard player.rate != 0, player.currentTime().isNumeric else { return }
        playhead = project.fps.frame(player.currentTime())
        guard showColorComparison, comparisonPlayer.currentItem != nil else { return }
        let drift = abs(comparisonPlayer.currentTime().seconds - player.currentTime().seconds)
        if drift > 1 / project.fps.value {
            comparisonPlayer.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func clearPlayers() {
        snapshot = nil
        comparisonSnapshot = nil
        pause()
        player.replaceCurrentItem(with: nil)
        comparisonPlayer.replaceCurrentItem(with: nil)
    }

    private func show(_ built: CompositionSnapshot, comparison: CompositionSnapshot?) async throws {
        snapshot = built
        let item = Self.playerItem(built)
        player.replaceCurrentItem(with: item)
        var comparisonItem: AVPlayerItem?
        if let comparison {
            comparisonSnapshot = comparison
            comparisonItem = Self.playerItem(comparison)
            comparisonPlayer.replaceCurrentItem(with: comparisonItem)
        }
        try await Self.waitUntilReady(item, message: "Preview could not become ready")
        if let comparisonItem {
            try await Self.waitUntilReady(comparisonItem, message: "Comparison preview could not become ready")
        }
    }

    private static func playerItem(_ snapshot: CompositionSnapshot) -> AVPlayerItem {
        let item = AVPlayerItem(asset: snapshot.composition)
        item.videoComposition = snapshot.videoComposition
        item.audioMix = snapshot.audioMix
        return item
    }

    private static func waitUntilReady(_ item: AVPlayerItem, message: String) async throws {
        for _ in 0..<50 where item.status == .unknown {
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        guard item.status == .readyToPlay else {
            throw item.error ?? ProjectError.invalid(message)
        }
    }
}
