import AVFoundation
import BashCutDocument
import BashCutProject
import SwiftUI

/// The Stickers panel (#64): emoji, image, animated and video-with-alpha stickers from every library scope, with
/// packs, tags, search and scope filters. A click places one at the playhead (image-like ones on the Overlay layer);
/// Add… and drops take image files and movies with alpha; Save selection as… saves the selected overlay item.
struct StickerLibraryView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibraryItemsSection(
                document: document, kinds: [.sticker], saveKinds: [.sticker], fileKind: .sticker,
                columns: [GridItem(.adaptive(minimum: 55))],
                itemActions: { item in
                    document.fileURL == nil ? [] : [LibraryPanelAction(title: "Place at Playhead") { document.placeFromLibrary(item) }]
                },
                tile: tile)
            Text("Click a sticker to place it at the playhead. Drop PNG, GIF or WebP images, or movies with alpha, to add your own.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tile(_ item: LibraryItem) -> some View {
        Button { document.placeFromLibrary(item) } label: {
            if let emoji = item.params["emoji"]?.string, item.params["stickerKind"]?.string ?? "emoji" == "emoji" {
                Text(verbatim: emoji).font(.largeTitle)
            } else {
                LibraryImage(url: document.libraryCatalog.previewURL(of: item) ?? document.libraryCatalog.fileURL(of: item))
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .bottomLeading) { kindBadge(item) }
            }
        }
        .buttonStyle(.bordered).disabled(document.fileURL == nil)
        .help(LibraryView.title(item))
    }

    @ViewBuilder private func kindBadge(_ item: LibraryItem) -> some View {
        switch item.params["stickerKind"]?.string {
        case "animated":
            Image(systemName: "photo.stack").help("Animated: placed as its first frame for now")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        case "video-alpha":
            Image(systemName: "film").help("Video with transparency")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

/// An image item's picture (a sticker or a preview), read once per file: an image's first frame, or a movie's first
/// frame with its transparency.
struct LibraryImage: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() } else { Image(systemName: "photo") }
        }
        .task(id: url) { image = await url.asyncMap(Self.picture) ?? nil }
    }

    private static func picture(_ url: URL) async -> NSImage? {
        guard LibrarySticker.videoExtensions.contains(url.pathExtension.lowercased()) else {
            return NSImage(contentsOf: url)
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}

/// A sticker's placing defaults in the item sheet (#64): size, position and animation; length stays as saved.
struct LibraryStickerFields: View {
    @Binding var sticker: LibrarySticker

    var body: some View {
        if sticker.isMedia {
            HStack {
                Slider(value: Binding(
                    get: { sticker.size ?? LibrarySticker.defaultSize }, set: { sticker.size = ($0 * 100).rounded() / 100 }),
                    in: 0.05...1) { Text("Size") }
                Text(verbatim: "\(Int(((sticker.size ?? LibrarySticker.defaultSize) * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
            }
            .help("The sticker's width as a share of the frame width")
            Picker("Position", selection: Binding(get: { positionName }, set: { setPosition($0) })) {
                if case .point = sticker.position { Text("As saved").tag("custom") }
                ForEach(StickerPosition.names, id: \.self) { name in Text(LocalizedStringKey(Self.title(name))).tag(name) }
            }
            .help("Named places keep the sticker inside the safe area")
            Picker("Animation", selection: Binding(
                get: { sticker.animation ?? "none" }, set: { sticker.animation = $0 == "none" ? nil : $0 })
            ) {
                Text("None").tag("none")
                ForEach(MotionPreset.all) { preset in Text(LocalizedStringKey(preset.title)).tag(preset.id) }
            }
        }
    }

    private var positionName: String {
        switch sticker.position {
        case .named(let name): name
        case .point: "custom"
        case nil: "center"
        }
    }

    private func setPosition(_ name: String) {
        guard name != "custom" else { return }
        sticker.position = .named(name)
    }

    static func title(_ name: String) -> String {
        switch name {
        case "center": "Center"
        case "top": "Top"
        case "bottom": "Bottom"
        case "left": "Left"
        case "right": "Right"
        case "top-left": "Top left"
        case "top-right": "Top right"
        case "bottom-left": "Bottom left"
        default: "Bottom right"
        }
    }
}
