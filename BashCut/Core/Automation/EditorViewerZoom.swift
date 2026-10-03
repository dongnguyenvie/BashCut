import Foundation

/// Viewer zoom: `fit` shows the whole frame; a percentage shows the output at that size (100 = one output pixel per
/// screen point) and scrolls. The menu in the viewer header and `ui view --viewer-zoom` use the same values.
public enum EditorViewerZoom {
    public static let choices = ["fit", "25", "50", "100", "200"]

    /// The scale for a choice: nil for fit, 0.5 for "50".
    public static func scale(_ choice: String) -> Double? {
        guard choice != "fit", let percent = Double(choice) else { return nil }
        return percent / 100
    }

    public static func choice(_ scale: Double?) -> String {
        guard let scale else { return "fit" }
        return String(Int((scale * 100).rounded()))
    }
}
