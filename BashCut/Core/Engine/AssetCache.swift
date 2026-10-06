@preconcurrency import AVFoundation
import Foundation

/// A purpose-specific LRU sized for the current project's active media, not a fixed 64-file working set.
actor AssetCache {
    private let minimumCapacity: Int
    private var capacity: Int
    private var assets: [URL: LoadedAsset] = [:]
    private var order: [URL] = []
    private(set) var loads = 0
    var count: Int { assets.count }

    init(minimumCapacity: Int) {
        self.minimumCapacity = max(1, minimumCapacity)
        capacity = max(1, minimumCapacity)
    }

    func resize(for mediaCount: Int) {
        capacity = max(minimumCapacity, mediaCount)
        evict()
    }

    func load(_ url: URL) async throws -> LoadedAsset {
        let signature = FileSignature(url)
        if let cached = assets[url], cached.signature == signature {
            touch(url)
            return cached
        }
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let loaded = LoadedAsset(
            asset: asset, signature: signature, video: video, audio: audio,
            videoRange: try await video?.load(.timeRange),
            naturalSize: try await video?.load(.naturalSize) ?? .zero,
            preferredTransform: try await video?.load(.preferredTransform) ?? .identity)
        loads += 1
        assets[url] = loaded
        touch(url)
        evict()
        return loaded
    }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }

    private func evict() {
        while order.count > capacity { assets.removeValue(forKey: order.removeFirst()) }
    }
}

/// Immutable asset metadata; retains the asset that owns its tracks across builder/cache actor boundaries.
struct LoadedAsset: @unchecked Sendable {
    let asset: AVURLAsset
    let signature: FileSignature
    let video: AVAssetTrack?
    let audio: AVAssetTrack?
    /// Where the video track has pictures; the file's duration (and so `Media.frames`) can run past its end.
    let videoRange: CMTimeRange?
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
}
