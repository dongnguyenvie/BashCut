import Foundation
import OSLog

/// Plain-text debug log shared by the app, the `bashcut` CLI and `bashcut-mcp`, so one file shows what a
/// manual test did: `~/Library/Logs/BashCut/debug.log` (rotated to `debug.1.log` at 5 MB). Lines are
/// mirrored privately to the unified log under subsystem `app.bashcut`. Release is off by default;
/// `BASHCUT_DEBUG_LOG=1|0` overrides it, and `BASHCUT_DEBUG_LOG_PATH` selects an isolated destination.
public enum DebugLog {
    public static let url: URL = ProcessInfo.processInfo.environment["BASHCUT_DEBUG_LOG_PATH"]
        .map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BashCut/debug.log")
    /// Off inside test runners so tests never write to the user's log; `BASHCUT_DEBUG_LOG=1` forces it on.
    public static let enabled: Bool = {
        let info = ProcessInfo.processInfo
        switch info.environment["BASHCUT_DEBUG_LOG"] {
        case "0": return false
        case "1": return true
        default:
            #if DEBUG
            return !["swiftpm-testing-helper", "xctest"].contains(info.processName)
                && info.environment["XCTestConfigurationFilePath"] == nil
            #else
            return false
            #endif
        }
    }()

    private static let maximumBytes: UInt64 = 5 * 1024 * 1024
    private static let queue = DispatchQueue(label: "app.bashcut.debug-log")
    private static let writer = DebugLogWriter(url: url, maximumBytes: maximumBytes)
    private static let process = ProcessInfo.processInfo.processName + ":" + String(ProcessInfo.processInfo.processIdentifier)
    private static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    public static func write(_ category: String, _ message: @autoclosure () -> String) {
        guard enabled else { return }
        // One entry per line, so multi-line errors (usage text) stay greppable.
        let text = message().replacingOccurrences(of: "\n", with: " ⏎ ")
        Logger(subsystem: "app.bashcut", category: category).debug("\(text, privacy: .private)")
        let line = "\(Date().formatted(timestamp)) [\(process)] \(category): \(text)\n"
        queue.async { writer.append(line) }
    }

    /// Waits until queued lines are on disk; short-lived processes such as the CLI call it before exiting.
    public static func flush() { queue.sync {} }

}
