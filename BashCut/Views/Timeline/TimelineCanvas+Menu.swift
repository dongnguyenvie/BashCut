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
            document.selectedTrackID = track.id
            selectedGap = nil
            if document.selectedIDs.count > 1, document.selectedIDs.contains(item.id) {
                document.select(document.selectedIDs, primary: item.id)
                return selectionMenu()
            }
            document.selectedID = item.id
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
        if document.canPerform(.pasteClips) { menu.addItem(actionItem(.pasteClips)) }
        PluginMenus.append(to: menu, document, placement: "timeline.context")
        return menu.items.isEmpty ? nil : menu
    }

    /// The menu for a right-click on a clip that is part of a multi-selection: actions on every selected clip.
    private func selectionMenu() -> NSMenu {
        let menu = NSMenu()
        let count = document.selectedIDs.count
        let header = NSMenuItem(title: String(format: String(localized: "%d clips selected"), count), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        for action in [UIAction.delete, .lift] { menu.addItem(actionItem(action)) }
        menu.addItem(.separator())
        for action in [UIAction.copyClips, .cutClips, .pasteClips, .muteClips] { menu.addItem(actionItem(action)) }
        return menu
    }

    /// A menu entry that runs `action`, with its shortcut shown when it has ⌘ or no modifier.
    private func actionItem(_ action: UIAction) -> NSMenuItem {
        let title = action == .muteClips && SelectionEdits.allMuted(document.selectedIDs, in: document.project)
            ? String(localized: "Unmute") : NSLocalizedString(Self.menuTitles[action] ?? action.title, comment: "")
        let entry = ClosureMenuItem(title) { [weak self] in self?.document.run(action) }
        entry.isEnabled = document.canPerform(action)
        if let shortcut = action.shortcuts.first, shortcut.modifiers.isEmpty || shortcut.modifiers == [.command] {
            entry.keyEquivalent = shortcut.key == "delete" ? "\u{8}" : shortcut.key
            entry.keyEquivalentModifierMask = shortcut.modifiers.isEmpty ? [] : .command
        }
        return entry
    }

    /// Short titles for the clip menus; `UIAction.title` describes the action for agents.
    private static let menuTitles: [UIAction: String] = [
        .copyClips: "Copy", .cutClips: "Cut", .pasteClips: "Paste", .muteClips: "Mute",
    ]

    private func clipMenu(item: Item, track: Track) -> NSMenu {
        let menu = NSMenu()
        var actions: [UIAction] = [.split, .delete, .lift]
        if track.kind == "video" { actions += [.freezeFrame, .changeFraming] }
        if item.linkedItemID != nil { actions.append(.unlinkAudio) }
        for (index, action) in actions.enumerated() {
            if index == 3 { menu.addItem(.separator()) }
            let entry = actionItem(action)
            if action == .freezeFrame && item.fields["freezeFrame"] != nil {
                entry.title = String(localized: "Remove freeze frame")
            }
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let clipboard: [UIAction] = [.copyClips, .cutClips, .pasteClips] + (item.mediaID == nil ? [] : [.muteClips])
        clipboard.map(actionItem).forEach(menu.addItem)
        if item.mediaID != nil, item.fields["freezeFrame"] == nil {
            menu.addItem(speedMenu(item))
            if track.kind == "video" {
                let reversed = item.fields["reversed"] != nil
                menu.addItem(ClosureMenuItem(String(localized: reversed ? "Play Forward" : "Reverse")) { [weak self] in
                    guard let self else { return }
                    do { _ = try document.reverseClip(item.id) } catch { document.message = error.localizedDescription }
                })
            }
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

    /// Speed › presets and Reset, applied like the Inspector (length follows speed unless the Inspector says not).
    private func speedMenu(_ item: Item) -> NSMenuItem {
        let submenu = NSMenu()
        let keepDuration = UserDefaults.standard.object(forKey: "speedChangesLength") as? Bool == false
        for preset in UIAction.speedPresets {
            let entry = ClosureMenuItem(UIAction.speedLabel(preset)) { [weak self] in
                guard let self else { return }
                do { try document.setClipSpeed(preset, item: item.id, keepDuration: keepDuration) } catch {
                    document.message = error.localizedDescription
                }
            }
            entry.state = abs(item.speed - preset) < 0.001 ? .on : .off
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        let curves = NSMenu()
        let current = document.speedCurvePreset(of: item)
        for preset in [("none", "None")] + SpeedCurve.presets.map({ ($0.id, $0.title) }) {
            let entry = ClosureMenuItem(String(localized: String.LocalizationValue(preset.1))) { [weak self] in
                guard let self else { return }
                do {
                    try document.setClipSpeedCurve(
                        SpeedCurve.preset(preset.0), item: item.id, keepDuration: keepDuration)
                } catch { document.message = error.localizedDescription }
            }
            entry.state = (current ?? "none") == preset.0 ? .on : .off
            curves.addItem(entry)
        }
        let curveItem = NSMenuItem(title: String(localized: "Curve"), action: nil, keyEquivalent: "")
        curveItem.submenu = curves
        submenu.addItem(curveItem)
        let label = item.speedCurve == nil ? UIAction.speedLabel(item.speed) : String(localized: "Curve")
        let parent = NSMenuItem(
            title: String(format: String(localized: "Speed (%@)"), label), action: nil,
            keyEquivalent: "")
        parent.submenu = submenu
        return parent
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
                    || type?.conforms(to: .image) == true
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
