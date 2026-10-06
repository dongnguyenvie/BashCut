import BashCutDocument
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
    var columns = [GridItem(.flexible())]
    /// Entries kept outside the library that the panel shows as items, searched and filtered with them (the
    /// Filters panel's style kits and project looks); their context menu is `extraActions`.
    var extraItems: [LibraryItem] = []
    var extraActions: (LibraryItem) -> [LibraryPanelAction] = { _ in [] }
    /// Commands first in a library item's context menu (the Effects panel's Apply with…).
    var itemActions: (LibraryItem) -> [LibraryPanelAction] = { _ in [] }
    @ViewBuilder let tile: (LibraryItem) -> Tile

    @State private var items: [LibraryItem] = []
    @State private var dropTargeted = false

    private var panel: String { document.ui.libraryTab.panelName }

    private var filter: Binding<LibraryPanelFilter> {
        Binding(
            get: { document.ui.libraryFilters[panel] ?? LibraryPanelFilter() },
            set: { document.ui.libraryFilters[panel] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(spacing: 6) {
                TextField("Search library…", text: filter.query).textFieldStyle(.roundedBorder)
                filterMenu
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(visibleItems, id: \.reference) { item in
                    tile(item)
                        .overlay(alignment: .topTrailing) { LibraryItemBadges(item: item) }
                        .contextMenu { contextMenu(item) }
                }
            }
            if visibleItems.isEmpty {
                Text(filter.wrappedValue.isActive ? "No matching items." : "Nothing in this library yet.")
                    .font(.caption).foregroundStyle(.secondary)
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
        .task(id: "\(document.libraryRevision):\(document.fileURL?.path ?? "")") { load() }
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
            Button("Add…", systemImage: "plus") { document.chooseLibraryFiles(kind: fileKind) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help(fileKind == nil ? "Import a library pack" : "Add files or import a library pack. You can also drop them here.")
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Pack", selection: filter.pack) {
                Text("All packs").tag(String?.none)
                ForEach(Self.unique(allItems.compactMap(\.pack)), id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
            }
            Picker("Tag", selection: filter.tag) {
                Text("All tags").tag(String?.none)
                ForEach(Self.unique(allItems.flatMap(\.tags)), id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
            }
            Picker("Scope", selection: filter.scope) {
                Text("All scopes").tag(String?.none)
                ForEach(LibraryScope.allCases, id: \.self) { scope in
                    Text(ProjectDocument.scopeTitle(scope)).tag(String?.some(scope.rawValue))
                }
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
        .help("Filter by pack, tag or scope")
    }

    @ViewBuilder private func contextMenu(_ item: LibraryItem) -> some View {
        if extraItems.contains(where: { $0.reference == item.reference }) {
            ForEach(Array(extraActions(item).enumerated()), id: \.offset) { _, action in
                Button(action.title, role: action.destructive ? .destructive : nil, action: action.run)
            }
        } else {
            libraryMenu(item)
        }
    }

    @ViewBuilder private func libraryMenu(_ item: LibraryItem) -> some View {
        let actions = itemActions(item)
        if !actions.isEmpty {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in Button(action.title, action: action.run) }
            Divider()
        }
        Button("Duplicate & Edit…") { document.beginDuplicate(item) }
        if item.scope.isWritable {
            if item.kind == .transitionPreset || item.kind == .look || item.kind == .audio {
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

    private var visibleItems: [LibraryItem] {
        let filter = filter.wrappedValue
        let match = LibraryCatalog.Filter(
            tag: filter.tag, scope: filter.scope.flatMap(LibraryScope.init(rawValue:)), pack: filter.pack,
            query: filter.query.isEmpty ? nil : filter.query)
        return allItems.filter(match.matches)
    }

    private var allItems: [LibraryItem] { extraItems + items }

    private func load() {
        do {
            items = try document.libraryCatalog.panelItems(kinds)
        } catch {
            items = LibraryBuiltIns.items.filter { $0.kind.map(kinds.contains) == true }
            document.message = error.localizedDescription
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.lowercased()).inserted }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// A context menu command for an entry a panel shows beside its library items.
struct LibraryPanelAction {
    let title: LocalizedStringKey
    var destructive = false
    let run: () -> Void
}

/// Small marks on an item: who made it when not built in, and where it is saved.
struct LibraryItemBadges: View {
    let item: LibraryItem

    var body: some View {
        HStack(spacing: 2) {
            if item.creator == "agent" {
                Image(systemName: "sparkles").help("Made by an agent")
            }
            switch item.scope {
            case .project: Image(systemName: "folder").help("Saved in this project")
            case .user: Image(systemName: "desktopcomputer").help("Saved on this Mac")
            case .plugin: Image(systemName: "puzzlepiece.extension").help("From a plugin")
            case .builtIn: EmptyView()
            }
        }
        .font(.system(size: 9)).foregroundStyle(.secondary).padding(3)
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
        case .saveSelection(let kind): "Save selection as \(ProjectDocument.kindTitle(kind))"
        case .duplicate: "Duplicate & Edit"
        case .rename:
            request.transition != nil ? "Edit transition" : request.look != nil ? "Edit look"
                : request.audio != nil ? "Edit audio" : "Rename"
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
