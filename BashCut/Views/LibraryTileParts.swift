import AVFoundation
import BashCutProject
import SwiftUI

extension LibraryKind {
    /// The icon a tile shows when it has no picture.
    var tileSymbol: String {
        switch self {
        case .audio: "waveform"
        case .textPreset: "textformat"
        case .sticker: "face.smiling"
        case .effectPreset: "sparkles"
        case .transitionPreset: "rectangle.2.swap"
        case .look: "camera.filters"
        case .voice: "mic"
        case .clip: "film"
        case .brand: "paintpalette"
        }
    }
}

/// A picture's stand-in when an item has no preview or its file will not load: the kind's icon, never an empty tile.
/// Tiles draw the item's name under the picture, so the icon alone is enough there.
struct LibraryTileFallback: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
    }
}

/// A tile caption: one line, the middle cut when it does not fit, the full name on hover.
struct LibraryTileCaption: View {
    let item: LibraryItem

    var body: some View {
        LibraryView.title(item).font(.caption2).lineLimit(1).truncationMode(.middle)
            .help(Text(verbatim: item.name))
    }
}

/// Reads the picture of an image or a movie for a library tile.
enum LibraryPictureLoader {
    /// A movie shows a frame from its middle (an animated graphic starts empty), the first with something in it.
    static func picture(_ url: URL) async -> NSImage? {
        guard LibrarySticker.videoExtensions.contains(url.pathExtension.lowercased()) else {
            return NSImage(contentsOf: url)
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        let seconds = ((try? await asset.load(.duration))?.seconds).flatMap { $0.isFinite ? $0 : nil } ?? 0
        for share in [0.5, 0.25, 0.75, 0.0] {
            let time = CMTime(seconds: seconds * share, preferredTimescale: 600)
            if let frame = try? await generator.image(at: time).image, !isBlank(frame) {
                return NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
            }
        }
        return nil
    }

    /// Whether a picture is (almost) fully transparent, so it would draw as an empty tile.
    static func isBlank(_ image: CGImage) -> Bool {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipFirst, image.alphaInfo != .noneSkipLast else { return false }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        return !stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 12 }
    }
}
