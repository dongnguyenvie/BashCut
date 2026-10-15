import CoreGraphics

/// The size of a plugin view's window (plugin API 11 `location: window`, D2): 75% of the editor window, at least
/// 900×600, so a results grid with a sidebar and an inspector fits. The window remembers the size the user gives it.
public enum PluginWindowLayout {
    public static let share = 0.75
    public static let minimum = CGSize(width: 900, height: 600)
    /// Without an editor window to measure.
    public static let fallback = CGSize(width: 1100, height: 720)

    /// The size a new window gets over an editor window of size `editor`.
    public static func defaultSize(editor: CGSize?) -> CGSize {
        guard let editor else { return fallback }
        return CGSize(
            width: max(minimum.width, (editor.width * share).rounded()),
            height: max(minimum.height, (editor.height * share).rounded()))
    }
}
