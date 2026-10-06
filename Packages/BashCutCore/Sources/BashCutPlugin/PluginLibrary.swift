import BashCutProject
import Foundation

/// One library pack inside the plugin folder (API 6): a folder with `pack.json` in the format `library import-pack`
/// reads, and the files its items name. The app lists its items in the plugin scope; they are read-only and go away
/// with the plugin, while anything placed from them is copied into the project first.
public struct PluginLibraryContribution: Codable, Sendable, Equatable {
    /// The pack folder, relative to the plugin folder.
    public let path: String

    public init(path: String) { self.path = path }

    public static let maximumPacks = 32

    func validate() throws {
        let components = NSString(string: path).pathComponents
        guard !path.isEmpty, path.count <= 512, !path.hasPrefix("/"), !path.hasPrefix("~"), !components.contains(".."),
            !path.contains("\0")
        else { throw PluginError.invalid("Library pack path \(path) must stay inside the plugin bundle") }
    }
}

/// The library items plugins ship in `contributes.library` packs (API 6). Each pack is read with
/// `LibraryPack.read`, so it has the format and checks of `library import-pack`; its folder must resolve inside the
/// plugin folder. Items keep their pack-relative paths prefixed with the pack folder, so the plugin folder is the root
/// `LibraryCatalog` resolves their files against, and `createdBy` names the plugin.
public enum PluginLibrary {
    /// Every item one plugin contributes, or why a pack could not be read.
    public static func items(of plugin: InstalledPlugin) -> (items: [LibraryItem], problems: [String]) {
        var items: [LibraryItem] = []
        var problems: [String] = []
        for pack in plugin.manifest.libraryPacks {
            do {
                items += try read(pack, of: plugin)
            } catch {
                problems.append("\(plugin.id): library pack \(pack.path): \(error.localizedDescription)")
            }
        }
        return (items, problems)
    }

    /// One pack's items, as the plugin scope lists them.
    public static func read(_ pack: PluginLibraryContribution, of plugin: InstalledPlugin) throws -> [LibraryItem] {
        let base = plugin.directory.resolvingSymlinksInPath().standardizedFileURL.path
        let folder = plugin.directory.appendingPathComponent(pack.path, isDirectory: true)
        let resolved = folder.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved == base || resolved.hasPrefix(base + "/") else {
            throw PluginError.invalid("the pack folder is outside the plugin")
        }
        let contents = try LibraryPack.read(folder)
        let prefix = NSString(string: pack.path).standardizingPath
        let createdBy: [String: JSONValue] = [
            "by": .string("plugin"), "plugin": .string(plugin.id), "pluginName": .string(plugin.manifest.displayName),
            "pluginVersion": .string(plugin.manifest.version),
        ]
        return contents.items.map { item in
            var item = LibraryItem(fields: item.fields, scope: .plugin)
            for key in ["file", "preview"] {
                if let path = item[key]?.string { item[key] = .string(prefix == "." ? path : prefix + "/" + path) }
            }
            item["createdBy"] = .object(createdBy)
            item["history"] = nil
            return item
        }
    }

    /// What the plugin scope of `LibraryCatalog` holds for `plugins` (in catalog order): their items and the folder
    /// each plugin's paths are relative to. An item whose ID is built in or came from an earlier plugin is left out,
    /// with a problem saying so, so a plugin cannot hide another item.
    public static func catalog(
        _ plugins: [InstalledPlugin], reserved: Set<String> = Set(LibraryBuiltIns.items.map(\.id))
    ) -> (items: [LibraryItem], roots: [String: URL], problems: [String]) {
        var items: [LibraryItem] = []
        var roots: [String: URL] = [:]
        var problems: [String] = []
        var taken = reserved
        for plugin in plugins where !plugin.manifest.libraryPacks.isEmpty && roots[plugin.id] == nil {
            let found = Self.items(of: plugin)
            problems += found.problems
            for item in found.items {
                guard taken.insert(item.id).inserted else {
                    problems.append("\(plugin.id): library item \(item.id) is already used; it is not listed")
                    continue
                }
                items.append(item)
            }
            roots[plugin.id] = plugin.directory
        }
        return (items, roots, problems)
    }
}
