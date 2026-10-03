import AVFoundation
import BashCutEngine
import BashCutProject
import Foundation
import Observation

/// The editor viewer: the program player, the color-comparison player, the composition they play and
/// the playhead. The document hands it each new project revision through `rebuild`; seeking, playback
/// and the comparison toggle work against the last project it was given.
///
/// A rebuild prepares the new composition in fresh players (ready and sought to the playhead) and then
/// swaps them in, so the viewer keeps showing the previous picture instead of going blank on every edit. When the
/// new composition plays the same media at the same times (a colour, text, transform, keyframe or volume edit), the
/// shown players only take its video composition and audio mix, which is much quicker than loading it again.
@MainActor @Observable
public final class PreviewController {
    public private(set) var player = AVPlayer()
    public private(set) var comparisonPlayer = PreviewController.mutedPlayer()
    /// Current frame of the program viewer.
    public private(set) var playhead = 0
    /// Whether the viewer shows the ungraded original beside the graded program.
    public private(set) var showColorComparison = false
    /// The composition the program player is playing, for frame grabs. After an edit it is the previous
    /// composition until the new one is shown; `isCurrent` tells them apart.
    @ObservationIgnored public private(set) var snapshot: CompositionSnapshot?
    /// Whether `snapshot` shows the last project given to `rebuild`.
    public var isCurrent: Bool { snapshot != nil && shownRequest == request }
    /// The composition of the last project given to `rebuild` as soon as it is built, before the players are
    /// ready to show it; frame grabs (`ui frame`) need no player.
    public var currentBuild: CompositionSnapshot? { builtRequest == request ? built : nil }
    @ObservationIgnored private var built: CompositionSnapshot?
    @ObservationIgnored private var builtRequest = -1
    /// Bumped by every `rebuild` and `reset`; `shownRequest` is the one on screen.
    @ObservationIgnored private var request = 0
    @ObservationIgnored private var shownRequest = -1
    /// Status-bar text: an error, or "" once a preview is ready.
    @ObservationIgnored public var onMessage: (@MainActor (String) -> Void)?
    /// Called with the playhead when playback stops (pause or the end of the timeline).
    @ObservationIgnored public var onPlaybackStopped: (@MainActor (Int) -> Void)?
    @ObservationIgnored private var wasPlaying = false

    @ObservationIgnored var awaitReadiness: @MainActor (AVPlayerItem, String) async throws -> Void = { item, message in
        try await PlayerItemReadiness.wait(item, message: message)
    }
    private let engine: any RenderEngine
    private let coalescingDelay: @Sendable () async throws -> Void
    @ObservationIgnored private var project = Project(name: "Untitled")
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var workspace: URL?
    @ObservationIgnored private var comparisonSnapshot: CompositionSnapshot?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    /// Number of compositions built; tests use it to see that a rebuild ran.
    @ObservationIgnored public private(set) var buildCount = 0
    /// Rebuilds that updated the shown players in place instead of loading new ones.
    @ObservationIgnored public private(set) var inPlaceUpdates = 0
    /// Exact seeks sent to the program player; tests use it to see that scrubbing coalesces.
    @ObservationIgnored public private(set) var seekCount = 0
    /// Chase-time scrubbing (Apple QA1820): one exact seek in flight, the newest target waits for it.
    @ObservationIgnored private var seekInFlight = false
    @ObservationIgnored private var chaseTarget: CMTime?
    /// Bumped when the player item changes, so a stale seek completion is ignored.
    @ObservationIgnored private var seekGeneration = 0

    public init(engine: any RenderEngine, coalescingDelay: @escaping @Sendable () async throws -> Void = {
        try await Task.sleep(for: .milliseconds(50))
    }) {
        self.engine = engine
        self.coalescingDelay = coalescingDelay
    }

    private static func mutedPlayer() -> AVPlayer {
        let player = AVPlayer()
        player.isMuted = true
        return player
    }

    public var isPlaying: Bool { player.rate != 0 }

    /// Forgets the previous project's preview and moves the playhead to the start.
    public func reset(_ project: Project) {
        rebuildTask?.cancel()
        rebuildTask = nil
        request += 1
        clearPlayers()
        showColorComparison = false
        self.project = project
        root = nil
        playhead = 0
    }

    /// Discrete edits build immediately; coalesced slider/drag edits debounce. Newer calls cancel older ones.
    public func rebuild(_ project: Project, root: URL?, workspace: URL?, coalescing: Bool = false) {
        self.project = project
        self.root = root
        self.workspace = workspace
        rebuildTask?.cancel()
        request += 1
        // The previous picture stays up while the new composition builds; only playback stops.
        pause()
        if playhead > project.duration { playhead = project.duration }
        guard let root, project.duration > 0 else {
            clearPlayers()
            return
        }
        let compare = showColorComparison
        let request = request
        rebuildTask = Task { [engine] in
            let timing = PreviewTiming()
            defer { timing.finish() }
            do {
                if coalescing { try await coalescingDelay() }
                try Task.checkCancellation()
                timing.begin("build")
                let built = try await engine.build(project, root: root, workspace: workspace, purpose: .preview)
                let comparisonBuilt = compare
                    ? try await engine.build(
                        project.withoutColorEffects(), root: root, workspace: workspace, purpose: .preview)
                    : nil
                timing.end()
                try Task.checkCancellation()
                guard request == self.request, compare == showColorComparison else { return }
                self.built = built
                builtRequest = request
                buildCount += 1
                timing.begin("swap")
                let updated = update(with: built, comparison: comparisonBuilt, request: request)
                timing.end()
                if !updated {
                    try await show(built, comparison: comparisonBuilt, request: request, timing: timing)
                }
                onMessage?("")
            } catch is CancellationError {} catch {
                // Keep the last picture if preparation is slow; stale requests must not overwrite current errors.
                guard request == self.request else { return }
                if !(error is PlayerItemReadiness.Timeout) { clearPlayers() }
                onMessage?(error.localizedDescription)
            }
        }
    }

    /// Moves the playhead and shows that exact frame. While a seek is still decoding, further calls only
    /// update the target, so dragging the playhead never queues up stale frames.
    public func seek(_ frame: Int) {
        let target = min(max(0, frame), project.duration)
        if target != playhead { playhead = target }
        chase(project.fps.time(playhead))
    }

    private func chase(_ time: CMTime) {
        chaseTarget = time
        guard !seekInFlight, player.currentItem != nil else { return }
        chaseTarget = nil
        seekInFlight = true
        seekCount += 1
        let generation = seekGeneration
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.seekFinished(generation) }
        }
        if showColorComparison {
            comparisonPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func seekFinished(_ generation: Int) {
        guard generation == seekGeneration else { return }
        seekInFlight = false
        if let next = chaseTarget { chase(next) }
    }

    public func togglePlayback() {
        if player.rate == 0 {
            wasPlaying = true
            player.play()
            if showColorComparison { comparisonPlayer.play() }
        } else {
            pause()
        }
    }

    public func pause() {
        player.pause()
        comparisonPlayer.pause()
        noteStopped()
    }

    private func noteStopped() {
        guard wasPlaying else { return }
        wasPlaying = false
        onPlaybackStopped?(playhead)
    }

    public func setColorComparison(_ enabled: Bool) {
        guard showColorComparison != enabled else { return }
        showColorComparison = enabled
        rebuild(project, root: root, workspace: workspace)
    }

    /// Follows the player while it plays and keeps the comparison player within a frame of it.
    public func updatePlayhead() {
        if let error = player.currentItem?.error { onMessage?(error.localizedDescription) }
        if player.rate == 0 { noteStopped() } else { wasPlaying = true }
        guard player.rate != 0, player.currentTime().isNumeric else { return }
        let frame = project.fps.frame(player.currentTime())
        // Observers (timeline, transport bar) only hear about real moves.
        if frame != playhead { playhead = frame }
        guard showColorComparison, comparisonPlayer.currentItem != nil else { return }
        let drift = abs(comparisonPlayer.currentTime().seconds - player.currentTime().seconds)
        if drift > 1 / project.fps.value {
            comparisonPlayer.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func clearPlayers() {
        seekGeneration += 1
        seekInFlight = false
        chaseTarget = nil
        snapshot = nil
        comparisonSnapshot = nil
        built = nil
        pause()
        player.replaceCurrentItem(with: nil)
        comparisonPlayer.replaceCurrentItem(with: nil)
    }

    /// Gives the shown players the new video composition and audio mix when `built` (and the comparison) has the
    /// structure of what they play; false when they need new player items.
    private func update(with built: CompositionSnapshot, comparison: CompositionSnapshot?, request: Int) -> Bool {
        func same(_ new: CompositionSnapshot?, _ shown: CompositionSnapshot?) -> Bool {
            guard let new, let shown else { return new == nil && shown == nil }
            return new.structure != nil && new.structure == shown.structure
        }
        guard let shown = snapshot, same(built, shown), same(comparison, comparisonSnapshot),
            let item = player.currentItem, item.status == .readyToPlay, item.error == nil,
            comparison == nil || (comparisonPlayer.currentItem?.status == .readyToPlay && comparisonPlayer.currentItem?.error == nil)
        else { return false }
        item.videoComposition = built.videoComposition
        item.audioMix = built.audioMix
        if let comparison, let comparisonItem = comparisonPlayer.currentItem {
            comparisonItem.videoComposition = comparison.videoComposition
            comparisonItem.audioMix = comparison.audioMix
        }
        snapshot = built
        comparisonSnapshot = comparison
        shownRequest = request
        inPlaceUpdates += 1
        // A paused player keeps its last frame: seek to the playhead so it renders with the new instructions.
        seek(playhead)
        return true
    }

    /// Readies `built` in new players at the playhead, then swaps them in for the current ones.
    private func show(
        _ built: CompositionSnapshot, comparison: CompositionSnapshot?, request: Int, timing: PreviewTiming
    ) async throws {
        timing.begin("ready")
        let staged = AVPlayer()
        let item = Self.playerItem(built)
        staged.replaceCurrentItem(with: item)
        var stagedComparison: AVPlayer?
        if let comparison {
            let player = Self.mutedPlayer()
            player.replaceCurrentItem(with: Self.playerItem(comparison))
            stagedComparison = player
        }
        try await awaitReadiness(item, "Preview could not become ready")
        if let comparisonItem = stagedComparison?.currentItem {
            try await awaitReadiness(comparisonItem, "Comparison preview could not become ready")
        }
        timing.begin("swap")
        let frame = playhead
        let time = project.fps.time(frame)
        await staged.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        if let stagedComparison {
            await stagedComparison.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        try Task.checkCancellation()
        guard request == self.request else { return }
        player.replaceCurrentItem(with: nil)
        comparisonPlayer.replaceCurrentItem(with: nil)
        player = staged
        comparisonPlayer = stagedComparison ?? Self.mutedPlayer()
        snapshot = built
        comparisonSnapshot = comparison
        shownRequest = request
        seekGeneration += 1
        seekInFlight = false
        chaseTarget = nil
        // The playhead may have moved while the new players were getting ready.
        if playhead != frame { seek(playhead) }
    }

    private static func playerItem(_ snapshot: CompositionSnapshot) -> AVPlayerItem {
        let item = AVPlayerItem(asset: snapshot.composition)
        item.videoComposition = snapshot.videoComposition
        item.audioMix = snapshot.audioMix
        return item
    }

}
