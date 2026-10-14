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
                columns: [GridItem(.adaptive(minimum: 72))],
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
            VStack(spacing: 3) {
                if let emoji = item.params["emoji"]?.string, item.params["stickerKind"]?.string ?? "emoji" == "emoji" {
                    Text(verbatim: emoji).font(.largeTitle).frame(height: 40)
                } else {
                    LibraryImage(
                        url: document.libraryCatalog.previewURL(of: item) ?? document.libraryCatalog.fileURL(of: item),
                        fallbackSymbol: item.params["stickerKind"]?.string == "video-alpha" ? "film" : LibraryKind.sticker.tileSymbol)
                        .frame(width: 40, height: 40)
                        .overlay(alignment: .bottomLeading) { kindBadge(item) }
                }
                LibraryTileCaption(item: item)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).disabled(document.fileURL == nil)
        .help(Text(verbatim: item.name))
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

/// An image item's picture (a sticker or a preview), read once per file: an image (a GIF, APNG or animated WebP
/// plays), or a movie's first frame with its transparency.
struct LibraryImage: View {
    let url: URL?
    /// The icon shown while there is no picture, and when the file is missing or will not load.
    var fallbackSymbol = "photo"
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                if Self.isAnimated(image) {
                    AnimatedImageView(image: image)
                } else {
                    Image(nsImage: image).resizable().scaledToFit()
                }
            } else {
                LibraryTileFallback(symbol: fallbackSymbol)
            }
        }
        .task(id: url) { image = await url.asyncMap(LibraryPictureLoader.picture) ?? nil }
    }
}

extension LibraryImage {
    static func isAnimated(_ image: NSImage) -> Bool {
        image.representations.contains { (($0 as? NSBitmapImageRep)?.value(forProperty: .frameCount) as? Int ?? 1) > 1 }
    }
}

/// An animated image that plays in a loop, scaled to fit.
private struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image { view.image = image }
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
