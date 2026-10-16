import AVFoundation
import BashCutDocument
import BashCutEngine
import BashCutProject
import SwiftUI

struct LibraryView: View {
    @Bindable var document: ProjectDocument
    @Bindable var pluginManager: PluginManagerModel
    @State private var search = ""
    @State private var audioTrack = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedStringKey(document.ui.libraryTab.rawValue)).font(.headline)
                Spacer()
                LibraryWideButton(document: document)
            }.padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch document.ui.libraryTab {
                    case .media: media
                    case .audio: audio
                    case .text: text
                    case .stickers: StickerLibraryView(document: document)
                    case .effects: EffectLibraryView(document: document)
                    case .filters: FilterLibraryView(document: document)
                    case .transitions:
                        TransitionLibraryView(document: document)
                    case .brand: BrandLibraryView(document: document)
                    case .tools: ToolsPanelView(document: document, pluginManager: pluginManager)
                    }
                    PluginActionStrip(document: document, placement: "panel." + document.ui.libraryTab.panelName)
                }.padding(10)
            }
            if document.ui.libraryTab.hasTileLayout {
                Divider()
                LibraryPanelFooter(document: document)
            }
        }.background(Color.white.opacity(0.025))
            .sheet(item: Bindable(document.ui).libraryEditor) { request in
                // Not `Binding(optional)`: it force-unwraps, and saving clears the request while the sheet closes.
                LibraryItemEditorSheet(
                    document: document,
                    request: Binding(
                        get: { document.ui.libraryEditor ?? request }, set: { document.ui.libraryEditor = $0 }))
            }
            .sheet(item: Bindable(document.ui).librarySearch) { request in
                LibrarySearchSheet(
                    document: document,
                    request: Binding(
                        get: { document.ui.librarySearch ?? request }, set: { document.ui.librarySearch = $0 }))
            }
    }

    /// Built-in names are UI strings to localize; saved names are user content.
    static func title(_ item: LibraryItem) -> Text {
        item.scope == .builtIn ? Text(LocalizedStringKey(item.name)) : Text(verbatim: item.name)
    }
    private var media: some View {
        VStack(alignment: .leading, spacing: 10) {
            MediaSourceChips(document: document, selection: mediaSourceBinding, counts: mediaSourceCounts)
            if mediaSource == .selects {
                SelectsListView(document: document)
            } else if mediaSource == .clips {
                clips
            } else {
                mediaGrid.mediaFileDrop(document)
            }
        }
    }

    /// Clip items (P2-H5): footage saved in the library, such as generated B-roll; a click places one at the playhead.
    private var clips: some View {
        LibraryItemsSection(
            document: document, kinds: [.clip], fileKind: .clip,
            itemActions: { item in
                document.fileURL == nil ? [] : [LibraryPanelAction(title: "Place at Playhead") { document.placeFromLibrary(item) }]
            },
            tile: { item in
                Button { document.placeFromLibrary(item) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        LibraryImage(url: document.libraryCatalog.previewURL(of: item) ?? document.libraryCatalog.fileURL(of: item),
                                     fallbackSymbol: LibraryKind.clip.tileSymbol).frame(height: 60)
                        LibraryTileCaption(item: item)
                    }
                }
                .buttonStyle(.plain).disabled(document.fileURL == nil)
                .help("Place at Playhead")
            })
    }

    private var mediaGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TextField("Search media…", text: $search).textFieldStyle(.roundedBorder)
                AllAssetsButton(document: document, query: search)
            }
            Button("Import footage…") { document.importMedia() }.disabled(document.fileURL == nil)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(visibleMedia) { media in
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            document.previewSource(media)
                        } label: {
                            MediaThumbnail(
                                media: media, root: document.fileURL?.deletingLastPathComponent(),
                                workspace: document.settings.workspace)
                        }.buttonStyle(.plain).help("Open source viewer")
                            .accessibilityLabel("Preview " + media.fileName).overlay { MediaWorkBadge(document: document, mediaID: media.id) }
                        Text(media.fileName).font(.caption2).lineLimit(1)
                        Text(mediaSummary(media)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Button("Append") { document.appendMedia(media) }.font(.caption2)
                            proxyBadge(media)
                        }
                    }
                    .onDrag { NSItemProvider(object: TimelineCanvas.mediaPasteboardPrefix + media.id as NSString) }
                    .help("Drag onto the timeline to place it on a layer")
                    .contextMenu {
                        Button("Create Preview Proxy") {
                            Task { try? await document.requestProxies(mediaIDs: [media.id], force: true) }
                        }.disabled(document.fileURL == nil || document.proxyState(media) == .queued)
                        let pluginActions = pluginManager.actions(at: "media.context")
                        if !pluginActions.isEmpty { Divider() }
                        ForEach(pluginActions) { action in
                            Button(action.title) { document.triggerPluginAction(action, mediaID: media.id) }
                                .disabled(!document.canRunPluginAction(action, mediaID: media.id))
                        }
                    }
                }
                PlaceholderTiles(document: document)
            }
            if visibleMedia.isEmpty {
                Text(emptyMediaMessage).foregroundStyle(.secondary).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    @ViewBuilder private func proxyBadge(_ media: Media) -> some View {
        switch document.proxyState(media) {
        case .ready:
            Text("Proxy").font(.system(size: 9)).foregroundStyle(.secondary)
                .help("Previews use a smaller copy of this clip; export uses the original.")
        case .queued:
            Text("Making proxy…").font(.system(size: 9)).foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }
    private func mediaSummary(_ media: Media) -> String {
        if media.isImage, let width = media.width, let height = media.height {
            return "\(width)×\(height) · " + String(localized: "Image")
        }
        let duration = String(format: "%.1fs", media.durationSeconds)
        let rate = String(format: "%.2f fps", media.fps.value)
        if let width = media.width, let height = media.height {
            return "\(width)×\(height) · \(rate) · \(duration)"
        }
        return "\(rate) · \(duration)"
    }
    private var audio: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Track", selection: $audioTrack) {
                ForEach(document.project.tracks.filter { $0.kind == "audio" }, id: \.id) { track in
                    Text(document.project.trackTitle(track)).tag(track.id)
                }
            }
            .task(id: document.project.tracks.map(\.id).joined(separator: ":")) {
                let audio = document.project.tracks.filter { $0.kind == "audio" }
                if !audio.contains(where: { $0.id == audioTrack }) {
                    audioTrack = (audio.first { $0.role == TrackRole.music } ?? audio.first)?.id ?? ""
                }
            }
            Button("Import audio…") { document.importMedia(kind: "audio", trackID: audioTrack) }.disabled(
                document.fileURL == nil || audioTrack.isEmpty)
            ForEach(document.project.media.filter { $0["kind"] == .string("audio") }) { media in
                HStack {
                    Image(systemName: "waveform")
                    Text(media.fileName).lineLimit(1)
                    Spacer()
                    Button("Insert") { document.appendMedia(media, track: audioTrack) }.disabled(audioTrack.isEmpty)
                }.font(.caption)
                    .onDrag { NSItemProvider(object: TimelineCanvas.mediaPasteboardPrefix + media.id as NSString) }
                    .contextMenu {
                        Button("Save to Library…") { document.beginSaveAudio(mediaID: media.id) }
                    }
            }
            Divider()
            LibraryItemsSection(
                document: document, kinds: [.audio], saveKinds: [.audio], fileKind: .audio, badgesInTile: true,
                itemActions: { item in
                    [
                        LibraryPanelAction(title: "Place at Playhead") { document.placeFromLibrary(item) },
                        LibraryPanelAction(title: "Analyze Length, Loudness & Tempo") { document.analyzeFromLibrary(item) },
                    ]
                },
                tile: { item in AudioLibraryTile(document: document, item: item) })
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryItemsSection(document: document, kinds: [.textPreset], saveKinds: [.textPreset]) { item in
                Button {
                    document.placeFromLibrary(item)
                } label: {
                    VStack {
                        TextPresetTile(item: item)
                        Self.title(item).font(.caption)
                    }.padding(8)
                }.buttonStyle(.bordered).disabled(document.fileURL == nil)
            }
        }
    }
}

private extension LibraryView {
    /// Kept in the document's UI state so `ui view --media-source` can switch it.
    var mediaSource: MediaLibrarySource { MediaLibrarySource(rawValue: document.ui.mediaSource) ?? .footage }

    var mediaSourceBinding: Binding<MediaLibrarySource> {
        Binding(get: { mediaSource }, set: { document.ui.mediaSource = $0.rawValue })
    }

    var mediaSourceCounts: [MediaLibrarySource: Int] {
        var counts: [MediaLibrarySource: Int] = [:]
        for media in document.project.media where media["kind"] != .string("audio") { counts[source(for: media), default: 0] += 1 }
        return counts
    }

    var visibleMedia: [Media] {
        document.project.media.filter {
            $0["kind"] != .string("audio")
                && source(for: $0) == mediaSource
                && (search.isEmpty || "\($0.path) \($0.fileName)".searchFolded.contains(search.searchFolded))
        }
    }

    var emptyMediaMessage: LocalizedStringKey {
        if !search.isEmpty { return "No matching media." }
        switch mediaSource {
        case .footage: return "Import footage to start editing."
        case .project: return "No project media."
        case .shared: return "No shared media in this project."
        case .selects, .clips: return ""
        }
    }

    func source(for media: Media) -> MediaLibrarySource {
        let path = media["originalPath"]?.string ?? media.path  // a converted copy counts where its original is
        if path.hasPrefix("@assets/") { return .shared }
        guard let root = document.fileURL?.deletingLastPathComponent(),
            let resolved = try? MediaPathResolver.resolve(
                path, projectRoot: root, workspaceRoot: document.settings.workspace)
        else { return .project }
        let footage = root.appendingPathComponent("footage").resolvingSymlinksInPath().standardizedFileURL
        let candidate = resolved.resolvingSymlinksInPath().standardizedFileURL
        if candidate.path == footage.path || candidate.path.hasPrefix(footage.path + "/") {
            return .footage
        }
        return .project
    }
}

private struct MediaThumbnail: View {
    let media: Media
    let root: URL?
    let workspace: URL?
    @State private var image: NSImage?
    @State private var thumbnailFrame = 0
    @State private var hovering = false
    private var mediaURL: URL? {
        guard let root else { return nil }
        return try? MediaPathResolver.resolve(
            media.path, projectRoot: root, workspaceRoot: workspace)
    }
    private var isOffline: Bool {
        guard let mediaURL else { return true }
        return !FileManager.default.fileExists(atPath: mediaURL.path)
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.5)
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
                if isOffline {
                    VStack {
                        HStack {
                            Label("Offline", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2.bold()).padding(4)
                                .background(.black.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius: 4))
                            Spacer()
                        }
                        Spacer()
                    }.padding(5).foregroundStyle(.orange)
                }
                if hovering, !isOffline, !media.isImage {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(scrubTime)
                                .font(.caption2.monospacedDigit()).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.black.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }.padding(5)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hovering = true
                        let width = max(1, geometry.size.width)
                        let fraction = Double(point.x / width).clamped(to: 0...1)
                        let raw = Int(fraction * Double(max(0, media.frames - 1)))
                        let bucket = max(1, media.frames / 30)
                        thumbnailFrame = min(media.frames - 1, raw / bucket * bucket)
                    case .ended:
                        hovering = false
                        thumbnailFrame = 0
                    }
                }
        }.frame(height: 100).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityValue(scrubTime)
            .task(id: media.path + ":\(thumbnailFrame)") {
                guard let mediaURL, !isOffline else { return }
                if media.kind == "image" {
                    image = StillImageMovie.decoded(mediaURL, maximumSide: 240).map { NSImage(cgImage: $0, size: .zero) }
                    return
                }
                if thumbnailFrame > 0 {
                    do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                }
                let generator = AVAssetImageGenerator(
                    asset: AVURLAsset(url: mediaURL))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 240, height: 240)
                let time = CMTime(
                    seconds: Double(thumbnailFrame) / media.fps.value, preferredTimescale: 60_000)
                if let result = try? await generator.image(at: time), !Task.isCancelled {
                    image = NSImage(cgImage: result.image, size: .zero)
                }
            }
    }
    private var scrubTime: String {
        let seconds = Double(thumbnailFrame) / media.fps.value
        return String(format: "%02d:%02d.%02d", Int(seconds) / 60, Int(seconds) % 60, Int(seconds * 100) % 100)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
