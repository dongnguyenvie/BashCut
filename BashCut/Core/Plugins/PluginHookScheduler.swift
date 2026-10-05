import Foundation

/// Decides which hook deliveries start, so one edit heard by hundreds of plugins never starts hundreds of plugin
/// processes at once (#99):
///
/// - at most `limit` deliveries run at a time across all plugins;
/// - one runs per plugin at a time, and its other events wait in its own queue, each kind once;
/// - plugins take turns: a plugin that just ran goes behind every plugin already waiting.
///
/// The caller keeps the latest payload per key, so a newer event replaces a waiting one of the same kind.
public struct PluginHookScheduler<Key: Hashable> {
    /// Four, or fewer on a Mac with fewer cores: enough to keep hooks responsive without competing with playback.
    public static var defaultLimit: Int { min(4, max(1, ProcessInfo.processInfo.activeProcessorCount)) }

    public let limit: Int
    public private(set) var running: Set<String> = []
    private var queues: [String: [Key]] = [:]
    /// Plugins with queued keys that are not running, in turn order.
    private var turns: [String] = []
    private var hasTurn: Set<String> = []

    public init(limit: Int = defaultLimit) { self.limit = max(1, limit) }

    /// Keys waiting to start.
    public var queued: Int { queues.values.reduce(0) { $0 + $1.count } }

    public mutating func enqueue(_ key: Key, plugin: String) {
        var queue = queues[plugin] ?? []
        guard !queue.contains(key) else { return }
        queue.append(key)
        queues[plugin] = queue
        if !running.contains(plugin) { takeTurn(plugin) }
    }

    /// The next delivery to start, now counted as running, or nil when the limit is reached or nothing waits.
    public mutating func next() -> (plugin: String, key: Key)? {
        guard running.count < limit, !turns.isEmpty else { return nil }
        let plugin = turns.removeFirst()
        hasTurn.remove(plugin)
        guard var queue = queues[plugin], !queue.isEmpty else { return next() }
        let key = queue.removeFirst()
        queues[plugin] = queue.isEmpty ? nil : queue
        running.insert(plugin)
        return (plugin, key)
    }

    /// Ends `plugin`'s running delivery; its next queued key waits for a new turn.
    public mutating func finish(_ plugin: String) {
        guard running.remove(plugin) != nil else { return }
        if queues[plugin] != nil { takeTurn(plugin) }
    }

    /// Drops every queued key. Running deliveries still call `finish`.
    public mutating func removeQueued() {
        queues.removeAll()
        turns.removeAll()
        hasTurn.removeAll()
    }

    private mutating func takeTurn(_ plugin: String) {
        if hasTurn.insert(plugin).inserted { turns.append(plugin) }
    }
}
