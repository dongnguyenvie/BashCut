@preconcurrency import AVFoundation
import BashCutProject
import BashCutTestSupport
import CoreGraphics
import Foundation
import Testing

@testable import BashCutEngine

/// Source frames as pictures (P0-A5): exact frames by index, contact sheets and the filmstrip.
struct MediaStillsTests {
    /// Grey level at `x, y` (top-left origin) of `image`.
    func grey(_ image: CGImage, _ x: Int, _ y: Int) -> Int {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return Int(pixel[0])
    }

    /// Red level at `x, y` (top-left origin).
    func red(_ image: CGImage, _ x: Int, _ y: Int) -> Int { grey(image, x, y) }

    @Test("Exact frames come back by index, upright, at the asked size")
    func exactFrames() async throws {
        let root = try TestFixtures.temporaryDirectory("media-stills")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("ramp.mov")
        // Grey 25 × (index mod 9), so neighbouring frames differ by 25, flat, with a white square in the top-left
        // corner.
        try await PictureSamplerTests.writeMovie(to: url, frames: 120, flat: true, dot: { _ in (0, 0) }, shade: { $0 % 9 * 25 })
        let images = try await MediaStills.images(
            url: url, isImage: false, fps: FrameRate(30, 1), frames: [0, 37, 119], maximumSide: nil)
        #expect(Set(images.keys) == [0, 37, 119])
        for (frame, image) in images {
            #expect(image.width == 160 && image.height == 90)
            #expect(abs(grey(image, 80, 60) - frame % 9 * 25) <= 12, "frame \(frame): \(grey(image, 80, 60))")
            #expect(grey(image, 2, 2) > 200, "the square stays top-left")
        }
        let small = try await MediaStills.images(
            url: url, isImage: false, fps: FrameRate(30, 1), frames: [10], maximumSide: 80)
        #expect(small[10]?.width == 80)
    }

    @Test("Contrast is measured on the pixels the text changes, against what was behind them")
    func contrast() throws {
        func frame(text: Bool) throws -> CGImage {
            let context = try #require(CGContext(
                data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            if text {
                context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                context.fill(CGRect(x: 10, y: 10, width: 30, height: 10))
            }
            return try #require(context.makeImage())
        }
        let measured = try #require(MediaStills.contrast(
            withText: try frame(text: true), without: try frame(text: false), rect: CGRect(x: 0, y: 0, width: 1, height: 1)))
        #expect(measured.pixels == 300)
        #expect(abs(measured.text - 1) < 0.01 && abs(measured.background - 0.214) < 0.01)
        #expect(abs(measured.ratio - 3.98) < 0.05 && abs(measured.lightRatio - 3.98) < 0.05)
        #expect(MediaStills.contrast(
            withText: try frame(text: false), without: try frame(text: false), rect: CGRect(x: 0, y: 0, width: 1, height: 1)) == nil)
    }

    @Test("Fitting keeps the picture upright")
    func fit() throws {
        let context = try #require(CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 800,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 50, width: 200, height: 50))  // the top half
        let image = try #require(context.makeImage())
        let fitted = MediaStills.fit(image, maximumSide: 100)
        #expect(fitted.width == 100 && fitted.height == 50)
        #expect(grey(fitted, 50, 5) > 200 && grey(fitted, 50, 45) < 50)
        #expect(MediaStills.fit(image, maximumSide: 400).width == 200)
    }

    @Test("A sheet lays cells out in rows at the common shape; a strip draws frames, level, gaps and words")
    func sheetAndStrip() throws {
        let context = try #require(CGContext(
            data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 256,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let picture = try #require(context.makeImage())
        let cells = (0..<5).map { MediaStills.Cell(image: $0 == 3 ? nil : picture, label: "\($0 + 1) clip 0:0\($0).0", group: $0 / 3) }
        let sheet = try #require(MediaStills.sheet(cells, columns: 3, longEdge: 160))
        #expect(sheet.width == 3 * 160 + 4 * 4)
        #expect(sheet.height == 2 * 90 + 3 * 4)

        let strip = MediaStills.Strip(
            frames: [(0.5, picture), (1.5, nil)], levels: (0.1, Array(repeating: -20, count: 30)),
            gaps: [(start: 1, end: 2)], words: [(text: "xin chào", start: 0.2, end: 0.8)], from: 0, to: 3)
        let image = try #require(MediaStills.strip(strip, width: 800))
        #expect(image.width == 800)
        #expect(image.height == 225 + 22 + 110 + 44)
        let sound = MediaStills.Strip(
            frames: [], levels: (0.1, [-30]), gaps: [], words: [], from: 0, to: 1)
        #expect(MediaStills.strip(sound, width: 400)?.height == 22 + 110 + 44, "sound alone has no frame row")
        #expect(MediaStills.clock(75.25) == "1:15.3")

        // Zones shade the picture: the bottom caption bar of a portrait cell turns red, its middle stays black.
        let tall = try #require(CGContext(
            data: nil, width: 90, height: 160, bitsPerComponent: 8, bytesPerRow: 360,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        tall.setFillColor(CGColor(gray: 0, alpha: 1))
        tall.fill(CGRect(x: 0, y: 0, width: 90, height: 160))
        let portrait = try #require(tall.makeImage())
        let zoned = try #require(MediaStills.sheet(
            [MediaStills.Cell(image: portrait, label: "", group: 0, zones: SafeArea(top: 0.1, bottom: 0.2, sideWidth: 0.1, sideHeight: 0.3))],
            columns: 1, longEdge: 160))
        #expect(red(zoned, 20, 4 + 150) > 40)
        #expect(red(zoned, 20, 4 + 80) < 10)

        // A cut mark is a line through the strip.
        let marked = try #require(MediaStills.strip(
            MediaStills.Strip(frames: [], levels: nil, gaps: [], words: [], from: 0, to: 1, marks: [0.5]), width: 400))
        #expect(red(marked, 200, 30) > 200)
    }
}
