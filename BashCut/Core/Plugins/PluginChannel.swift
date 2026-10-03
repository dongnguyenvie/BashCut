import Foundation

/// How this copy of BashCut was distributed, which decides where plugins may come from.
///
/// - `direct` (Developer ID download, `scripts/run.sh` builds): plugins inside the app, in the user's plugin folder,
///   in a project's `.bashcut/plugins` and from the registry.
/// - `appStore` (sandboxed builds): only plugins inside the app. App Store Review Guideline 2.5.2 forbids
///   downloading code, and the sandbox would stop most downloaded tools anyway.
public enum PluginChannel: String, Sendable {
    case direct
    case appStore = "app-store"

    public static var current: PluginChannel {
        #if BASHCUT_APP_STORE
            return .appStore
        #else
            if let forced = ProcessInfo.processInfo.environment["BASHCUT_PLUGIN_CHANNEL"].flatMap(PluginChannel.init) {
                return forced
            }
            return ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil ? .direct : .appStore
        #endif
    }

    /// Plugins outside the app bundle (user folder, project folder, registry) may be installed and run.
    public var allowsUserPlugins: Bool { self == .direct }
}
