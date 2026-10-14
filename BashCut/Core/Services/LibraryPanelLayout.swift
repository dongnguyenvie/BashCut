import Foundation

/// How one library panel draws its items (P1-10): the tile size and grid or list, remembered per panel in Settings.
public struct LibraryPanelLayout: Codable, Equatable, Sendable {
    /// 0 (small) … 1 (large).
    public var tileSize = 0.4
    public var isList = false

    public init(tileSize: Double = 0.4, isList: Bool = false) {
        self.tileSize = min(max(tileSize, 0), 1)
        self.isList = isList
    }

    /// The narrowest a tile may be at this size, in points.
    public var tileMinimum: Double { Self.minimumRange.lowerBound + tileSize * (Self.minimumRange.upperBound - Self.minimumRange.lowerBound) }
    public static let minimumRange = 64.0...150.0
}

/// The widths of the library panel (P1-10): dragged between `widthRange`, or widened to `wideWidth` over the viewer.
public enum LibraryPanelMetrics {
    public static let widthRange: ClosedRange<Double> = 300...520
    public static let wideWidth = 760.0
    /// The category sidebar of the wide panel.
    public static let sidebarWidth = 160.0
    /// Screens at least this wide start the panel at `roomyWidth`, narrower ones at the range's minimum.
    public static let roomyScreen = 1680.0
    public static let roomyWidth = 372.0

    public static func defaultWidth(screenWidth: Double) -> Double {
        screenWidth >= roomyScreen ? roomyWidth : widthRange.lowerBound
    }

    public static func clamp(_ width: Double) -> Double { min(max(width.rounded(), widthRange.lowerBound), widthRange.upperBound) }
}
