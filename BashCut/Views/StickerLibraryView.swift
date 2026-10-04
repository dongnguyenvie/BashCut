import BashCutEngine
import SwiftUI

/// Image stickers from the user's library and from plugin sticker packs (placed as overlay clips), then emoji
/// stickers by category (inserted as text items).
struct StickerLibraryView: View {
    @Bindable var document: ProjectDocument
    @State private var images: [URL] = []
    @State private var packs: [ContributedStickerPack] = []

    private static let categories: [(title: String, symbols: [String])] = [
        (
            "Reactions",
            [
                "😂", "🤣", "😋", "😍", "🥰", "😎", "🤩", "🥳", "😱", "😭", "🥹", "😅",
                "🤔", "🤯", "😴", "🤤", "😤", "😡", "🥵", "🥶", "🤫", "🫣", "😏", "🙄",
            ]
        ),
        (
            "Gestures",
            [
                "👍", "👎", "👏", "🙌", "🙏", "👌", "✌️", "🤞", "🤟", "🤙", "💪", "👀",
                "👉", "👈", "👆", "👇", "✍️", "🫶", "🤝", "👋",
            ]
        ),
        (
            "Hearts and highlights",
            [
                "🔥", "💯", "⭐", "🌟", "✨", "💥", "💫", "⚡", "❤️", "🧡", "💛", "💚",
                "💙", "💜", "🖤", "💔", "💖", "💢", "💤", "💦", "🎯", "👑", "💎", "🏆",
            ]
        ),
        (
            "Food and drink",
            [
                "🍲", "🍜", "🍚", "🍱", "🍣", "🥢", "🍔", "🍕", "🍟", "🌮", "🥗", "🍗",
                "🥩", "🦐", "🍳", "🥖", "🍰", "🍩", "🍦", "🍓", "🥭", "🌶️", "☕", "🧋",
                "🍵", "🍺", "🥂", "🍹",
            ]
        ),
        (
            "Travel and places",
            [
                "📍", "🗺️", "🧭", "✈️", "🚗", "🛵", "🚌", "🚆", "⛵", "🏖️", "🏝️", "⛰️",
                "🏕️", "🏙️", "🏠", "🏨", "⛩️", "🌅", "🌃", "🌈", "☀️", "🌙", "🌧️", "❄️",
            ]
        ),
        (
            "Celebration",
            [
                "🎉", "🎊", "🎁", "🎂", "🎈", "🎆", "🧧", "🏮", "🎄", "🎃", "🎵", "🎶",
                "🎤", "🎬", "📸", "🎮", "⚽", "🏀",
            ]
        ),
        (
            "Animals and nature",
            [
                "🐶", "🐱", "🐼", "🐯", "🐷", "🐔", "🐟", "🦋", "🐝", "🌸", "🌺", "🌻",
                "🌹", "🍀", "🌴", "🌵", "🍁", "🌊",
            ]
        ),
        (
            "Signs and arrows",
            [
                "✅", "❌", "❗", "❓", "⚠️", "🚫", "🆕", "🆒", "🔝", "💡", "💰", "💸",
                "⏰", "📌", "🔔", "🔒", "➡️", "⬅️", "⬆️", "⬇️", "↗️", "↘️", "🔄", "➕",
            ]
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My stickers").font(.headline)
                Spacer()
                Button("Import stickers…", systemImage: "plus") {
                    document.importStickers()
                    images = ProjectDocument.stickerLibrary()
                }
            }
            if images.isEmpty {
                Text("Import PNG or GIF images to use them as stickers in any project.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 55))]) {
                ForEach(images, id: \.self) { url in
                    stickerButton(url).contextMenu {
                        Button("Remove sticker", role: .destructive) {
                            document.removeSticker(url)
                            images = ProjectDocument.stickerLibrary()
                        }
                    }
                }
            }
            ForEach(packs) { pack in
                Text(pack.title).font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 55))]) {
                    ForEach(pack.stickers, id: \.self) { url in stickerButton(url) }
                }
            }
            Divider()
            ForEach(Self.categories, id: \.title) { category in
                Text(LocalizedStringKey(category.title)).font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 55))]) {
                    ForEach(category.symbols, id: \.self) { symbol in
                        Button(symbol) { document.addText(style: "bold-outline", text: symbol) }
                            .font(.largeTitle).buttonStyle(.bordered)
                    }
                }
            }
        }
        .disabled(document.fileURL == nil)
        .onAppear { images = ProjectDocument.stickerLibrary() }
        .task(id: document.plugins.plugins.map { $0.installationID + String(describing: document.plugins.availability[$0.id]) }) {
            packs = document.plugins.stickerPacks
        }
    }

    private func stickerButton(_ url: URL) -> some View {
        Button { document.addSticker(url) } label: {
            StickerThumbnail(url: url).frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered).help(url.lastPathComponent)
        .accessibilityLabel(url.deletingPathExtension().lastPathComponent)
    }
}

private struct StickerThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            let url = url
            let decoded = await Task.detached { StillImageMovie.decoded(url, maximumSide: 128) }.value
            image = decoded.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
    }
}
