import AppKit
import BashCutAutomation
import BashCutProject
import UniformTypeIdentifiers

/// The clip and gap context menus, and dropping media from the Media panel or Finder onto a layer.
extension TimelineCanvas {
    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let (_, item, track) = hit(at: point) {
            document.selectedID = item.id
            document.selectedTrackID = track.id
            selectedGap = nil
            return clipMenu(item: item, track: track)
        }
        if let gap = gapHit(at: point) {
            selectedGap = gap
            let menu = NSMenu()
            menu.addItem(ClosureMenuItem(String(localized: "Delete gap")) { [weak self] in self?.deleteGap(gap) })
            PluginMenus.append(to: menu, document, placement: "timeline.context")
            return menu
        }
        let menu = NSMenu()
        PluginMenus.append(to: menu, document, placement: "timeline.context")
        return menu.items.isEmpty ? nil : menu
    }

    private func clipMenu(item: Item, track: Track) -> NSMenu {
        let menu = NSMenu()
        var actions: [UIAction] = [.split, .delete, .lift]
        if track.kind == "video" { actions += [.freezeFrame, .changeFraming] }
        if item.linkedItemID != nil { actions.append(.unlinkAudio) }
        for (index, action) in actions.enumerated() {
            if index == 3 { menu.addItem(.separator()) }
            let title = action == .freezeFrame && item.fields["freezeFrame"] != nil
                ? String(localized: "Remove freeze frame") : NSLocalizedString(action.title, comment: "")
            let entry = ClosureMenuItem(title) { [weak self] in self?.document.run(action) }
            entry.isEnabled = document.canPerform(action)
            if let shortcut = action.shortcuts.first, shortcut.modifiers.isEmpty || shortcut.modifiers == [.command] {
                entry.keyEquivalent = shortcut.key == "delete" ? "\u{8}" : shortcut.key
                entry.keyEquivalentModifierMask = shortcut.modifiers.isEmpty ? [] : .command
            }
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let locked = track.isLocked
        let title = String(format: String(localized: locked ? "Unlock %@" : "Lock %@"), track.name)
        menu.addItem(ClosureMenuItem(title) { [weak self] in
            do { try self?.document.setLayerSwitches(track.id, locked: !locked) } catch {
                self?.document.message = error.localizedDescription
            }
        })
        PluginMenus.append(to: menu, document, placement: "clip.context", mediaID: item.mediaID)
        PluginMenus.append(to: menu, document, placement: "track.context")
        return menu
    }

    // MARK: Dropping media

    static let mediaPasteboardPrefix = "bashcut-media:"

    private struct Drop {
        let media: [Media]
        let files: [URL]
        let trackID: String?
        let frame: Int
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !document.busy, !document.conflict, document.fileURL != nil, let drop = drop(for: sender) else {
            showGuides(at: nil, snapped: false)
            return []
        }
        showGuides(at: drop.frame, snapped: false)
        let point = convert(sender.draggingLocation, from: nil)
        let layer = drop.trackID.flatMap { id in project.tracks.first { $0.id == id }?.name } ?? String(localized: "New layer")
        showBadge(Timecode.string(drop.frame, fps: project.fps) + "  " + layer, at: point)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        showGuides(at: nil, snapped: false)
        badge.show(nil, nearX: 0, y: 0, within: visibleRect)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { draggingExited(sender) }
        guard let drop = drop(for: sender) else { return false }
        if !drop.files.isEmpty {
            document.importFiles(drop.files, trackID: drop.trackID, at: drop.frame)
            return true
        }
        var at = drop.frame
        for media in drop.media {
            do {
                let placed = try document.placeMedia(media, trackID: drop.trackID, at: at)
                at = document.project.tracks.first { $0.id == placed.trackID }?.items.map(\.end).filter { $0 > at }.min() ?? at
            } catch {
                document.message = error.localizedDescription
                return false
            }
        }
        return true
    }

    /// What a drag carries and where it would land: the layer under the pointer when it takes that kind of
    /// media (otherwise the planner picks one), at the snapped frame under the pointer.
    private func drop(for sender: any NSDraggingInfo) -> Drop? {
        let pasteboard = sender.draggingPasteboard
        let ids = (pasteboard.readObjects(forClasses: [NSString.self]) as? [String] ?? [])
            .filter { $0.hasPrefix(Self.mediaPasteboardPrefix) }.map { String($0.dropFirst(Self.mediaPasteboardPrefix.count)) }
        let media = ids.compactMap { id in project.media.first { $0.id == id } }
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter { url in
                let type = UTType(filenameExtension: url.pathExtension)
                return type?.conforms(to: .movie) == true || type?.conforms(to: .audio) == true
            }
        guard !media.isEmpty || !files.isEmpty else { return nil }
        let point = convert(sender.draggingLocation, from: nil)
        let isAudio = media.first.map { $0["kind"]?.string == "audio" }
            ?? files.first.map { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .audio) == true } ?? false
        let row = layout.row(at: point.y)?.track
        let trackID = row.flatMap { track -> String? in
            guard !track.isLocked else { return nil }
            return isAudio ? (track.kind == "audio" ? track.id : nil) : (track.kind == "video" ? track.id : nil)
        } ?? (isAudio ? project.track(role: TrackRole.music)?.id : nil)
        let frame = snap(
            min(project.duration, layout.frame(at: point.x)), excluding: nil, toPlayhead: true,
            modifiers: NSEvent.modifierFlags).frame
        return Drop(media: media, files: files, trackID: trackID, frame: frame)
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
