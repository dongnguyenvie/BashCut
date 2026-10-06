import AppKit
import BashCutPlugin
import SwiftUI

// MARK: - Media

/// Downsampled thumbnails of local images, read off the main actor and kept in memory.
@MainActor enum PluginImages {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()
    nonisolated static let maximumPixels = 640

    static func cached(_ path: String) -> NSImage? { cache.object(forKey: path as NSString) }

    static func load(_ path: String) async -> NSImage? {
        if let image = cached(path) { return image }
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            let url = URL(fileURLWithPath: path)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
            else { return nil }
            return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        }.value
        if let image { cache.setObject(image, forKey: path as NSString) }
        return image
    }
}

struct PluginImageView: View {
    let path: String?
    let height: Double?
    let caption: String?
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: min(max(height ?? 140, 16), 600))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            if let caption { Text(verbatim: caption).font(.caption2).foregroundStyle(.secondary) }
        }
        .task(id: path) {
            guard let path else { return }
            image = PluginImages.cached(path)
            if image == nil { image = await PluginImages.load(path) }
        }
    }
}

/// Before and after images with a draggable divider.
struct PluginImageCompare: View {
    let node: PluginViewNode
    @State private var before: NSImage?
    @State private var after: NSImage?
    @State private var split = 0.5

    var body: some View {
        let height = min(max(node.double("height") ?? 160, 40), 600)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                picture(after)
                picture(before).mask(alignment: .leading) {
                    Rectangle().frame(width: geometry.size.width * split)
                }
                Rectangle().fill(.white).frame(width: 2).offset(x: geometry.size.width * split - 1)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(max(value.location.x / max(geometry.size.width, 1), 0), 1)
            })
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .bottom) {
            HStack {
                Text(verbatim: node.string("beforeLabel") ?? String(localized: "Before"))
                Spacer()
                Text(verbatim: node.string("afterLabel") ?? String(localized: "After"))
            }.font(.caption2).padding(4).foregroundStyle(.white).shadow(radius: 2)
        }
        .task(id: (node.string("before") ?? "") + "|" + (node.string("after") ?? "")) {
            if let path = node.string("before") { before = await PluginImages.load(path) }
            if let path = node.string("after") { after = await PluginImages.load(path) }
        }
    }

    private func picture(_ image: NSImage?) -> some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() } else { Color.secondary.opacity(0.12) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
}

/// One preview player for every plugin view: starting a sound stops the one playing.
@MainActor @Observable final class PluginAudioPreview {
    static let shared = PluginAudioPreview()
    private(set) var playing: String?
    @ObservationIgnored private var player: NSSound?

    func toggle(_ path: String) {
        player?.stop()
        if playing == path {
            playing = nil
            return
        }
        guard let sound = NSSound(contentsOf: URL(fileURLWithPath: path), byReference: true) else {
            playing = nil
            return
        }
        player = sound
        playing = path
        sound.play()
        let duration = sound.duration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.1))
            if self?.playing == path, self?.player === sound { self?.playing = nil }
        }
    }
}

struct PluginAudioButton: View {
    let path: String?
    let title: String?
    var compact = false
    private var preview: PluginAudioPreview { .shared }

    var body: some View {
        let playing = path != nil && preview.playing == path
        Button {
            if let path { preview.toggle(path) }
        } label: {
            if compact {
                Image(systemName: playing ? "stop.fill" : "play.fill")
            } else {
                Label(title ?? URL(fileURLWithPath: path ?? "").lastPathComponent, systemImage: playing ? "stop.fill" : "play.fill")
            }
        }
        .buttonStyle(.borderless)
        .disabled(path == nil)
    }
}
