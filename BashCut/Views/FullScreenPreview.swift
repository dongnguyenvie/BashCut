import AVFoundation
import AppKit
import BashCutAutomation
import BashCutDocument
import SwiftUI

/// Full-screen preview (#530): a borderless window over a whole screen with the program picture alone. It shows the
/// viewer's own player, so the playhead, play state and audio are the viewer's and nothing decodes twice; the viewer
/// shows a note instead of the picture meanwhile. With a second screen it opens there and leaves the editor where it is.
@MainActor @Observable
final class FullScreenPreview {
    private(set) var isOn = false
    /// Play from the start again at the end of the timeline.
    var loop = false
    /// The transport over the picture; it hides a moment after the pointer stops.
    private(set) var showsControls = true
    /// The pointer is on the transport, which then stays.
    @ObservationIgnored var pointerOnControls = false
    @ObservationIgnored private var window: FullScreenPreviewWindow?
    @ObservationIgnored private weak var editorWindow: NSWindow?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    func toggle(_ document: ProjectDocument) {
        if isOn { close() } else { open(document) }
    }

    func open(_ document: ProjectDocument) {
        guard window == nil else { return }
        let editor = NSApp.windows.first { $0.contentView is NSHostingView<EditorView> }
        // Another screen than the editor's when there is one, so the editor stays usable beside it.
        guard let screen = NSScreen.screens.first(where: { $0 != editor?.screen }) ?? editor?.screen ?? NSScreen.main
        else { return }
        editorWindow = editor
        let window = FullScreenPreviewWindow(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        // Above the menu bar and the Dock of that screen.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.onKey = { [weak self, weak document] event in
            guard let self, let document else { return false }
            return handleKey(event, document: document)
        }
        window.onMouseMoved = { [weak self] in self?.revealControls() }
        let hosting = NSHostingView(
            rootView: FullScreenPreviewView(document: document, model: self).preferredColorScheme(.dark).tint(.cyan))
        hosting.sizingOptions = []
        // Pointer moves reach the window also while the editor on another screen is key.
        hosting.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: window, userInfo: nil))
        window.contentView = hosting
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self, weak document] note in
            let item = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let document, self.loop,
                      item == document.preview.player.currentItem.map(ObjectIdentifier.init) else { return }
                document.preview.seek(0)
                document.preview.togglePlayback()
            }
        }
        self.window = window
        isOn = true
        window.makeKeyAndOrderFront(nil)
        revealControls()
    }

    /// Back to the editor; the playhead and play state stay as they are.
    func close() {
        guard let window else { return }
        self.window = nil
        hideTask?.cancel()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        window.orderOut(nil)
        window.contentView = nil
        isOn = false
        showsControls = true
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    /// Shows the transport and hides it (and the pointer) again after a moment without moves.
    func revealControls() {
        if !showsControls { showsControls = true }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
            guard let self, isOn, !pointerOnControls else { return }
            showsControls = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    /// Space, ←/→ (a frame; ⇧ a second), J/K/L, Esc and ⌥⌘F; false passes the key on.
    private func handleKey(_ event: NSEvent, document: ProjectDocument) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (event.keyCode, event.charactersIgnoringModifiers?.lowercased()) {
        case (53, _): close()
        case (_, "f") where modifiers == [.command, .option]: close()
        case (49, _) where modifiers.isEmpty: document.run(.togglePlayback)
        case (123, _), (124, _):
            let back = event.keyCode == 123
            let second = modifiers.contains(.shift)
            document.run(second ? (back ? .backSecond : .forwardSecond) : (back ? .previousFrame : .nextFrame))
        case (_, "j") where modifiers.isEmpty: document.run(.shuttleBack)
        case (_, "k") where modifiers.isEmpty: document.run(.shuttleStop)
        case (_, "l") where modifiers.isEmpty: document.run(.shuttleForward)
        default: return false
        }
        return true
    }
}

/// Borderless, yet it takes keys, and the preview sees them before any control does. It never becomes main, so
/// sheets and panels keep opening on the editor.
private final class FullScreenPreviewWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?
    var onMouseMoved: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }

    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }
}

/// The picture aspect-fit on black at the screen's size, the overlays the viewer's toggles show, and the transport.
private struct FullScreenPreviewView: View {
    let document: ProjectDocument
    let model: FullScreenPreview

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if document.project.duration > 0 {
                GeometryReader { geometry in
                    let aspect = Double(document.project.width) / Double(max(1, document.project.height))
                    let width = max(1, min(geometry.size.width, geometry.size.height * aspect))
                    ZStack {
                        PlayerView(player: document.preview.player)
                        PluginViewerOverlays(document: document)
                        if document.ui.showSafeArea { ViewerSafeArea(document: document) }
                    }
                    .frame(width: width, height: width / aspect)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            if model.showsControls {
                FullScreenTransport(document: document, model: model).padding(32).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.showsControls)
        .ignoresSafeArea()
    }
}

/// Play/pause, scrubber, time, loop and close. It is its own view, like `TransportBar`: only it follows the playhead,
/// and only while it is shown.
private struct FullScreenTransport: View {
    let document: ProjectDocument
    @Bindable var model: FullScreenPreview

    var body: some View {
        HStack(spacing: 14) {
            Button {
                document.run(.togglePlayback)
            } label: {
                Image(systemName: !document.preview.isPlaying ? "play.fill" : "pause.fill").frame(width: 20)
            }.help("Play or pause (Space)")
            Slider(
                value: Binding(get: { Double(document.playhead) }, set: { document.preview.seek(Int($0)) }),
                in: 0...Double(max(1, document.project.duration)))
            Text(
                Timecode.transportLabel(
                    position: document.playhead, length: document.project.duration, fps: document.project.fps)
            ).font(.callout.monospacedDigit())
            Toggle(isOn: $model.loop) { Image(systemName: "repeat") }.toggleStyle(.button).help("Loop")
            Button {
                model.close()
            } label: {
                Image(systemName: "xmark")
            }.help("Exit full screen (Esc)")
        }
        .buttonStyle(.borderless).font(.title3)
        .padding(.horizontal, 18).padding(.vertical, 10)
        .frame(maxWidth: 900)
        .background(.ultraThinMaterial, in: Capsule())
        .onHover { inside in
            model.pointerOnControls = inside
            if !inside { model.revealControls() }
        }
    }
}
