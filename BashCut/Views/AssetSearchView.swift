import BashCutDocument
import BashCutProject
import SwiftUI

/// ⇧⌘F, and All assets in a panel's search field (P2-B1): one search over the whole local library, the project's media
/// and its selects, grouped by kind, in the command palette's look. ↑↓ choose, Return or a click uses the item as its
/// panel would, Space (after moving with the arrows) previews it, and Search online hands the query to Online resources.
struct AssetSearchView: View {
    @Bindable var document: ProjectDocument
    let close: () -> Void
    @State private var library: [LibraryItem] = []
    @State private var selection = 0
    /// The arrows were used since the last typing: Space previews instead of typing a space.
    @State private var navigating = false
    @FocusState private var focused: Bool
    private var preview = LibraryAudioPreview.shared

    init(document: ProjectDocument, close: @escaping () -> Void) {
        self.document = document
        self.close = close
    }

    private var query: Binding<String> { Bindable(document.ui).assetSearchQuery }

    var body: some View {
        let sections = document.assetSearchSections(document.ui.assetSearchQuery, library: library)
        let results = AssetSearch.flattened(sections)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search all assets", text: query)
                    .textFieldStyle(.plain).font(.title3).focused($focused)
                    .onSubmit { use(results, at: selection) }
                    .onKeyPress(.upArrow) { move(-1, in: results) }
                    .onKeyPress(.downArrow) { move(1, in: results) }
                    .onKeyPress(.space) {
                        guard navigating, results.indices.contains(selection) else { return .ignored }
                        document.previewAsset(results[selection].asset)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }
                    .onExitCommand(perform: dismiss)
            }.padding(12)
            Divider()
            if document.ui.assetSearchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Search sounds, stickers, text styles, effects, transitions, looks, project media and selects.")
                    .foregroundStyle(.secondary).font(.callout).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            } else if results.isEmpty {
                Text("No matching asset").foregroundStyle(.secondary).padding(16)
            } else {
                list(sections, results: results)
            }
            Divider()
            footer
        }
        .paletteChrome()
        .onAppear {
            library = document.assetSearchLibrary()
            focused = true
        }
        .onChange(of: document.libraryRevision) { library = document.assetSearchLibrary() }
        .onChange(of: document.ui.assetSearchQuery) {
            selection = 0
            navigating = false
        }
    }

    private func list(_ sections: [AssetSearch.Section], results: [AssetSearch.Result]) -> some View {
        let indexByID = Dictionary(results.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.results) { result in
                                let index = indexByID[result.id] ?? 0
                                AssetSearchRow(document: document, result: result, selected: index == selection)
                                    .id(result.id)
                                    .onTapGesture { use(results, at: index) }
                            }
                        } header: {
                            sectionHeader(section)
                        }
                    }
                }.padding(.horizontal, 6).padding(.bottom, 6)
            }
            .frame(maxHeight: 420)
            .onChange(of: selection) {
                if results.indices.contains(selection) { proxy.scrollTo(results[selection].id) }
            }
        }
    }

    private func sectionHeader(_ section: AssetSearch.Section) -> some View {
        HStack(spacing: 6) {
            Text(Self.title(section.group)).font(.caption.weight(.semibold))
            Text(verbatim: "\(section.total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if section.total > section.results.count {
                Text("first \(section.results.count)").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 3)
        .background(Color(red: 0.11, green: 0.115, blue: 0.13))
    }

    private var footer: some View {
        let text = document.ui.assetSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let online = document.onlineSearchTarget != nil
        return HStack(spacing: 12) {
            Text("↩ or click: use · ↓ then Space: preview").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
                dismiss()
                // After the popover is gone, so the browser window or the plugin sheet takes the focus.
                DispatchQueue.main.async { document.searchOnline(text) }
            } label: {
                Label {
                    (text.isEmpty ? Text("Search online") : Text("Search online for “\(text)”"))
                        .lineLimit(1).truncationMode(.middle)
                } icon: {
                    Image(systemName: "globe")
                }
            }
            .buttonStyle(.borderless).font(.caption)
            .disabled(!online)
            .help(online ? Text("Open Online resources with this search") : Text("Install Online resources from Plugins to search online"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    static func title(_ group: AssetSearch.Group) -> LocalizedStringKey {
        switch group {
        case .media: "Project media"
        case .selects: "Selects"
        case .library(let kind): title(kind)
        }
    }

    private static func title(_ kind: LibraryKind) -> LocalizedStringKey {
        switch kind {
        case .audio: "Sounds"
        case .clip: "Library clips"
        case .sticker: "Stickers"
        case .textPreset: "Text styles"
        case .effectPreset: "Effects"
        case .transitionPreset: "Transitions"
        case .look: "Looks"
        case .voice: "Voices"
        case .brand: "Brand kits"
        }
    }

    private func move(_ step: Int, in results: [AssetSearch.Result]) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        selection = min(max(0, selection + step), results.count - 1)
        navigating = true
        return .handled
    }

    private func use(_ results: [AssetSearch.Result], at index: Int) {
        guard results.indices.contains(index) else { return }
        let asset = results[index].asset
        if let reason = document.assetUnavailableReason(asset) {
            document.message = reason
            return
        }
        dismiss()
        DispatchQueue.main.async { document.useAsset(asset) }
    }

    private func dismiss() {
        preview.stop()
        close()
    }
}

/// One result: a picture or icon, the name, where it comes from, and a play button for sounds.
private struct AssetSearchRow: View {
    let document: ProjectDocument
    let result: AssetSearch.Result
    let selected: Bool
    private var preview = LibraryAudioPreview.shared

    init(document: ProjectDocument, result: AssetSearch.Result, selected: Bool) {
        self.document = document
        self.result = result
        self.selected = selected
    }

    var body: some View {
        HStack(spacing: 10) {
            picture.frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 1) {
                title.lineLimit(1).truncationMode(.middle)
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if case .library(let item) = result.asset, item.kind == .audio {
                let playing = preview.playing == item.reference
                Button { document.toggleLibraryPreview(item) } label: {
                    Image(systemName: playing ? "stop.fill" : "play.fill").frame(width: 14)
                }
                .buttonStyle(.borderless).help(playing ? "Stop" : "Play")
                .accessibilityLabel(playing ? Text("Stop") : Text("Play"))
            }
        }
        .paletteRow(selected: selected)
    }

    @ViewBuilder private var picture: some View {
        switch result.asset {
        case .media(let media):
            LibraryTileFallback(symbol: media.isImage ? "photo" : media.kind == "audio" ? "waveform" : "film")
        case .select:
            LibraryTileFallback(symbol: "text.quote")
        case .library(let item):
            if let emoji = item.params["emoji"]?.string {
                Text(verbatim: emoji).font(.title2)
            } else if let url = document.libraryCatalog.previewURL(of: item) {
                LibraryImage(url: url, fallbackSymbol: item.kind?.tileSymbol ?? "photo")
            } else {
                LibraryTileFallback(symbol: item.kind?.tileSymbol ?? "photo")
            }
        }
    }

    private var title: Text {
        switch result.asset {
        case .media(let media): Text(verbatim: media.fileName)
        case .select(let select): Text(verbatim: select.quote.map { "“\($0)”" } ?? select.id)
        case .library(let item): LibraryView.title(item)
        }
    }

    /// Where it is and what it is, for telling apart items with the same name.
    private var detail: String {
        switch result.asset {
        case .media(let media):
            return media.isImage ? media.path : "\(media.path) · " + Self.seconds(media.durationSeconds)
        case .select(let select):
            let name = document.project.media.first { $0.id == select.media }?.fileName ?? select.media
            return "\(name) · \(Self.seconds(select.from))–\(Self.seconds(select.to)) · \(select.status)"
        case .library(let item):
            let seconds = item.params["seconds"]?.double.map(Self.seconds)
            let plugin = item.scope == .plugin ? item.createdBy["pluginName"]?.string : nil
            return [item.pack, plugin, ProjectDocument.scopeTitle(item.scope), item.params["role"]?.string, seconds]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private static func seconds(_ value: Double) -> String {
        value.isFinite ? String(format: "%.1f s", value) : "–"
    }
}
