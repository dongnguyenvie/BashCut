import AVFoundation
import BashCutDocument
import BashCutProject
import SwiftUI

struct LibraryView: View {
    @Bindable var document: ProjectDocument
    @Bindable var pluginManager: PluginManagerModel
    @State private var search = ""
    @State private var mediaSource = MediaLibrarySource.footage
    @State private var audioTrack = ""
    @State private var captionSource = ""
    @State private var captionProvider = ""
    @State private var replaceGeneratedCaptions = true
    @State private var captionMessage = ""
    @State private var beatSource = ""
    @State private var beatProvider = ""
    @State private var beatMessage = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedStringKey(document.ui.libraryTab.rawValue)).font(.headline)
                Spacer()
            }.padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch document.ui.libraryTab {
                    case .media: media
                    case .audio: audio
                    case .text: text
                    case .stickers: stickers
                    case .effects: effects
                    case .filters: FilterLibraryView(document: document)
                    case .transitions:
                        TransitionLibraryView(document: document)
                    case .voice:
                        VoiceLibraryView(document: document, pluginManager: pluginManager)
                    }
                    PluginActionStrip(document: document, placement: "panel." + document.ui.libraryTab.panelName)
                }.padding(10)
            }
        }.background(Color.white.opacity(0.025))
    }
    private var media: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Media source", selection: $mediaSource) {
                ForEach(MediaLibrarySource.allCases) { source in
                    Text(LocalizedStringKey(source.title)).tag(source)
                }
            }
            .pickerStyle(.segmented)
            // The panel is too narrow for an inline label; it stays the accessibility label.
            .labelsHidden()
            TextField("Search media…", text: $search).textFieldStyle(.roundedBorder)
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
                            .accessibilityLabel("Preview " + URL(fileURLWithPath: media.path).lastPathComponent)
                        Text(URL(fileURLWithPath: media.path).lastPathComponent).font(.caption2).lineLimit(1)
                        Text(mediaSummary(media))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
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
            }
            if visibleMedia.isEmpty {
                Text(emptyMediaMessage).foregroundStyle(.secondary).font(.caption)
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
                    Text(track.name).tag(track.id)
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
                    Text(URL(fileURLWithPath: media.path).lastPathComponent).lineLimit(1)
                    Spacer()
                    Button("Insert") { document.appendMedia(media, track: audioTrack) }.disabled(audioTrack.isEmpty)
                }.font(.caption)
                    .onDrag { NSItemProvider(object: TimelineCanvas.mediaPasteboardPrefix + media.id as NSString) }
            }
            Divider()
            Text("Beat Detection").font(.headline)
            Picker("Source", selection: $beatSource) {
                ForEach(document.project.media.filter { $0["kind"] == .string("audio") }) { media in
                    Text(URL(fileURLWithPath: media.path).lastPathComponent).tag(media.id)
                }
            }
            Picker("Provider", selection: $beatProvider) {
                Text("Automatic").tag("")
                ForEach(pluginManager.providers(for: "audio.beats")) { choice in
                    Text("\(choice.provider.name) · \(choice.pluginName)").tag(choice.provider.id)
                }
            }
            .onChange(of: beatProvider) { _, value in
                let stored = document.project.preferredProvider(for: "audio.beats") ?? ""
                guard value != stored else { return }
                document.apply(
                    .setProviderPreference(
                        capability: "audio.beats", provider: value.isEmpty ? nil : value),
                    label: "Choose beat provider")
            }
            FindPluginButton(document: document, capability: "audio.beats")
            ProviderOptionsView(document: document, capability: "audio.beats", providerID: beatProvider)
            Button(pluginManager.calling.contains("audio.beats") ? "Detecting beats…" : "Detect beats") {
                detectBeats()
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                document.fileURL == nil || beatSource.isEmpty
                    || pluginManager.calling.contains("audio.beats"))
            if let bpm = document.project.beatBPM {
                Text("\(document.project.beatFrames.count) beats · \(bpm, format: .number.precision(.fractionLength(1))) BPM")
                    .font(.caption.monospacedDigit())
            }
            Text(beatMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .task(id: document.project.media.map(\.id).joined(separator: ":")) {
            pluginManager.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
            beatProvider = document.project.preferredProvider(for: "audio.beats") ?? ""
            let audio = document.project.media.filter { $0["kind"] == .string("audio") }
            if !audio.contains(where: { $0.id == beatSource }) { beatSource = audio.first?.id ?? "" }
        }
    }

    private func detectBeats() {
        beatMessage = ""
        Task {
            do {
                try await document.detectBeats(mediaID: beatSource)
                beatMessage = String(localized: "Beat grid updated")
            } catch { beatMessage = error.localizedDescription }
        }
    }
    private var text: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Auto Captions").font(.headline)
            Picker("Source", selection: $captionSource) {
                ForEach(document.project.media) { media in
                    Text(URL(fileURLWithPath: media.path).lastPathComponent).tag(media.id)
                }
            }
            Picker("Provider", selection: $captionProvider) {
                Text("Automatic").tag("")
                ForEach(pluginManager.providers(for: "captions.transcribe")) { choice in
                    Text("\(choice.provider.name) · \(choice.pluginName)").tag(choice.provider.id)
                }
            }
            .onChange(of: captionProvider) { _, value in
                let stored = document.project.preferredProvider(for: "captions.transcribe") ?? ""
                guard value != stored else { return }
                document.apply(
                    .setProviderPreference(
                        capability: "captions.transcribe", provider: value.isEmpty ? nil : value),
                    label: "Choose transcription provider")
            }
            FindPluginButton(document: document, capability: "captions.transcribe")
            ProviderOptionsView(document: document, capability: "captions.transcribe", providerID: captionProvider)
            Toggle("Replace existing captions", isOn: $replaceGeneratedCaptions)
            Button(
                pluginManager.calling.contains("captions.transcribe") ? "Transcribing…" : "Generate captions"
            ) {
                generateCaptions()
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                document.fileURL == nil || captionSource.isEmpty
                    || pluginManager.calling.contains("captions.transcribe"))
            Text(captionMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Divider()
            Menu("Import SRT…") {
                Button("Add captions…") { document.importCaptions() }
                Button("Replace captions…") { document.importCaptions(replace: true) }
            }.disabled(document.fileURL == nil)
            Button("Export SRT…", action: document.exportCaptions).disabled(document.fileURL == nil)
            ForEach(
                [
                    ("Bold Outline", "bold-outline", "Quá là ngon!"),
                    ("Cinematic Serif", "cinematic-serif", "a moment to remember"),
                    ("Keyword Sticker", "keyword-sticker", "BEST BITE"),
                    ("Place Card", "place-card", "BẾN THÀNH · QUẬN 1"),
                    ("Hook Title", "hook-title", "ĂN GÌ HÔM NAY?"),
                    ("Chapter Card", "chapter-card", "CHAPTER 01"),
                ], id: \.1
            ) { title, style, sample in
                Button {
                    document.addText(style: style, text: sample)
                } label: {
                    VStack {
                        Text(sample)
                            .font(
                                style == "cinematic-serif" || style == "chapter-card"
                                    ? .system(.body, design: .serif) : .headline)
                            .foregroundStyle(style == "keyword-sticker" ? .black : .white)
                            .frame(maxWidth: .infinity, minHeight: 55).background(.black.opacity(0.3))
                        Text(LocalizedStringKey(title)).font(.caption)
                    }.padding(8)
                }.buttonStyle(.bordered).disabled(document.fileURL == nil)
            }
        }
        .task(id: document.project.media.map(\.id).joined(separator: ":")) {
            pluginManager.refresh(projectRoot: document.fileURL?.deletingLastPathComponent())
            captionProvider = document.project.preferredProvider(for: "captions.transcribe") ?? ""
            if !document.project.media.contains(where: { $0.id == captionSource }) {
                captionSource = document.project.media.first?.id ?? ""
            }
        }
    }

    private func generateCaptions() {
        captionMessage = ""
        Task {
            do {
                try await document.generateCaptions(mediaID: captionSource, replace: replaceGeneratedCaptions)
                captionMessage = String(localized: "Captions generated")
            } catch { captionMessage = error.localizedDescription }
        }
    }
    private var stickers: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 55))]) {
            ForEach(["🔥", "😋", "👍", "💯", "⭐", "📍", "🍲", "😂"], id: \.self) { symbol in
                Button(symbol) { document.addText(style: "bold-outline", text: symbol) }
                    .font(.largeTitle).buttonStyle(.bordered).disabled(document.fileURL == nil)
            }
        }
    }
    private var effects: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Punch in 1.3×") {
                document.patchSelected(["transform": .object(["zoom": .number(1.3)])], label: "Punch in")
            }
            Button("Reset framing") {
                document.patchSelected(
                    ["transform": .object(["zoom": .number(1), "pan": .integer(0), "tilt": .integer(0)])],
                    label: "Reset framing")
            }
            Text("Select a clip. Animated effects and speed ramps are still in development.").font(
                .caption
            ).foregroundStyle(.secondary)
        }.disabled(document.selected == nil)
    }
}

private extension LibraryView {
    var visibleMedia: [Media] {
        document.project.media.filter {
            $0["kind"] != .string("audio")
                && source(for: $0) == mediaSource
                && (search.isEmpty || $0.path.localizedCaseInsensitiveContains(search))
        }
    }

    var emptyMediaMessage: LocalizedStringKey {
        if !search.isEmpty { return "No matching media." }
        switch mediaSource {
        case .footage: return "Import footage to start editing."
        case .project: return "No project media."
        case .shared: return "No shared media in this project."
        }
    }

    func source(for media: Media) -> MediaLibrarySource {
        if media.path.hasPrefix("@assets/") { return .shared }
        guard let root = document.fileURL?.deletingLastPathComponent(),
            let resolved = try? MediaPathResolver.resolve(
                media.path, projectRoot: root, workspaceRoot: document.settings.workspace)
        else { return .project }
        let footage = root.appendingPathComponent("footage").resolvingSymlinksInPath().standardizedFileURL
        let candidate = resolved.resolvingSymlinksInPath().standardizedFileURL
        if candidate.path == footage.path || candidate.path.hasPrefix(footage.path + "/") {
            return .footage
        }
        return .project
    }
}

private enum MediaLibrarySource: String, CaseIterable, Identifiable {
    case footage
    case project
    case shared

    var id: Self { self }
    var title: String {
        switch self {
        case .footage: "Footage"
        case .project: "Project"
        case .shared: "Shared"
        }
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
                if hovering, !isOffline {
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
