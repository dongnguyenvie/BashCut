import BashCutDocument
import BashCutPlugin
import BashCutProject
import SwiftUI

/// The part every library panel shares (#80): its items with search, pack, tag and scope filters, Add… and drops,
/// Save selection as…, and each item's context menu. `tile` draws one item; clicking it is the tile's job.
struct LibraryItemsSection<Tile: View>: View {
    @Bindable var document: ProjectDocument
    let kinds: [LibraryKind]
    /// What Save selection as… offers here.
    var saveKinds: [LibraryKind] = []
    /// The kind Add… and drops make from plain files (audio, sticker images); packs are always accepted.
    var fileKind: LibraryKind?
    /// The tile draws `LibraryItemBadges` itself (the Audio panel puts them after the title), so none in the corner.
    var badgesInTile = false
    var columns = [GridItem(.flexible())]
    /// Commands first in a library item's context menu (the Effects panel's Apply with…).
    var itemActions: (LibraryItem) -> [LibraryPanelAction] = { _ in [] }
    @ViewBuilder let tile: (LibraryItem) -> Tile

    @State var items: [LibraryItem] = []
    /// Starred references (this Mac) and the project's recent ones, newest first (D5).
    @State var favorites: [String] = []
    @State var recent: [String] = []
    /// The home view sections the user folded.
    @State var collapsed: Set<String> = []
    @State private var dropTargeted = false
    /// How many matches the panel draws; Show more adds a page. A new search or filter starts again.
    @State var shown = Self.pageSize
    static var pageSize: Int { 60 }

    var panel: String { document.ui.libraryTab.panelName }

    var filter: Binding<LibraryPanelFilter> {
        Binding(
            get: { document.ui.libraryFilters[panel] ?? LibraryPanelFilter() },
            set: { document.ui.libraryFilters[panel] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if document.ui.libraryWide {
                // Wide panel (P1-10): the categories on the left, the tiles on the right.
                header
                HStack(alignment: .top, spacing: 10) {
                    sidebar.frame(width: LibraryPanelMetrics.sidebarWidth - 10)
                    Divider()
                    VStack(alignment: .leading, spacing: 8) { searchRow; sourceChips; listing }
                }
            } else {
                header
                searchRow
                sourceChips
                listing
            }
        }
        .padding(4)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            document.addFilesToLibrary(urls, kind: fileKind)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .task(id: "\(document.libraryRevision):\(document.plugins.library.revision):\(document.fileURL?.path ?? "")") {
            load()
        }
        .onChange(of: filter.wrappedValue) { shown = Self.pageSize }
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            TextField("Search library…", text: filter.query).textFieldStyle(.roundedBorder)
            AllAssetsButton(document: document, query: filter.wrappedValue.query)
            filterMenu
        }
    }

    @ViewBuilder var listing: some View { if showsHome { homeSections } else { results } }

    func grid(_ items: [LibraryItem], fromOnePack: Bool = false) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(items, id: \.reference) { item in
                let starred = favorites.contains(item.reference)
                LibraryGridTile(
                    item: item, isFavorite: starred, showsBadges: !badgesInTile, hidesScope: fromOnePack,
                    toggleFavorite: { document.toggleLibraryFavorite(item, currently: starred) },
                    place: canPlaceFromTile(item) ? { document.placeFromLibrary(item) } : nil,
                    draggable: item.kind != .brand && item.kind != .voice,
                    content: { shownTile(item) })
                    .contextMenu { contextMenu(item) }
            }
        }
    }

    /// Plugin items by plugin, in the order they come, with the plugin's name and its packs' names.
    func pluginGroups(_ items: [LibraryItem]) -> [(plugin: String, name: String, packs: [String], items: [LibraryItem])] {
        var groups: [(plugin: String, name: String, packs: [String], items: [LibraryItem])] = []
        for item in items where item.scope == .plugin {
            let plugin = item.createdBy["plugin"]?.string ?? ""
            if let index = groups.firstIndex(where: { $0.plugin == plugin }) {
                groups[index].items.append(item)
                if let pack = item.pack, !groups[index].packs.contains(pack) { groups[index].packs.append(pack) }
            } else {
                let name = item.createdBy["pluginName"]?.string ?? plugin
                groups.append((plugin, name, item.pack.map { [$0] } ?? [], [item]))
            }
        }
        return groups
    }

    /// Search… and Generate…, when a plugin that may run provides them for this panel's kinds (#81).
    @ViewBuilder var providerButtons: some View {
        if !document.libraryProviders(PluginAPI.librarySearch, kinds: kinds).isEmpty {
            Button("Search…", systemImage: "magnifyingglass.circle") {
                document.beginLibrarySearch(PluginAPI.librarySearch, kinds: kinds)
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless)
            .help("Search a plugin's source for items to add to the library")
        }
        if !document.libraryProviders(PluginAPI.libraryGenerate, kinds: kinds).isEmpty {
            Button("Generate…", systemImage: "wand.and.stars") {
                document.beginLibrarySearch(PluginAPI.libraryGenerate, kinds: kinds)
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless)
            .help("Make new items with a plugin from a prompt")
        }
    }

    private var header: some View {
        HStack {
            Text("Library").font(.headline).lineLimit(1).layoutPriority(1)
            Spacer()
            if !saveKinds.isEmpty {
                Menu {
                    ForEach(saveKinds, id: \.self) { kind in
                        let title = ProjectDocument.kindTitle(kind)
                        Button(title.prefix(1).uppercased() + title.dropFirst()) {
                            document.beginSaveSelection(as: kind)
                        }
                    }
                } label: {
                    Label("Save selection as…", systemImage: "square.and.arrow.down")
                }
                .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Save selection as…")
                .disabled(document.selectedID == nil)
                .help("Save the selected item's style, framing, transition, grade or sound as a library item.")
            }
            providerButtons
            Button("Add…", systemImage: "plus") { document.chooseLibraryFiles(kind: fileKind) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help(fileKind == nil ? "Import a library pack" : "Add files or import a library pack. You can also drop them here.")
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Pack", selection: filter.pack) {
                Text("All packs").tag(String?.none)
                ForEach(Self.unique(items.compactMap(\.pack)), id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
            }
            Picker("Tag", selection: filter.tag) {
                Text("All tags").tag(String?.none)
                ForEach(Self.unique(items.flatMap(\.tags)), id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
            }
            if filter.wrappedValue.isActive {
                Divider()
                Button("Clear filters") { filter.wrappedValue = LibraryPanelFilter() }
            }
        } label: {
            Image(systemName: filter.wrappedValue.isActive
                ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Filter by pack or tag")
    }

    @ViewBuilder private func contextMenu(_ item: LibraryItem) -> some View { libraryMenu(item) }

    @ViewBuilder private func libraryMenu(_ item: LibraryItem) -> some View {
        let actions = itemActions(item)
        if !actions.isEmpty {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in Button(action.title, action: action.run) }
            Divider()
        }
        let starred = favorites.contains(item.reference)
        Button(starred ? "Remove from Favorites" : "Add to Favorites") {
            document.toggleLibraryFavorite(item, currently: starred)
        }
        Button("Duplicate & Edit…") { document.beginDuplicate(item) }
        if item.scope.isWritable {
            if [.transitionPreset, .look, .audio, .textPreset, .brand].contains(item.kind) || document.isMediaSticker(item) {
                Button("Edit…") { document.beginRename(item) }
            } else {
                Button("Rename…") { document.beginRename(item) }
            }
            if item.scope == .project {
                Button("Move to This Mac") { document.moveFromLibraryPanel(item, to: .user) }
            } else {
                Button("Move to Project") { document.moveFromLibraryPanel(item, to: .project) }
                    .disabled(document.fileURL == nil)
            }
        }
        Divider()
        Button("Show Source & License") { document.showLibraryItemInfo(item) }
        if document.libraryCatalog.fileURL(of: item) != nil {
            Button("Show in Finder") { document.revealLibraryFile(item) }
        }
        if item.scope.isWritable {
            Divider()
            Button("Remove from Library", role: .destructive) { document.removeFromLibraryPanel(item) }
        }
    }

    private func load() {
        do {
            let catalog = document.libraryCatalog
            items = try catalog.panelItems(kinds)
            favorites = (try? catalog.favorites()) ?? []
            recent = (try? catalog.recent()) ?? []
        } catch {
            items = LibraryBuiltIns.items.filter { $0.kind.map(kinds.contains) == true }
            document.message = error.localizedDescription
        }
    }

    static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.lowercased()).inserted }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// A context menu command for an entry a panel shows beside its library items.
struct LibraryPanelAction {
    let title: LocalizedStringKey
    let run: () -> Void
}

/// Small marks on an item: who made it when not built in, and where it is saved.
struct LibraryItemBadges: View {
    let item: LibraryItem
    /// Drawn in a row (after a title) instead of over a tile's corner: no inset.
    var inline = false
    /// The whole section comes from one pack and its header says so: no plugin or folder mark.
    var hidesScope = false

    var body: some View {
        HStack(spacing: 2) {
            if item.creator == "agent" {
                Image(systemName: "sparkles").help("Made by an agent")
            }
            switch hidesScope ? .builtIn : item.scope {
            case .project: Image(systemName: "folder").help("Saved in this project")
            case .user: Image(systemName: "desktopcomputer").help("Saved on this Mac")
            case .plugin: Image(systemName: "puzzlepiece.extension").help("From a plugin")
            case .builtIn: EmptyView()
            }
        }
        .font(.system(size: 9)).foregroundStyle(.secondary).padding(inline ? 0 : 3)
        .accessibilityElement(children: .combine)
    }
}

/// The library item sheet: Save selection as…, Duplicate & Edit… and Rename….
struct LibraryItemEditorSheet: View {
    @Bindable var document: ProjectDocument
    @Binding var request: LibraryEditorRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Form {
                TextField("Name", text: $request.name)
                TextField("Tags", text: $request.tags, prompt: Text("food, warm, hook"))
                TextField("Pack", text: $request.pack)
                if request.transition != nil {
                    TransitionPresetFields(document: document, preset: Binding(
                        get: { request.transition ?? TransitionPreset(kind: "dissolve") },
                        set: { request.transition = $0 }))
                }
                if request.look != nil {
                    FilterStackFields(
                        stack: Binding(get: { request.look ?? FilterStack() }, set: { request.look = $0 }),
                        keepsLUT: $request.keepsLUT)
                }
                if request.audio != nil {
                    LibraryAudioFields(audio: Binding(get: { request.audio ?? LibraryAudio() }, set: { request.audio = $0 }))
                }
                if request.sticker != nil {
                    LibraryStickerFields(sticker: Binding(
                        get: { request.sticker ?? LibrarySticker(stickerKind: "image") }, set: { request.sticker = $0 }))
                }
                if request.brand != nil {
                    BrandKitFields(document: document, params: Binding(
                        get: { request.brand ?? [:] }, set: { request.brand = $0 }))
                }
                if request.recipe != nil {
                    EffectRecipeFields(text: Binding(get: { request.recipe ?? "{}" }, set: { request.recipe = $0 }))
                }
                if request.textPreset != nil {
                    TextPresetFields(style: Binding(
                        get: { request.textPreset ?? LibraryTextPreset(textPreset: "bold-outline") },
                        set: { request.textPreset = $0 }))
                }
                if !isRename {
                    Picker("Save in", selection: $request.scope) {
                        Text("Project").tag(LibraryScope.project)
                        Text("This Mac").tag(LibraryScope.user)
                    }
                    .disabled(document.fileURL == nil)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { document.ui.libraryEditor = nil }.keyboardShortcut(.cancelAction)
                Button("Save") { document.commitLibraryEditor() }.keyboardShortcut(.defaultAction)
                    .disabled(request.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 380)
    }

    private var isRename: Bool {
        if case .rename = request.mode { return true }
        return false
    }

    private var title: LocalizedStringKey {
        switch request.mode {
        case .saveSelection(.brand): "New brand kit"
        case .saveSelection(let kind): "Save selection as \(ProjectDocument.kindTitle(kind))"
        case .duplicate: "Duplicate & Edit"
        case .rename:
            request.transition != nil ? "Edit transition" : request.look != nil ? "Edit look"
                : request.audio != nil ? "Edit audio" : request.sticker?.isMedia == true ? "Edit sticker"
                : request.textPreset != nil ? "Edit text style" : request.brand != nil ? "Edit brand kit"
                : request.recipe != nil ? "Edit effect" : "Rename"
        }
    }
}

/// An audio item's role and loop flag in the item sheet (#78); mood and genre are its tags.
struct LibraryAudioFields: View {
    @Binding var audio: LibraryAudio

    var body: some View {
        Picker("Use as", selection: $audio.role) {
            Text("Automatic").tag(String?.none)
            Text("Music").tag(String?.some("music"))
            Text("Sound effect").tag(String?.some("sfx"))
            Text("Ambience").tag(String?.some("ambience"))
        }
        .help("Music and ambience go on the Music layer, sound effects on the SFX layer.")
        Toggle("Loops seamlessly", isOn: Binding(get: { audio.loopable == true }, set: { audio.loopable = $0 }))
            .help("Placed longer than the file, a loopable sound repeats; another plays once.")
        if let line = LibraryAudioBadges.summary(audio) {
            Text(verbatim: line).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
