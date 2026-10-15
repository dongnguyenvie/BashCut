import BashCutProject
import CoreImage
import CoreVideo
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A transition's looping preview for the Transitions panel (P2-B3): two bundled sample stills (a warm sunset going
/// out, a cool lake coming in) through the same `BashCutCompositor.picture` path an export takes, so the preview always
/// matches the renderer. Rendered locally the first time a motion is shown and kept as a GIF in Application Support,
/// keyed by the motion data and easing, so a preset with its own `motion` gets its own preview. Nothing is downloaded.
public enum TransitionPreview {
    /// Frames per second of the preview, the tween's length and the holds on each picture around it.
    public static let fps = 20.0
    public static let tweenFrames = 20
    public static let holdBefore = 6
    public static let holdAfter = 10
    /// Bumped when the stills, timing or files change, so older previews are not reused.
    static let version = 2

    /// The cache key: a hash of the motion's data and the easing (and `version`).
    public static func key(motion: TransitionMotion, easing: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = (try? encoder.encode(motion.json)) ?? Data()
        var hasher = SHA256()
        hasher.update(data: Data("v\(version)|\(easing)|".utf8))
        hasher.update(data: body)
        return hasher.finalize().prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// The keys the Transitions panel can show: every built-in kind at the default easing, and each preset's motion
    /// (its own, else its kind's) with its easing. `TransitionPreviewStore.prune` keeps only these.
    public static func wantedKeys(presets: [TransitionPreset]) -> Set<String> {
        var keys = Set(TransitionMotion.groups.flatMap(\.kinds).map {
            key(motion: TransitionMotion.resolved(kind: $0, motion: nil), easing: TimelineTransition.defaultEasing)
        })
        for preset in presets {
            keys.insert(key(
                motion: TransitionMotion.resolved(kind: preset.kind, motion: preset.motion),
                easing: preset.easing ?? TimelineTransition.defaultEasing))
        }
        return keys
    }

    /// The bundled sample stills: the outgoing and the incoming picture.
    public static func samples() -> (outgoing: CGImage, incoming: CGImage)? {
        func load(_ name: String) -> CGImage? {
            guard let url = sampleURL(name), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let outgoing = load("outgoing"), let incoming = load("incoming") else { return nil }
        return (outgoing, incoming)
    }

    /// A bundled sample still: "outgoing" or "incoming".
    static func sampleURL(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "TransitionSamples")
    }

    /// Every frame of the preview: the outgoing picture held, the tween, the incoming picture held.
    public static func frames(
        outgoing: CGImage, incoming: CGImage, motion: TransitionMotion, easing: String,
        size: CGSize = CGSize(width: 320, height: 180)
    ) throws -> [CGImage] {
        let bounds = CGRect(origin: .zero, size: size)
        let context = CIContext(options: [.cacheIntermediates: false])
        let from = try layer(outgoing, size: size), to = try layer(incoming, size: size)
        func side(_ isIncoming: Bool) -> FrameLayer {
            let picture = isIncoming ? to : from
            return FrameLayer(
                trackID: isIncoming ? 2 : 1, transform: picture.transform,
                transition: RenderTransition(
                    kind: "custom", startFrame: 0, duration: tweenFrames, incoming: isIncoming, fps: fps,
                    easing: easing, motion: motion))
        }
        let outgoingLayer = side(false), incomingLayer = side(true)
        let black = CIImage(color: .black).cropped(to: bounds)
        var result: [CGImage] = []
        let total = holdBefore + tweenFrames + 1 + holdAfter
        for index in 0..<total {
            let frame = index - holdBefore
            var image = black
            if frame < 0 {
                image = CIImage(cvPixelBuffer: from.buffer).transformed(by: from.transform).composited(over: image)
            } else if frame > tweenFrames {
                image = CIImage(cvPixelBuffer: to.buffer).transformed(by: to.transform).composited(over: image)
            } else {
                // The order a composition draws a cut in: the outgoing hold under the incoming clip, on black.
                let time = Double(frame) / fps
                image = BashCutCompositor.picture(outgoingLayer, source: from.buffer, time: time, bounds: bounds)
                    .composited(over: image)
                image = BashCutCompositor.picture(incomingLayer, source: to.buffer, time: time, bounds: bounds)
                    .composited(over: image)
            }
            guard let rendered = context.createCGImage(
                image.cropped(to: bounds), from: bounds, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            else { throw ProjectError.invalid("The transition preview could not be drawn") }
            result.append(rendered)
        }
        return result
    }

    /// Renders the preview of `motion` with the bundled stills and writes it as a looping GIF at `url`.
    public static func render(motion: TransitionMotion, easing: String, to url: URL) throws {
        guard let samples = samples() else { throw ProjectError.invalid("The transition sample stills are missing") }
        let pictures = try frames(outgoing: samples.outgoing, incoming: samples.incoming, motion: motion, easing: easing)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).gif")
        try AnimatedImageMovie.writeGIF(pictures, delay: 1 / fps, to: partial, maximumSide: 192)
        // The poster first: a GIF on disk means both files are there.
        try writePNG(pictures[posterIndex(pictures)], to: posterURL(url))
        _ = try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: partial, to: url)
    }

    /// The still a tile shows while it is not hovered, kept beside the GIF.
    public static func posterURL(_ url: URL) -> URL { url.deletingPathExtension().appendingPathExtension("png") }

    /// The tween frame that shows the move best: the most unlike both still pictures, and not one flat colour (the
    /// white middle of a flash or the black of a dip says nothing about it).
    static func posterIndex(_ frames: [CGImage]) -> Int {
        let cells = frames.map(thumbnail)
        guard let first = cells.first, let last = cells.last else { return 0 }
        func difference(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Double(max(1, a.count)) }
        // How much a frame says: some contrast, and not burnt to white or sunk to black.
        func legible(_ a: [Double]) -> Double {
            let mean = a.reduce(0, +) / Double(max(1, a.count))
            let spread = (a.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(1, a.count))).squareRoot()
            return min(1, spread / 40) * min(1, (255 - mean) / 60) * min(1, mean / 60)
        }
        let tween = holdBefore + 1..<min(cells.count - 1, holdBefore + tweenFrames)
        return tween.max { a, b in
            func score(_ index: Int) -> Double {
                min(difference(cells[index], first), difference(cells[index], last)) * legible(cells[index])
            }
            return score(a) < score(b)
        } ?? holdBefore + tweenFrames / 2
    }

    /// A frame as 16 × 9 grey levels (0–255).
    private static func thumbnail(_ image: CGImage) -> [Double] {
        let width = 16, height = 9
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            context?.interpolationQuality = .medium
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels.map(Double.init)
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ProjectError.invalid("Cannot write \(url.lastPathComponent)") }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw ProjectError.invalid("Cannot write \(url.lastPathComponent)") }
    }

    /// The still a tile shows while it is not hovered (`posterURL`), without decoding the GIF.
    public static func poster(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(posterURL(url) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The frames of a preview GIF, in order.
    public static func load(_ url: URL) -> [CGImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        return (0..<CGImageSourceGetCount(source)).compactMap { CGImageSourceCreateImageAtIndex(source, $0, nil) }
    }

    /// A still as the decoded frame a composition hands the compositor, and the transform that fills the frame.
    private static func layer(_ image: CGImage, size: CGSize) throws -> (buffer: CVPixelBuffer, transform: CGAffineTransform) {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer
        ) == kCVReturnSuccess, let buffer else { throw ProjectError.invalid("No pixel buffer for the transition preview") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw ProjectError.invalid("No pixel buffer for the transition preview") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let scale = max(size.width / Double(image.width), size.height / Double(image.height))
        let transform = CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(
            translationX: (size.width - Double(image.width) * scale) / 2,
            y: (size.height - Double(image.height) * scale) / 2))
        return (buffer, transform)
    }
}

/// Transition previews on disk (Application Support/BashCut/TransitionPreviews), rendered once per motion and easing.
/// Concurrent requests for one key share a render; at most two render at a time. Old previews go in `prune`.
public actor TransitionPreviewStore {
    public static let shared = TransitionPreviewStore(folder: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BashCut/TransitionPreviews", isDirectory: true))

    public let folder: URL
    private(set) var running: [String: Task<URL?, Never>] = [:]
    private var slots = 2
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// How many previews this store rendered (tests check that a second request reuses the file).
    public private(set) var renders = 0
    /// Keys shown since launch: their files' dates were set once, so `prune` knows what was used recently.
    private var used: Set<String> = []
    private var pruned = false

    /// The most the folder keeps (about 250 previews of 130 KB; 39 are built in): past it the previews shown longest
    /// ago go first.
    public static let byteLimit = 32 << 20

    public init(folder: URL) { self.folder = folder }

    public func url(key: String) -> URL { folder.appendingPathComponent("\(key).gif") }

    /// The preview of `motion`, rendered when it is not on disk yet; nil when it cannot be drawn.
    public func preview(motion: TransitionMotion, easing: String) async -> URL? {
        let key = TransitionPreview.key(motion: motion, easing: easing)
        let target = url(key: key)
        if FileManager.default.fileExists(atPath: target.path) {
            if used.insert(key).inserted {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
            }
            return target
        }
        if let task = running[key] { return await task.value }
        let task = Task<URL?, Never> {
            await acquire()
            // Drawn off the actor, so other keys keep answering while this one renders.
            let drawn = await Task.detached(priority: .utility) {
                (try? TransitionPreview.render(motion: motion, easing: easing, to: target)) != nil
            }.value
            release()
            if drawn { renders += 1 }
            return drawn ? target : nil
        }
        running[key] = task
        let result = await task.value
        running[key] = nil
        used.insert(key)
        return result
    }

    /// `prune(keeping:)` once per launch: the Transitions panel calls it when it first shows.
    public func pruneOnce(keeping keys: @Sendable () -> Set<String>) {
        guard !pruned else { return }
        pruned = true
        prune(keeping: keys())
    }

    /// Deletes the previews (GIF and poster) whose key is not in `keys` (a changed motion or easing, a removed
    /// preset), half-written files of renders that ended, then the previews shown longest ago while the folder is
    /// over `byteLimit`. A key that is rendering now is never touched. Returns the deleted files.
    @discardableResult
    public func prune(keeping keys: Set<String>, byteLimit: Int = TransitionPreviewStore.byteLimit) -> [URL] {
        let manager = FileManager.default
        let properties: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: properties)
        else { return [] }
        var removed: [URL] = []
        func remove(_ file: URL) { if (try? manager.removeItem(at: file)) != nil { removed.append(file) } }
        var kept: [String: (files: [URL], bytes: Int, date: Date)] = [:]
        for file in files {
            let name = file.lastPathComponent
            // ".<uuid>.gif" is a render being written; with none running it is left from one that stopped.
            if name.hasPrefix(".") {
                if running.isEmpty, name.hasSuffix(".gif") { remove(file) }
                continue
            }
            let key = file.deletingPathExtension().lastPathComponent
            guard running[key] == nil else { continue }
            guard keys.contains(key) else {
                remove(file)
                continue
            }
            let values = try? file.resourceValues(forKeys: Set(properties))
            var entry = kept[key] ?? ([], 0, .distantPast)
            entry.files.append(file)
            entry.bytes += values?.fileSize ?? 0
            entry.date = max(entry.date, values?.contentModificationDate ?? .distantPast)
            kept[key] = entry
        }
        var total = kept.values.reduce(0) { $0 + $1.bytes }
        for entry in kept.values.sorted(by: { $0.date < $1.date }) where total > byteLimit {
            entry.files.forEach(remove)
            total -= entry.bytes
        }
        return removed
    }

    private func acquire() async {
        if slots > 0 {
            slots -= 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { slots += 1 } else { waiting.removeFirst().resume() }
    }
}
