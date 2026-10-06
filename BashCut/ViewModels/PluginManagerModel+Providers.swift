import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// The library items of ready plugins' packs (#81): what `ProjectDocument.libraryCatalog` lists in the plugin scope.
struct PluginLibraryState: Equatable {
    var items: [LibraryItem] = []
    /// Each plugin's folder, which its items' paths are relative to.
    var roots: [String: URL] = [:]
    /// Packs that could not be read, and items left out because their ID was taken.
    var problems: [String] = []
    /// Changes whenever the items do, so library panels reload.
    var revision = 0
}

/// Providers of a capability, and the library packs and providers plugins add (#81).
extension PluginManagerModel {
    func providers(for capability: String) -> [PluginProviderChoice] {
        plugins.flatMap { plugin in
            (plugin.manifest.providers ?? []).compactMap { provider in
                guard provider.capability == capability else { return nil }
                return PluginProviderChoice(
                    pluginID: plugin.id, pluginName: plugin.manifest.displayName, provider: provider)
            }
        }.sorted {
            ($0.provider.priority, $0.provider.name) > ($1.provider.priority, $1.provider.name)
        }
    }

    /// Providers of `library.search` or `library.generate` in plugins that may run now that serve one of `kinds`.
    func libraryProviders(_ capability: String, kinds: [LibraryKind]) -> [PluginProviderChoice] {
        plugins.filter { availability[$0.id] == .ready }.flatMap { plugin in
            (plugin.manifest.providers ?? []).filter { provider in
                provider.capability == capability && kinds.contains(where: provider.serves)
            }.map { PluginProviderChoice(pluginID: plugin.id, pluginName: plugin.manifest.displayName, provider: $0) }
        }.sorted { ($0.provider.priority, $0.provider.name) > ($1.provider.priority, $1.provider.name) }
    }

    /// Reads the library packs of the plugins that may run now. A pack that cannot be read is left out and listed
    /// in `diagnostics`.
    func rebuildLibrary() {
        let ready = plugins.filter { availability[$0.id] == .ready && !$0.manifest.libraryPacks.isEmpty }
        let found = PluginLibrary.catalog(ready)
        diagnostics += found.problems
        guard found.items != library.items || found.roots != library.roots || found.problems != library.problems else {
            return
        }
        library = PluginLibraryState(
            items: found.items, roots: found.roots, problems: found.problems, revision: library.revision + 1)
    }
}
