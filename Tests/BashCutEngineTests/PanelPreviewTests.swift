import BashCutProject
import CoreGraphics
import Foundation
import Testing
@testable import BashCutEngine

/// P2-B3: the Transitions panel's moving previews and the Filters panel's looks on the viewer's frame.
struct PanelPreviewTests {
    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("panel-previews-\(UUID().uuidString)", isDirectory: true)
    }

    /// The mean colour (0–255) of a part of `image`, given as shares of its width and height from the top left.
    private static func mean(_ image: CGImage, x: ClosedRange<Double> = 0...1, y: ClosedRange<Double> = 0...1) -> [Double] {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var sum = [0.0, 0.0, 0.0], count = 0.0
        for row in Int(y.lowerBound * Double(height))..<Int(y.upperBound * Double(height)) {
            for column in Int(x.lowerBound * Double(width))..<Int(x.upperBound * Double(width)) {
                let offset = (row * width + column) * 4
                for channel in 0..<3 { sum[channel] += Double(pixels[offset + channel]) }
                count += 1
            }
        }
        return sum.map { $0 / max(1, count) }
    }

    private static func distance(_ first: [Double], _ second: [Double]) -> Double {
        zip(first, second).map { abs($0 - $1) }.max() ?? 0
    }

    @Test("The two sample stills are bundled, small and different")
    func samples() throws {
        let samples = try #require(TransitionPreview.samples())
        #expect(samples.outgoing.width == 320 && samples.outgoing.height == 180)
        #expect(samples.incoming.width == 320 && samples.incoming.height == 180)
        #expect(Self.distance(Self.mean(samples.outgoing), Self.mean(samples.incoming)) > 40)
        var bytes = 0
        for name in ["outgoing", "incoming"] {
            bytes += try Data(contentsOf: try #require(TransitionPreview.sampleURL(name))).count
        }
        #expect(bytes <= 50_000)
    }

    @Test("A preview holds the outgoing still, runs the tween through the compositor, and holds the incoming one")
    func frames() throws {
        let samples = try #require(TransitionPreview.samples())
        let wipe = try #require(TransitionMotion.builtIns["wipe"])
        let frames = try TransitionPreview.frames(
            outgoing: samples.outgoing, incoming: samples.incoming, motion: wipe, easing: TimelineTransition.defaultEasing)
        #expect(frames.count == TransitionPreview.holdBefore + TransitionPreview.tweenFrames + 1 + TransitionPreview.holdAfter)
        let outgoing = Self.mean(samples.outgoing), incoming = Self.mean(samples.incoming)
        #expect(Self.distance(Self.mean(frames[0]), outgoing) < 6)
        #expect(Self.distance(Self.mean(frames[frames.count - 1]), incoming) < 6)
        // Half way through a wipe from the left, the left side is the lake and the right side still the sunset.
        let middle = frames[TransitionPreview.holdBefore + TransitionPreview.tweenFrames / 2]
        let left = Self.mean(middle, x: 0...0.4), right = Self.mean(middle, x: 0.6...1)
        #expect(Self.distance(left, Self.mean(samples.incoming, x: 0...0.4)) < 12)
        #expect(Self.distance(right, Self.mean(samples.outgoing, x: 0.6...1)) < 12)
    }

    @Test("Every built-in kind of the Transitions panel draws a preview that moves")
    func everyKind() throws {
        let samples = try #require(TransitionPreview.samples())
        let small = CGSize(width: 96, height: 54)
        for kind in TransitionMotion.groups.flatMap(\.kinds) {
            let frames = try TransitionPreview.frames(
                outgoing: samples.outgoing, incoming: samples.incoming,
                motion: TransitionMotion.resolved(kind: kind, motion: nil), easing: TimelineTransition.defaultEasing,
                size: small)
            let first = Self.mean(frames[0]), last = Self.mean(frames[frames.count - 1])
            let tween = frames[TransitionPreview.holdBefore + 1..<TransitionPreview.holdBefore + TransitionPreview.tweenFrames]
            #expect(
                tween.contains { Self.distance(Self.mean($0), first) > 4 && Self.distance(Self.mean($0), last) > 4 },
                "\(kind) shows neither picture changing")
        }
    }

    @Test("The poster is a frame where the move shows, never the flat white of a flash")
    func posters() throws {
        let samples = try #require(TransitionPreview.samples())
        for kind in ["flash", "blink", "dissolve", "wipe"] {
            let frames = try TransitionPreview.frames(
                outgoing: samples.outgoing, incoming: samples.incoming,
                motion: TransitionMotion.resolved(kind: kind, motion: nil), easing: TimelineTransition.defaultEasing,
                size: CGSize(width: 96, height: 54))
            let index = TransitionPreview.posterIndex(frames)
            #expect(index > TransitionPreview.holdBefore && index < TransitionPreview.holdBefore + TransitionPreview.tweenFrames)
            #expect(Self.mean(frames[index]).allSatisfy { $0 < 245 }, "\(kind) poster is white: \(index) \(Self.mean(frames[index]))")
        }
    }

    @Test("The key follows the motion data and the easing")
    func keys() throws {
        let dissolve = TransitionMotion.resolved(kind: "dissolve", motion: nil)
        let key = TransitionPreview.key(motion: dissolve, easing: "linear")
        #expect(key == TransitionPreview.key(motion: TransitionMotion(incoming: ["opacity": [0, 1]]), easing: "linear"))
        #expect(key != TransitionPreview.key(motion: dissolve, easing: "inOut"))
        let custom = try TransitionMotion(json: .object(["incoming": .object(["opacity": .array([.number(0), .number(0.5), .number(1)])])]))
        #expect(key != TransitionPreview.key(motion: custom, easing: "linear"))
    }

    @Test("A preview is rendered once and then read from disk, also when asked for twice at once")
    func store() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TransitionPreviewStore(folder: folder)
        let motion = TransitionMotion.resolved(kind: "iris", motion: nil)
        async let first = store.preview(motion: motion, easing: "linear")
        async let second = store.preview(motion: motion, easing: "linear")
        let urls = await [first, second]
        let url = try #require(urls[0])
        #expect(urls[1] == url)
        #expect(await store.renders == 1)
        #expect(await store.preview(motion: motion, easing: "linear") == url)
        #expect(await store.renders == 1)
        let loaded = TransitionPreview.load(url)
        #expect(loaded.count == TransitionPreview.holdBefore + TransitionPreview.tweenFrames + 1 + TransitionPreview.holdAfter)
        #expect(TransitionPreview.poster(url) != nil)
        _ = await store.preview(motion: motion, easing: "inOut")
        #expect(await store.renders == 2)
    }

    @Test("The wanted keys are every built-in kind and each preset's own motion and easing")
    func wantedKeys() throws {
        let kinds = TransitionMotion.groups.flatMap(\.kinds)
        let builtIn = TransitionPreview.wantedKeys(presets: [])
        #expect(builtIn.count == Set(kinds).count)
        #expect(builtIn.contains(TransitionPreview.key(
            motion: TransitionMotion.resolved(kind: "iris", motion: nil), easing: TimelineTransition.defaultEasing)))
        let custom = JSONValue.object(["incoming": .object(["opacity": .array([.number(0), .number(0.5), .number(1)])])])
        let keys = TransitionPreview.wantedKeys(presets: [
            TransitionPreset(kind: "iris", easing: "inOut"), TransitionPreset(kind: "mine", motion: custom),
        ])
        #expect(keys.isSuperset(of: builtIn) && keys.count == builtIn.count + 2)
        #expect(keys.contains(TransitionPreview.key(motion: try TransitionMotion(json: custom), easing: "linear")))
    }

    /// Writes a fake preview (GIF and poster) of `bytes` each, last shown `age` seconds ago.
    private static func fake(_ key: String, in folder: URL, bytes: Int = 10, age: TimeInterval = 0) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["\(key).gif", "\(key).png"] {
            let file = folder.appendingPathComponent(name)
            try Data(count: bytes).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: file.path)
        }
    }

    private static func names(_ folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    @Test("Pruning deletes previews no tile wants and half-written renders, and keeps the rest")
    func pruneUnwanted() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.fake("wanted", in: folder)
        try Self.fake("old-easing", in: folder)
        try Data(count: 10).write(to: folder.appendingPathComponent(".partial.gif"))
        let store = TransitionPreviewStore(folder: folder)
        let removed = await store.prune(keeping: ["wanted"])
        #expect(removed.count == 3)
        #expect(Self.names(folder) == ["wanted.gif", "wanted.png"])
        #expect(await store.prune(keeping: ["wanted"]).isEmpty)
    }

    @Test("Past the size bound the previews shown longest ago go first")
    func pruneBySize() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.fake("newest", in: folder, bytes: 100, age: 10)
        try Self.fake("middle", in: folder, bytes: 100, age: 100)
        try Self.fake("oldest", in: folder, bytes: 100, age: 1000)
        let store = TransitionPreviewStore(folder: folder)
        await store.prune(keeping: ["newest", "middle", "oldest"], byteLimit: 450)
        #expect(Self.names(folder) == ["newest.gif", "newest.png", "middle.gif", "middle.png"])
        // Showing a preview marks it used: the oldest file shown now outlives one that was not.
        try Self.fake("oldest", in: folder, bytes: 100, age: 1000)
        let motion = TransitionMotion.resolved(kind: "iris", motion: nil)
        let key = TransitionPreview.key(motion: motion, easing: "linear")
        try Self.fake(key, in: folder, bytes: 100, age: 5000)
        #expect(await store.preview(motion: motion, easing: "linear") != nil)
        #expect(await store.renders == 0)
        await store.prune(keeping: ["newest", "middle", "oldest", key], byteLimit: 450)
        #expect(Self.names(folder) == ["newest.gif", "newest.png", "\(key).gif", "\(key).png"])
    }

    @Test("A preview that is rendering is never pruned, and pruneOnce runs once")
    func pruneSkipsRenders() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.fake("stale", in: folder)
        let store = TransitionPreviewStore(folder: folder)
        let motion = TransitionMotion.resolved(kind: "dissolve", motion: nil)
        let key = TransitionPreview.key(motion: motion, easing: "linear")
        let rendering = Task { await store.preview(motion: motion, easing: "linear") }
        var prunedDuring = 0
        while await store.renders == 0 {
            if let removed = await store.pruneWhileRendering(key) {
                prunedDuring += 1
                #expect(!removed.contains { $0.lastPathComponent.hasPrefix(key) })
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(prunedDuring > 0)
        #expect(!Self.names(folder).contains("stale.gif"))
        let url = try #require(await rendering.value)
        #expect(FileManager.default.fileExists(atPath: url.path))
        await store.pruneOnce { [] }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try Self.fake("again", in: folder)
        await store.pruneOnce { [] }
        #expect(Self.names(folder) == ["again.gif", "again.png"])
    }

    @Test("An effect preset's saved GIF gives its first frame for the still tile and every frame with its delay")
    func effectPreview() throws {
        let samples = try #require(TransitionPreview.samples())
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let gif = folder.appendingPathComponent("effect.gif")
        try AnimatedImageMovie.writeGIF([samples.outgoing, samples.incoming, samples.outgoing], delay: 0.25, to: gif)
        let first = try #require(AnimatedPreview.firstFrame(gif))
        #expect(Self.distance(Self.mean(first), Self.mean(samples.outgoing)) < 12)
        let loaded = AnimatedPreview.frames(gif)
        #expect(loaded.images.count == 3)
        #expect(abs(loaded.delay - 0.25) < 0.01)
        #expect(Self.distance(Self.mean(loaded.images[1]), Self.mean(samples.incoming)) < 12)
        // No delay (or a tiny one) plays at 10 fps; a missing file has no frames.
        let fast = folder.appendingPathComponent("fast.gif")
        try AnimatedImageMovie.writeGIF([samples.outgoing, samples.incoming], delay: 0, to: fast)
        #expect(AnimatedPreview.frames(fast).delay == 0.1)
        #expect(AnimatedPreview.frames(folder.appendingPathComponent("none.gif")).images.isEmpty)
        #expect(AnimatedPreview.firstFrame(folder.appendingPathComponent("none.gif")) == nil)
    }

    @Test("A look's still is the frame graded like a clip: its exposure and its LUT")
    func looks() throws {
        let base = try #require(TransitionPreview.samples()?.incoming)
        let brighter = try LookPreview.render(base: base, color: ["exposure": .number(1)], lut: nil)
        #expect(Self.mean(brighter).reduce(0, +) > Self.mean(base).reduce(0, +) + 30)
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A 2-point LUT that swaps red and blue.
        let cube = folder.appendingPathComponent("swap.cube")
        var rows: [String] = []
        for blue in 0...1 { for green in 0...1 { for red in 0...1 { rows.append("\(blue) \(green) \(red)") } } }
        try ("LUT_3D_SIZE 2\n" + rows.joined(separator: "\n") + "\n").write(to: cube, atomically: true, encoding: .utf8)
        let swapped = Self.mean(try LookPreview.render(base: base, color: [:], lut: cube))
        let original = Self.mean(base)
        #expect(abs(swapped[0] - original[2]) < 8 && abs(swapped[2] - original[0]) < 8)
    }
}

extension TransitionPreviewStore {
    /// `prune(keeping: [])` only while `key` renders, in one step on the actor.
    fileprivate func pruneWhileRendering(_ key: String) -> [URL]? {
        running[key] == nil ? nil : prune(keeping: [])
    }
}
