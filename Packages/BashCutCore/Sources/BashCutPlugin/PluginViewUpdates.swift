import BashCutProject
import Foundation

/// A view update a session plugin sent without a request (#409, host feature `viewUpdate`): the line
/// `{"type":"viewUpdate","view":"<id>","body":[…],"title"?,"state"?,"notify"?}` from a background job or a timer; or
/// its overlay set (#407, `{"type":"overlays","overlays":[…]}`, `view` nil).
public struct PluginViewUpdate: Sendable {
    public let pluginID: String
    /// The view to redraw; nil for an overlay set.
    public let view: String?
    /// The update as a view answer (`body`, `title`?, `state`?, `notify`?), parsed by `PluginViewTree(parsing:)`; for
    /// an overlay set, `{"overlays": […]}` (`PluginOverlay.parse`).
    public let answer: JSONValue

    public init(pluginID: String, view: String?, answer: JSONValue) {
        self.pluginID = pluginID
        self.view = view
        self.answer = answer
    }
}

/// Where session plugins' view updates go. The app subscribes and draws an update only in a view on screen; with no
/// subscriber they are dropped. Sessions check each update first (`PluginViewUpdateLimiter`), so a plugin that sends
/// too many or too large ones loses them instead of slowing the app.
public final class PluginViewUpdates: @unchecked Sendable {
    public static let shared = PluginViewUpdates()

    /// A subscription; dropping it unsubscribes.
    public final class Subscription: @unchecked Sendable {
        private weak var center: PluginViewUpdates?
        private let id: UUID

        fileprivate init(center: PluginViewUpdates, id: UUID) {
            self.center = center
            self.id = id
        }

        deinit { center?.unsubscribe(id) }
    }

    private let lock = NSLock()
    private var handlers: [UUID: @Sendable (PluginViewUpdate) -> Void] = [:]

    public init() {}

    public func subscribe(_ handler: @escaping @Sendable (PluginViewUpdate) -> Void) -> Subscription {
        let id = UUID()
        lock.withLock { handlers[id] = handler }
        return Subscription(center: self, id: id)
    }

    fileprivate func unsubscribe(_ id: UUID) { lock.withLock { handlers[id] = nil } }

    public func post(_ update: PluginViewUpdate) {
        for handler in lock.withLock({ Array(handlers.values) }) { handler(update) }
    }
}

/// Per-plugin limits on view updates (#409): at most `maximumBytes` per update, and a token bucket of `burst` updates
/// refilled at `perSecond`; updates over either are dropped (and counted).
public struct PluginViewUpdateLimiter: Sendable {
    public static let maximumBytes = 512 * 1024
    public static let perSecond = 10.0
    public static let burst = 20.0

    private var tokens = Self.burst
    private var last: TimeInterval?
    /// Updates dropped so far.
    public private(set) var dropped = 0

    public init() {}

    /// Whether an update of `bytes` sent at `now` (seconds, any monotonic clock) may go through.
    public mutating func allow(bytes: Int, now: TimeInterval) -> Bool {
        if let last { tokens = min(Self.burst, tokens + max(0, now - last) * Self.perSecond) }
        last = now
        guard bytes <= Self.maximumBytes, tokens >= 1 else {
            dropped += 1
            return false
        }
        tokens -= 1
        return true
    }
}
