import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// Plugins that need other plugins (API 8 `requires`, #394).
extension PluginManagerModel {
    /// Shows every ready plugin whose requirements fail as `.needsPlugin`, so its actions, hooks, views, skills and
    /// providers stay off until the required plugins are installed, in range and ready. Runs on every rebuild; a
    /// plugin shown as `.needsPlugin` (only ever a ready one) is ready again first, so fixing a requirement takes effect
    /// at once.
    func applyRequirements() {
        for (id, state) in availability {
            if case .needsPlugin = state { availability[id] = .ready }
        }
        guard plugins.contains(where: { !$0.manifest.requirements.isEmpty }) else { return }
        let problems = PluginRequirements.problems(plugins) { availability[$0.id] == .ready }
        for (id, reason) in problems where availability[id] == .ready {
            availability[id] = .needsPlugin(reason)
        }
    }

    /// After a successful install (not a setup), offers the plugin's missing requirements and its setup if still needed.
    func offerMissingRequirements(after outcome: Result<JSONValue, any Error>, installing pending: PendingPluginInstall) {
        guard case .success = outcome, !pending.repair else { return }
        offerMissingRequirements(of: pending.plugin.id)
        offerSetupIfNeeded([pending.plugin.id])
    }

    /// Whether the plugin may run now: ready on its own and with its requirements met.
    func isReady(_ plugin: InstalledPlugin) -> Bool { availability[plugin.id] == .ready }

    /// Requirements of `plugin` no installed plugin meets, as `{id, version, inRegistry}`.
    func missingRequirements(_ plugin: InstalledPlugin) -> [(requirement: PluginRequirement, inRegistry: Bool)] {
        PluginRequirements.missing(plugin, installed: plugins).map { requirement in
            (requirement, registry?.entry(requirement.id) != nil)
        }
    }

    /// After an install, offers the first missing requirement that the registry has: its download and approval
    /// replace the finished install's, so the user approves (and later trusts) each plugin. Plugins not in the
    /// registry are named in the message instead.
    func offerMissingRequirements(of id: String) {
        guard let plugin = plugin(id) else { return }
        let missing = missingRequirements(plugin)
        guard !missing.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            if registry == nil { await refreshRegistry() }
            let names = missingRequirements(plugin).map(\.requirement.id).joined(separator: ", ")
            guard let next = missingRequirements(plugin).first(where: \.inRegistry) else {
                message = String(format: String(localized: "%@ also needs %@, which is not in the registry"),
                                 plugin.manifest.displayName, names)
                return
            }
            do {
                try await requestInstall(next.requirement.id)
                message = String(format: String(localized: "%@ needs %@: review its installation"),
                                 plugin.manifest.displayName, next.requirement.id)
            } catch {
                message = String(format: String(localized: "%@ needs %@: %@"), plugin.manifest.displayName,
                                 next.requirement.id, error.localizedDescription)
            }
        }
    }

    /// `requires` with each requirement's state, for `plugins list` and the plugin panel.
    func requirementsJSON(_ plugin: InstalledPlugin) -> JSONValue {
        .array(plugin.manifest.requirements.map { requirement in
            let installed = self.plugin(requirement.id)
            let state: String
            if let installed {
                state = requirement.range.contains(installed.manifest.version)
                    ? (availability[installed.id] ?? .untrusted).name : "wrong-version"
            } else {
                state = "missing"
            }
            var fields: [String: JSONValue] = [
                "id": .string(requirement.id), "version": .string(requirement.range.description), "state": .string(state),
            ]
            if let installed { fields["installed"] = .string(installed.manifest.version) }
            return .object(fields)
        })
    }
}
