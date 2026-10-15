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
