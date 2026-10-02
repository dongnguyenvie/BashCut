import BashCutEngine
import BashCutProject
import Foundation
import Observation

@MainActor @Observable final class WaveformModel {
    var values: [String: AudioWaveform] = [:]
    var errors: [String: String] = [:]
    var loading = false
    private let analyzer = WaveformAnalyzer()
    private var task: Task<Void, Never>?
    private var requested: [String] = []
    private var generation = UUID()

    func reset() {
        task?.cancel()
        generation = UUID()
        values = [:]
        errors = [:]
        requested = []
        loading = false
    }
    func refresh(media: [Media], root: URL) {
        requested = []
        values = [:]
        errors = [:]
        update(media: media, root: root)
    }
    func update(media: [Media], root: URL) {
        let signature = [root.path] + media.map { $0.id + ":" + $0.path }
        guard signature != requested else { return }
        task?.cancel()
        let identifiers = Set(media.map(\.id))
        values = values.filter { identifiers.contains($0.key) }
        errors = errors.filter { identifiers.contains($0.key) }
        requested = signature
        let id = UUID()
        generation = id
        loading = true
        task = Task {
            defer { if generation == id { loading = false } }
            for asset in media {
                do {
                    try Task.checkCancellation()
                    let waveform = try await analyzer.waveform(
                        url: root.appendingPathComponent(asset.path),
                        cacheDirectory: root.appendingPathComponent(".bashcut/cache/waveforms"))
                    try Task.checkCancellation()
                    guard generation == id else { return }
                    values[asset.id] = waveform
                    errors.removeValue(forKey: asset.id)
                } catch is CancellationError { return } catch {
                    if generation == id { errors[asset.id] = error.localizedDescription }
                }
            }
        }
    }
}
