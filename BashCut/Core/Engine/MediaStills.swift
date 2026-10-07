@preconcurrency import AVFoundation
import AppKit
import BashCutProject
import CoreGraphics
import CoreText
import Foundation

/// Source frames as pictures for agents (P0-A5): exact frames of any media by source time, contact sheets with a
/// label per cell, and a filmstrip with the sound level, the gaps and the words under it. They read the file
/// itself, never the timeline, so footage can be looked at before it is placed.
public enum MediaStills {
    /// Exact source frames of a file, each fitted inside `maximumSide` pixels (nil keeps the source size). A still
    /// image is its own frame 0. Frames that cannot be decoded are left out.
    public static func images(
        url: URL, isImage: Bool, fps: FrameRate, frames: [Int], maximumSide: Int?
    ) async throws -> [Int: CGImage] {
        guard !frames.isEmpty else { return [:] }
        if isImage {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            else { throw ProjectError.invalid("The image \(url.lastPathComponent) cannot be read") }
            let fitted = maximumSide.map { fit(image, maximumSide: $0) } ?? image
            return Dictionary(uniqueKeysWithValues: frames.map { ($0, fitted) })
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        if let maximumSide { generator.maximumSize = CGSize(width: maximumSide, height: maximumSide) }
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var result: [Int: CGImage] = [:]
        for await image in generator.images(for: frames.map(fps.time)) {
            try Task.checkCancellation()
            if let picture = try? image.image { result[fps.frame(image.requestedTime)] = picture }
        }
        return result
    }

    /// `image` scaled down to fit inside `maximumSide` pixels; a smaller image is returned as is.
    public static func fit(_ image: CGImage, maximumSide: Int) -> CGImage {
        let largest = max(image.width, image.height)
        guard largest > maximumSide else { return image }
        let scale = Double(maximumSide) / Double(largest)
        let size = CGSize(width: max(1, (Double(image.width) * scale).rounded()),
                          height: max(1, (Double(image.height) * scale).rounded()))
        guard let context = canvas(Int(size.width), Int(size.height), flipped: false) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage() ?? image
    }

    /// Sound levels of a whole file measured like `media.analyze`, for media without a stored record.
    public static func levels(url: URL) async throws -> MediaAnalysis.Sound? {
        try await MediaAnalyzer.sound(AVURLAsset(url: url))
    }

    /// Removes all but the `limit` newest PNGs in `directory`.
    public static func prune(_ directory: URL, keeping limit: Int) {
        guard let values = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return }
        let modified = { (url: URL) in
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        let sorted = values.filter { $0.pathExtension == "png" }.sorted { modified($0) > modified($1) }
        for url in sorted.dropFirst(limit) { try? FileManager.default.removeItem(at: url) }
    }

    public static func png(_ image: CGImage) throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ProjectError.invalid("The picture could not be encoded")
        }
        return data
    }

    // MARK: Contact sheet

    public struct Cell: Sendable {
        public let image: CGImage?
        public let label: String
        /// Cells of one media share a label colour; the colour changes with the group.
        public let group: Int

        public init(image: CGImage?, label: String, group: Int) {
            self.image = image
            self.label = label
            self.group = group
        }
    }

    /// A grid of `cells`, `columns` wide, each cell `longEdge` pixels on its long side at the most common picture
    /// shape, pictures fitted inside on black with their label in the bottom-left corner.
    public static func sheet(_ cells: [Cell], columns: Int, longEdge: Int) -> CGImage? {
        let aspects = cells.compactMap(\.image).map { Double($0.width) / Double(max(1, $0.height)) }.sorted()
        let aspect = aspects.isEmpty ? 16.0 / 9 : aspects[aspects.count / 2]
        let cellWidth = aspect >= 1 ? longEdge : max(16, Int((Double(longEdge) * aspect).rounded()))
        let cellHeight = aspect >= 1 ? max(16, Int((Double(longEdge) / aspect).rounded())) : longEdge
        let columns = max(1, min(columns, cells.count))
        let rows = (cells.count + columns - 1) / columns
        let gap = 4
        let width = columns * cellWidth + (columns + 1) * gap
        let height = rows * cellHeight + (rows + 1) * gap
        guard let context = canvas(width, height) else { return nil }
        fill(context, CGRect(x: 0, y: 0, width: width, height: height), grey: 0.12)
        for (index, cell) in cells.enumerated() {
            let rect = CGRect(
                x: gap + (index % columns) * (cellWidth + gap), y: gap + (index / columns) * (cellHeight + gap),
                width: cellWidth, height: cellHeight)
            fill(context, rect, grey: 0)
            if let image = cell.image { draw(image, fittedIn: rect, context: context) }
            let colour: CGColor = cell.group.isMultiple(of: 2)
                ? CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1) : CGColor(red: 0.3, green: 0.9, blue: 1, alpha: 1)
            label(cell.label, at: CGPoint(x: rect.minX + 4, y: rect.maxY - 4),
                  Style(size: max(11, Double(cellWidth) / 14), colour: colour, anchor: .bottom), context: context)
        }
        return context.makeImage()
    }

    // MARK: Filmstrip

    public struct Strip: Sendable {
        public var frames: [(seconds: Double, image: CGImage?)]
        /// Sound level in dBFS per window, starting at source second 0.
        public var levels: (window: Double, values: [Double])?
        public var gaps: [(start: Double, end: Double)]
        public var words: [(text: String, start: Double, end: Double)]
        public var from: Double
        public var to: Double

        public init(
            frames: [(seconds: Double, image: CGImage?)], levels: (window: Double, values: [Double])?,
            gaps: [(start: Double, end: Double)], words: [(text: String, start: Double, end: Double)], from: Double,
            to: Double
        ) {
            self.frames = frames
            self.levels = levels
            self.gaps = gaps
            self.words = words
            self.from = from
            self.to = to
        }
    }

    /// Frames along the top (none for sound alone), then a time ruler, the sound level (−60…0 dBFS) with the gaps shaded, and the words at
    /// their times on two alternating lines.
    public static func strip(_ strip: Strip, width: Int) -> CGImage? {
        let count = max(1, strip.frames.count)
        let aspects = strip.frames.compactMap(\.image).map { Double($0.width) / Double(max(1, $0.height)) }.sorted()
        let aspect = aspects.isEmpty ? 16.0 / 9 : aspects[aspects.count / 2]
        let cellWidth = Double(width) / Double(count)
        // Sound alone has no frame row.
        let picture = strip.frames.isEmpty ? 0 : max(24, (cellWidth / aspect).rounded())
        let ruler = 22.0, wave = 110.0, text = 44.0
        let height = Int(picture + ruler + wave + text)
        guard let context = canvas(width, height), strip.to > strip.from else { return nil }
        let span = strip.to - strip.from
        let x = { (seconds: Double) in (seconds - strip.from) / span * Double(width) }
        fill(context, CGRect(x: 0, y: 0, width: width, height: height), grey: 0.1)
        for (index, frame) in strip.frames.enumerated() {
            let rect = CGRect(x: Double(index) * cellWidth, y: 0, width: cellWidth - 2, height: picture)
            fill(context, rect, grey: 0)
            if let image = frame.image { draw(image, fittedIn: rect, context: context) }
            label(clock(frame.seconds), at: CGPoint(x: rect.minX + 3, y: rect.maxY - 3), Style(size: 11, anchor: .bottom),
                  context: context)
        }
        let waveTop = picture + ruler
        for gap in strip.gaps where gap.end > strip.from && gap.start < strip.to {
            let rect = CGRect(x: x(max(gap.start, strip.from)), y: waveTop,
                              width: x(min(gap.end, strip.to)) - x(max(gap.start, strip.from)), height: wave + text)
            context.setFillColor(CGColor(red: 0.25, green: 0.45, blue: 1, alpha: 0.28))
            context.fill(rect)
        }
        drawRuler(context, in: CGRect(x: 0, y: picture, width: Double(width), height: ruler), from: strip.from, to: strip.to)
        if let levels = strip.levels {
            context.setFillColor(CGColor(red: 0.35, green: 0.95, blue: 0.55, alpha: 1))
            for column in 0..<width {
                let seconds = strip.from + Double(column) / Double(width) * span
                let index = Int(seconds / levels.window)
                guard levels.values.indices.contains(index) else { continue }
                let level = min(1, max(0, (levels.values[index] + 60) / 60))
                let bar = level * wave
                context.fill(CGRect(x: Double(column), y: waveTop + (wave - bar) / 2, width: 1, height: max(1, bar)))
            }
        }
        for (index, word) in strip.words.enumerated() where word.end > strip.from && word.start < strip.to {
            let line = index.isMultiple(of: 2) ? 0.0 : 1.0
            label(word.text, at: CGPoint(x: x(max(word.start, strip.from)), y: waveTop + wave + 4 + line * 20),
                  Style(size: 13, anchor: .top), context: context)
        }
        return context.makeImage()
    }

    private static func drawRuler(_ context: CGContext, in rect: CGRect, from: Double, to: Double) {
        let span = to - from, top = rect.minY
        let step = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300].first { span / $0 <= 12 } ?? 600
        var tick = (from / step).rounded(.up) * step
        context.setFillColor(CGColor(gray: 0.6, alpha: 1))
        while tick <= to {
            let position = (tick - from) / span * rect.width
            context.fill(CGRect(x: position, y: top, width: 1, height: 6))
            label(clock(tick), at: CGPoint(x: position + 2, y: top + 4),
                  Style(size: 11, colour: CGColor(gray: 0.8, alpha: 1), anchor: .top), context: context)
            tick += step
        }
    }

    /// `m:ss.s`.
    public static func clock(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }

    // MARK: Drawing (top-left origin)

    /// An sRGB bitmap; `flipped` puts the origin top-left for layout.
    private static func canvas(_ width: Int, _ height: Int, flipped: Bool = true) -> CGContext? {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if flipped {
            context.translateBy(x: 0, y: Double(height))
            context.scaleBy(x: 1, y: -1)
        }
        return context
    }

    private static func fill(_ context: CGContext, _ rect: CGRect, grey: Double) {
        context.setFillColor(CGColor(gray: grey, alpha: 1))
        context.fill(rect)
    }

    private static func draw(_ image: CGImage, fittedIn rect: CGRect, context: CGContext) {
        let scale = min(rect.width / Double(image.width), rect.height / Double(image.height))
        let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(x: origin.x, y: origin.y + size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
    }

    private enum Anchor { case top, bottom }

    private struct Style {
        var size: Double
        var colour: CGColor = CGColor(gray: 1, alpha: 1)
        var anchor: Anchor
    }

    /// Text on a dark box; `point` is its top-left (`top`) or bottom-left (`bottom`) corner.
    private static func label(_ text: String, at point: CGPoint, _ style: Style, context: CGContext) {
        let (size, colour, anchor) = (style.size, style.colour, style.anchor)
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetImageBounds(line, context)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let boxHeight = ascent + descent + 4
        let top = anchor == .top ? point.y : point.y - boxHeight
        context.setFillColor(CGColor(gray: 0, alpha: 0.6))
        context.fill(CGRect(x: point.x - 2, y: top, width: max(bounds.width, 1) + 6, height: boxHeight))
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: point.x + 1, y: top + 2 + ascent)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
