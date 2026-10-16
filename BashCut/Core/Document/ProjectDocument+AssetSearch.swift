import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutProject
import Foundation

/// The All assets search (P2-B1, ⇧⌘F): one field over the whole local library, the project's media and its selects.
/// Return uses a result the way its panel does, Space previews it, and Search online hands the query to Online
/// resources.
extension ProjectDocument {
    /// The Online resources browser (bashcut-plugins `resources`): its window view and the search field that runs a
    /// search when submitted.
    enum OnlineResources {
        static let plugin = "bashcut.resources"
        static let view = "browse"
        static let queryField = "query"
    }

    /// Opens the search; the panel search field's All assets passes its text.
    func showAssetSearch(_ query: String? = nil) {
        DebugLog.write("ui", "all assets search")
        if let query { ui.assetSearchQuery = query }
        ui.showAssetSearch = true
    }

    /// Every library item, project first, read once when the search opens.
    func assetSearchLibrary() -> [LibraryItem] {
        do { return try libraryCatalog.items() } catch {
            message = error.localizedDescription
            return LibraryBuiltIns.items
        }
    }

    func assetSearchSections(_ query: String, library: [LibraryItem]) -> [AssetSearch.Section] {
        AssetSearch.search(query, library: library, media: project.media, selects: project.selects)
    }

    /// Why Return cannot use `asset` now, or nil when it can.
    func assetUnavailableReason(_ asset: AssetSearch.Asset) -> String? {
        if fileURL == nil { return String(localized: "Save the project first") }
        if case .library(let item) = asset, item.kind == .effectPreset || item.kind == .transitionPreset, selectedID == nil {
            return String(localized: "Select a clip first")
        }
        return nil
    }

    /// Return: what a click does in the item's panel. Media is appended, a select is placed at the end of its layer,
    /// effects and transitions go on the selected clip, a look grades the selection (or adds an adjustment layer),
    /// a brand kit becomes the project's, a voice opens the Voice tool, and everything else lands at the playhead.
    func useAsset(_ asset: AssetSearch.Asset) {
        if let reason = assetUnavailableReason(asset) {
            message = reason
            return
        }
        switch asset {
        case .media(let media): appendMedia(media)
        case .select(let select):
            do { try placeSelects([select], at: nil) } catch { message = error.localizedDescription }
        case .library(let item): useLibraryAsset(item)
        }
    }

    private func useLibraryAsset(_ item: LibraryItem) {
        switch item.kind {
        case .effectPreset, .transitionPreset: applyFromLibrary(item)
        case .look: if selectedID == nil { placeFromLibrary(item) } else { applyFromLibrary(item) }
        case .brand: applyBrandFromLibrary(item)
        case .voice: showTool(ToolID.voice)
        default: placeFromLibrary(item)
        }
    }

    /// Space: a sound plays (again: stops), footage and selects open in the source viewer (a select with its range
    /// marked), and other items are shown in their panel.
    func previewAsset(_ asset: AssetSearch.Asset) {
        switch asset {
        case .media(let media): previewSource(media)
        case .select(let select):
            guard let media = project.media.first(where: { $0.id == select.media }) else { return }
            previewSource(media)
            guard sourceViewer.visible, sourceViewer.media?.id == media.id else { return }
            let fps = media.fps.value
            markSource(in: Int((select.from * fps).rounded(.down)), out: Int((select.to * fps).rounded()))
        case .library(let item):
            if item.kind == .audio { toggleLibraryPreview(item) } else { showAssetInPanel(item) }
        }
    }

    /// Opens the panel that lists `item`, searching for its name.
    func showAssetInPanel(_ item: LibraryItem) {
        guard let kind = item.kind else { return }
        if kind == .voice { return showTool(ToolID.voice) }
        guard let tab = LibraryTab.assets.first(where: { $0.panelName == kind.panel }) else { return }
        showLibraryTab(tab)
        if kind == .clip { ui.mediaSource = MediaLibrarySource.clips.rawValue }
        ui.libraryFilters[tab.panelName] = LibraryPanelFilter(query: item.name)
    }

    // MARK: Online

    /// Online resources when it is installed and ready, else a plugin that provides `library.search`; nil: neither.
    var onlineSearchTarget: OnlineSearchTarget? {
        if let plugin = plugins.plugin(OnlineResources.plugin), plugins.isReady(plugin),
           plugin.manifest.views.contains(where: { $0.id == OnlineResources.view }) {
            return .onlineResources(plugin)
        }
        return libraryProviders(PluginAPI.librarySearch, kinds: LibraryKind.allCases).isEmpty ? nil : .librarySearch
    }

    enum OnlineSearchTarget {
        case onlineResources(InstalledPlugin)
        case librarySearch
    }

    /// Search online: opens Online resources and searches it for `query` there, or opens the plugin search sheet.
    func searchOnline(_ query: String) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch onlineSearchTarget {
        case .onlineResources(let plugin):
            guard let view = plugin.manifest.views.first(where: { $0.id == OnlineResources.view }) else { return }
            DebugLog.write("ui", "search online resources")
            pluginViews.show(plugin, view: view)
            guard !text.isEmpty else { return }
            let model = pluginViews.model(plugin: plugin.id, view: view.id)
            model.values[OnlineResources.queryField] = .string(text)
            Task {
                do {
                    if model.tree == nil { _ = try await model.perform(nil) }
                    _ = try await model.perform(PluginViewEvent(node: OnlineResources.queryField, kind: .submit, value: .string(text)))
                } catch {
                    message = error.localizedDescription
                }
            }
        case .librarySearch:
            beginLibrarySearch(PluginAPI.librarySearch, kinds: LibraryKind.allCases)
            ui.librarySearch?.text = text
        case nil:
            message = String(localized: "Install Online resources from Plugins to search online")
        }
    }
}
