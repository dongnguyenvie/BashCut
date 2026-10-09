import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import Foundation

/// Installing one approved plugin: its setup recipes, then placing and trusting its files. Single installs and
/// bundles both run through here.
extension PluginManagerModel {
    /// Runs the plugin's setup recipes, places its files (or a link) and trusts them; a repair only reruns setup.
    func performInstall(_ pending: PendingPluginInstall, reporter: JobReporter?) async throws {
        let plugin = pending.plugin
        let recipes = plugin.manifest.dependencies.compactMap { dependency in dependency.install.map { (dependency, $0) } }
        PluginFolders.prepare(plugin.id)
        let report: @Sendable (PluginRecipeOutput) -> Void = { [weak self] output in
            Task { @MainActor in self?.recipeOutput(output, reporter: reporter) }
        }
        if pending.repair {
            try trust.validateSetup(of: plugin)
            for (index, (dependency, recipe)) in recipes.enumerated() {
                installStep = String(format: String(localized: "Setting up %@ (%d of %d)…"), dependency.name, index + 1, recipes.count)
                try await PluginRecipeRunner.run(recipe.command, plugin: plugin, directory: plugin.directory, output: report)
            }
            // Approving the setup ran the plugin's own code, so its files are pinned like an install from the
            // registry; before, a plugin set up this way (a linked or copied folder) still said "Not approved yet".
            if trust.availability(of: plugin) == .untrusted { try trust.trust(plugin) }
            await checkHealthNow(plugin)
            return
        }
        let source = plugin.directory
        let manifest = plugin.manifest
        guard let installRoot = installRoot(for: pending.scope) else {
            throw PluginError.invalid("Open or save a project to add a plugin to it")
        }
        let destination = installRoot.appendingPathComponent(manifest.id, isDirectory: true)
        let replacing = pending.replacing
        let stagingRoot = installRoot.appendingPathComponent(".staging-\(UUID().uuidString)")
        let staged = stagingRoot.appendingPathComponent(manifest.id, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stagingRoot) }
        // Link (developer mode) places a link to the developer's folder, once it still holds the reviewed files.
        let linkTarget = pending.mode == .link ? pending.local : nil
        try await Task.detached {
            let manager = FileManager.default
            try manager.createDirectory(at: installRoot, withIntermediateDirectories: true)
            guard replacing || !manager.fileExists(atPath: destination.path) else {
                throw PluginError.invalid("Plugin \(manifest.id) is already installed")
            }
            try manager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            if let linkTarget, let folder = linkTarget.sourceFolder {
                try linkTarget.checkSourceUnchanged()
                try manager.createSymbolicLink(at: staged, withDestinationURL: folder.resolvingSymlinksInPath())
            } else {
                try manager.copyItem(at: source, to: staged)
            }
            _ = try InstalledPlugin(manifest: manifest, directory: staged).entrypointURL()
        }.value
        let stagedPlugin = InstalledPlugin(manifest: manifest, directory: staged)
        for (index, (dependency, recipe)) in recipes.enumerated() {
            installStep = String(format: String(localized: "Setting up %@ (%d of %d)…"), dependency.name, index + 1, recipes.count)
            try await PluginRecipeRunner.run(recipe.command, plugin: stagedPlugin, directory: staged, output: report)
        }
        try Task.checkCancellation()
        if replacing { stopSession(manifest.id) }
        try await Task.detached { try Self.place(staged, at: destination, root: installRoot) }.value
        // The user approved these exact files: pin them so later changes need approval again.
        if let installed = PluginCatalog.discover(in: [installRoot]).plugins.first(where: { $0.id == manifest.id }) {
            var origin = pending.local?.origin
            origin?.installedAt = Date()
            try? sources.set(origin, for: installed.directory)
            try trust.trust(installed)
            await checkHealthNow(installed)
        }
    }

    private func recipeOutput(_ output: PluginRecipeOutput, reporter: JobReporter?) {
        switch output {
        case .progress(let value, let text):
            installProgress = value
            if let text { installStep = text }
            reporter?.progress(value, detail: text)
        case .line(let text):
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            installLog.append(text)
            if installLog.count > 500 { installLog.removeFirst(installLog.count - 500) }
            reporter?.detail(text)
        }
    }
}
