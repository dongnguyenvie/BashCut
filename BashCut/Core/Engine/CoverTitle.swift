import BashCutProject
import CoreGraphics
import Foundation

/// A title drawn on a cover still (#443): the text item's preset and style laid out on a canvas the size of the
/// cover, so its size follows each cover's short side and it is fitted to the cover's width, as on the timeline.
public enum CoverTitle {
    /// The title's default size as a fraction of the cover's short side: 0.12 is 130 px on a 1080-wide 9:16 cover
    /// (6.75 % of its height), big enough to read on a phone-sized thumbnail where the timeline presets' 0.04–0.085
    /// read as a caption. A starting point, not a rule: `export cover --title-size` overrides it, and a long title
    /// still shrinks to fit the cover's width.
    public static let defaultSize = 0.12

    /// `item` with its text size set to `size` (defaultSize when nil) of the cover's short side.
    public static func sized(_ item: Item, _ size: Double?) -> Item {
        var item = item, style = item["textStyle"]?.object ?? [:]
        style["size"] = .number(size ?? defaultSize)
        item["textStyle"] = .object(style)
        return item
    }

    /// `image` with the text item drawn over it, and the title's box as fractions of the cover (x and y from the
    /// top-left), for checking it against a platform's zones. Nil when the text draws nothing.
    public static func draw(_ item: Item, over image: CGImage) -> (image: CGImage, box: CGRect)? {
        let size = CGSize(width: image.width, height: image.height)
        guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let raster = TextRenderer.raster(item, size: size),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.draw(raster.bitmap, in: raster.bounds)
        guard let drawn = context.makeImage() else { return nil }
        let layout = TextRenderer.layout(item, size: size)
        let drawnBox = layout.map { CGRect(x: $0.minX, y: $0.minY, width: $0.maxX - $0.minX, height: $0.maxY - $0.minY) }
        let bounds = (drawnBox ?? raster.bounds).intersection(CGRect(origin: .zero, size: size))
        let box = CGRect(
            x: bounds.minX / size.width, y: (size.height - bounds.maxY) / size.height,
            width: bounds.width / size.width, height: bounds.height / size.height)
        return (drawn, box)
    }
}
