import BashCutPlugin
import BashCutPlugins
import Foundation

/// Background file checks for the plugin catalog (#103): `refresh` lists plugins from what is already known, and
/// plugins whose files were not checked yet are checked here, off the main actor.
extension PluginManagerModel {
    /// Availability for one listing: the last check when it still holds, otherwise a full check now.
    func currentAvailability(_ plugin: InstalledPlugin) -> PluginAvailability {
        service.knownAvailability(plugin) ?? service.availability(plugin)
    }

    /// Sets each plugin's last known availability and returns the plugins whose files need a check: those not
    /// checked yet, or every one with `checkFiles`. Until checked, a plugin keeps its previous answer.
    func applyKnownAvailability(checkFiles: Bool) -> [InstalledPlugin] {
        var next: [String: PluginAvailability] = [:]
        var unchecked: [InstalledPlugin] = []
        for plugin in plugins {
            let known = service.knownAvailability(plugin)
            next[plugin.id] = known ?? availability[plugin.id] ?? .untrusted
            if checkFiles || known == nil { unchecked.append(plugin) }
        }
        availability = next
        return unchecked
    }

    /// Replaces the waiting checks with `list`; a newer refresh knows the current catalog better.
    func queueFileChecks(_ list: [InstalledPlugin]) {
        let running = !fileCheckQueue.isEmpty || !fileCheckBatch.isEmpty
        fileCheckQueue = list
        checkingFiles = Set(list.map(\.id)).union(fileCheckBatch)
        if !running, !list.isEmpty { Task { await runFileChecks() } }
    }

    /// Checks queued plugins' files off the main actor, a batch at a time, and applies each result while the
    /// catalog still has that installation.
    private func runFileChecks() async {
        while !fileCheckQueue.isEmpty {
            let batch = fileCheckQueue
            fileCheckQueue = []
            fileCheckBatch = Set(batch.map(\.id))
            let service = self.service
            let results = await Task.detached(priority: .utility) { Self.checkFiles(of: batch, service: service) }.value
            fileCheckBatch = []
            let current = Dictionary(plugins.map { ($0.id, $0.installationID) }, uniquingKeysWith: { first, _ in first })
            var changed = false
            for (plugin, state) in zip(batch, results)
            where current[plugin.id] == plugin.installationID && availability[plugin.id] != state {
                availability[plugin.id] = state
                changed = true
            }
            checkingFiles = Set(fileCheckQueue.map(\.id))
            if changed { rebuildActions() }
        }
    }

    /// Plugins are independent, so their folders are walked in parallel.
    private nonisolated static func checkFiles(
        of batch: [InstalledPlugin], service: CapabilityService
    ) -> [PluginAvailability] {
        let lock = NSLock()
        var results = [PluginAvailability](repeating: .untrusted, count: batch.count)
        DispatchQueue.concurrentPerform(iterations: batch.count) { index in
            let state = service.availability(batch[index])
            lock.lock()
            results[index] = state
            lock.unlock()
        }
        return results
    }
}
