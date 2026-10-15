import BashCutProject
import CoreImage
import Foundation

/// A look's tile in the Filters panel (P2-B3): a small still of the viewer's frame graded the way the look grades a
/// clip (`BashCutCompositor.graded`, the export path), so the tile shows what a click will do.
public enum LookPreview {
    /// `base` graded by `color` (exposure, contrast, saturation, lutStrength) and the LUT at `lut`, if any.
    public static func render(base: CGImage, color: [String: JSONValue], lut: URL?) throws -> CGImage {
        let cube = try lut.map(cached)
        let input = CIImage(cgImage: base)
        let graded = BashCutCompositor.graded(input, properties: ["color": .object(color)], lut: cube)
            .cropped(to: input.extent)
        guard let image = context.createCGImage(
            graded, from: input.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        else { throw ProjectError.invalid("The look preview could not be drawn") }
        return image
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// Parsed LUTs by file, so a new frame does not read every .cube again; the oldest go past `lutLimit`.
    nonisolated(unsafe) private static var luts: [URL: CubeLUT] = [:]
    nonisolated(unsafe) private static var order: [URL] = []
    private static let lock = NSLock()
    static let lutLimit = 48

    private static func cached(_ url: URL) throws -> CubeLUT {
        if let hit = lock.withLock({ luts[url] }) { return hit }
        let loaded = try CubeLUT.load(url)
        lock.withLock {
            if luts.updateValue(loaded, forKey: url) == nil { order.append(url) }
            while order.count > lutLimit { luts[order.removeFirst()] = nil }
        }
        return loaded
    }
}
