@preconcurrency import AVFoundation
import AppKit
import BashCutEngine
import BashCutProject

/// Small thumbnails for video clips on the timeline. Drawing only reads this cache; missing thumbnails are made
/// in the background, newest request first, one at a time, and the timeline redraws once a batch lands.
/// Times are snapped to a power-of-two grid, so zooming in and out reuses most thumbnails.
@MainActor final class FilmstripCache {
    struct Key: Hashable {
        let url: URL
        let millis: Int
        /// The grid step, also how far the decoder may stray from the exact time.
        let quantumMillis: Int
    }

    static let limit = 1_500
    nonisolated static let maximumSize = CGSize(width: 160, height: 160)

    var onUpdate: (() -> Void)?
    private var images: [Key: NSImage] = [:]
    private var order: [Key] = []
    private var pending: [Key] = []
    private var requested: Set<Key> = []
    private var working = false
    private var updateScheduled = false
    private let renderer = FilmstripRenderer()

    /// The thumbnail time grid for tiles that are `period` seconds apart: a power of two of seconds, never
    /// finer than one source frame.
    static func quantum(for period: Double, fps: Double) -> Double {
        let minimum = 1 / max(1, fps)
        guard period.isFinite, period > minimum else { return minimum }
        return pow(2, (log2(period)).rounded(.down))
    }

    /// The cached thumbnail nearest to `seconds` on the `quantum` grid; schedules it when missing.
    func image(url: URL, seconds: Double, quantum: Double) -> NSImage? {
        let snapped = (max(0, seconds) / quantum).rounded(.down) * quantum
        let key = Key(url: url, millis: Int((snapped * 1000).rounded()), quantumMillis: Int((quantum * 1000).rounded()))
        if let image = images[key] { return image }
        if !requested.contains(key) {
            requested.insert(key)
            pending.append(key)
            // Only recent requests matter; tiles scrolled past long ago are dropped and asked for again later.
            if pending.count > 400 {
                for stale in pending.prefix(pending.count - 400) { requested.remove(stale) }
                pending.removeFirst(pending.count - 400)
            }
            startWorking()
        }
        return nil
    }

    /// Forgets everything (another project opened).
    func reset() {
        images.removeAll()
        order.removeAll()
        pending.removeAll()
        requested.removeAll()
    }

    private func startWorking() {
        guard !working else { return }
        working = true
        Task { [weak self] in
            while let self, let key = self.nextKey() {
                let image = await self.renderer.image(
                    url: key.url, seconds: Double(key.millis) / 1000, tolerance: min(0.5, Double(key.quantumMillis) / 2000))
                self.store(image, for: key)
            }
            self?.working = false
        }
    }

    /// Newest request first: those are the tiles on screen now.
    private func nextKey() -> Key? { pending.popLast() }

    private func store(_ image: CGImage?, for key: Key) {
        guard let image else { return }
        images[key] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        order.append(key)
        if order.count > Self.limit {
            let dropped = order.removingHead(order.count - Self.limit)
            for key in dropped {
                images[key] = nil
                requested.remove(key)
            }
        }
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            MainActor.assumeIsolated {
                self?.updateScheduled = false
                self?.onUpdate?()
            }
        }
    }
}

private extension Array {
    mutating func removingHead(_ count: Int) -> [Element] {
        let head = Array(prefix(count))
        removeSubrange(0..<Swift.min(count, self.count))
        return head
    }
}

/// Decodes thumbnails off the main actor, keeping one image generator per file.
private actor FilmstripRenderer {
    private var generators: [URL: AVAssetImageGenerator] = [:]

    func image(url: URL, seconds: Double, tolerance: Double) async -> CGImage? {
        if StillImageMovie.isImage(url) {
            return StillImageMovie.decoded(url, maximumSide: Int(max(FilmstripCache.maximumSize.width,
                                                                       FilmstripCache.maximumSize.height)))
        }
        let generator = generators[url] ?? {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = FilmstripCache.maximumSize
            if generators.count > 32 { generators.removeAll() }
            generators[url] = generator
            return generator
        }()
        // A nearby frame within half a grid step is fine for a thumbnail and much faster than an exact frame.
        let slack = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = slack
        generator.requestedTimeToleranceAfter = slack
        return try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }
}

extension TimelineCanvas {
    /// The file thumbnails come from: the preview proxy when one exists, else the original.
    func filmstripURL(_ media: Media, root: URL) -> URL? {
        if let cached = filmstripURLs[media.id] { return cached }
        let url = try? ProxyMediaSource().url(for: media, root: root, workspace: document.settings.workspace, purpose: .preview)
        filmstripURLs[media.id] = url
        return url
    }
}
