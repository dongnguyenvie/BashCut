import BashCutTestSupport
import BashCutVisionAnalysis
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@Suite("Core vision analysis")
struct VisionAnalysisTests {
    /// A white 1280×720 picture with `text` in large black letters across its upper half.
    private func textPicture(_ text: String) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 1_280, height: 720, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1_280, height: 720))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 120, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]))
        context.textPosition = CGPoint(x: 120, y: 480) // CoreGraphics origin is the bottom left: upper half.
        CTLineDraw(line, context)
        return try #require(context.makeImage())
    }

    @Test("Sampling: every step from from up to to, at least one picture, a cap, and bad ranges refused")
    func sampling() throws {
        #expect(try VisionFrames.seconds(from: 0, to: 3, step: 1) == [0, 1, 2])
        #expect(try VisionFrames.seconds(from: 1.5, to: 2.6, step: 0.5) == [1.5, 2, 2.5])
        #expect(try VisionFrames.seconds(from: 2, to: 2, step: 1) == [2])
        #expect(throws: VisionError.self) { try VisionFrames.seconds(from: 0, to: 4_000, step: 1) }
        #expect(throws: VisionError.self) { try VisionFrames.seconds(from: 3, to: 1, step: 1) }
        #expect(throws: VisionError.self) { try VisionFrames.seconds(from: 0, to: 1, step: 0) }
    }

    @Test("Boxes are shares from the top left, clamped to the picture")
    func boxes() {
        #expect(VisionDetect.topLeft(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)) == [0.1, 0.4, 0.3, 0.4])
        #expect(VisionDetect.topLeft(CGRect(x: -0.1, y: 0.9, width: 0.3, height: 0.3)) == [0, 0, 0.2, 0.1])
        #expect(VisionDetect.topLeft(CGRect(x: 2, y: 2, width: 1, height: 1)) == [0, 0, 0, 0])
    }

    @Test("Text is read with its box in the upper half; a plain picture has no faces, people or text")
    func recognition() throws {
        let lines = try VisionDetect.text(textPicture("BASHCUT 2026"), languages: ["en-US"])
        let line = try #require(lines.first { $0.string.replacingOccurrences(of: " ", with: "").contains("BASHCUT") })
        #expect(line.box[1] < 0.5 && line.box[0] < 0.2 && line.confidence > 0.3)
        let blank = try textPicture("")
        #expect(try VisionDetect.text(blank, languages: []).isEmpty)
        let subjects = try VisionDetect.subjects(blank)
        #expect(subjects.faces.isEmpty && subjects.people.isEmpty)
    }

    @Test("A movie gives one upright picture per step at the second it shows; a still image gives one at 0")
    func frames() async throws {
        let video = try await TestFixtures.requireVideo()
        var seconds: [Double] = [], sizes: [Int] = []
        try await VisionFrames.forEach(.init(path: video.path, step: 0.5), maximumPixels: 1_280) { second, image in
            seconds.append(second)
            sizes.append(image.width)
        }
        #expect(seconds.count == 5 && seconds == seconds.sorted() && seconds.allSatisfy { $0 <= 2.002 })
        #expect(abs(seconds[2] - 1) <= 0.25 && sizes.allSatisfy { $0 == 320 })

        let folder = try TestFixtures.temporaryDirectory("vision")
        defer { try? FileManager.default.removeItem(at: folder) }
        let still = folder.appendingPathComponent("card.png")
        let destination = try #require(CGImageDestinationCreateWithURL(still as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try textPicture("TITLE"), nil)
        #expect(CGImageDestinationFinalize(destination))
        var stills: [Double] = []
        try await VisionFrames.forEach(.init(path: still.path, step: 1), maximumPixels: 640) { second, image in
            stills.append(second)
            #expect(image.width == 640)
        }
        #expect(stills == [0])
        // The range stops at the end of the file; past the cap is refused before any decode.
        var clamped = 0
        try await VisionFrames.forEach(.init(path: video.path, from: 1, to: 10_000, step: 0.5), maximumPixels: 64) { _, _ in clamped += 1 }
        #expect(clamped == 3)
        await #expect(throws: VisionError.self) {
            try await VisionFrames.forEach(.init(path: video.path, from: 0, step: 0.0001), maximumPixels: 64) { _, _ in }
        }
    }
}
