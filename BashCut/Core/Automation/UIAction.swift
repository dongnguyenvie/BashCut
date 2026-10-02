import Foundation

/// A keyboard shortcut written the way agents type it: `cmd+shift+z`, `space`, `i`.
public struct UIShortcut: Sendable, Hashable, CustomStringConvertible {
    public enum Modifier: String, Sendable, CaseIterable, Comparable {
        case command = "cmd", shift, option = "opt", control = "ctrl"

        public static func < (lhs: Self, rhs: Self) -> Bool {
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
        }
    }

    /// One character, or a named key: `space`, `delete`, `left`, `right`.
    public let key: String
    public let modifiers: Set<Modifier>

    public init(_ key: String, _ modifiers: Set<Modifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Parses `cmd+shift+z`; modifiers may also be spelled `command`, `option`, `alt`, `control`.
    public init?(parsing text: String) {
        let aliases: [String: Modifier] = [
            "cmd": .command, "command": .command, "shift": .shift, "opt": .option, "option": .option,
            "alt": .option, "ctrl": .control, "control": .control,
        ]
        var parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // `cmd++` names the plus key.
        if text.hasSuffix("++") { parts.removeLast(2); parts.append("+") }
        guard let key = parts.popLast(), !key.isEmpty else { return nil }
        var modifiers: Set<Modifier> = []
        for part in parts {
            guard let modifier = aliases[part] else { return nil }
            modifiers.insert(modifier)
        }
        self.init(key, modifiers)
    }

    public var description: String {
        (modifiers.sorted().map(\.rawValue) + [key]).joined(separator: "+")
    }
}

/// Every action the user triggers from the editor's buttons, menus and shortcuts. The UI and the
/// `ui.action` command run the same code, so anything a person can click an agent can run.
/// Add a case here with its title and shortcut, then handle it in `ProjectDocument+UIActions`.
public enum UIAction: String, CaseIterable, Sendable {
    case undo = "edit.undo"
    case redo = "edit.redo"
    case newProject = "project.new"
    case openProject = "project.open"
    case saveProject = "project.save"
    case importMedia = "project.import-media"
    case showHistory = "show.history"
    case showReview = "show.review"
    case showPlugins = "show.plugins"
    case showDoctor = "show.doctor"
    case showSettings = "show.settings"
    case showExport = "show.export"
    case showSections = "show.sections"
    case toggleAgentDock = "agent.toggle-dock"
    case askAgent = "agent.ask"
    case togglePlayback = "playback.toggle"
    case previousFrame = "playhead.previous-frame"
    case nextFrame = "playhead.next-frame"
    case backSecond = "playhead.back-second"
    case forwardSecond = "playhead.forward-second"
    case toggleCompare = "view.compare"
    case toggleSafeArea = "view.safe-area"
    case toggleSnap = "timeline.snap"
    case zoomIn = "timeline.zoom-in"
    case zoomOut = "timeline.zoom-out"
    case zoomFit = "timeline.zoom-fit"
    case split = "timeline.split"
    case delete = "timeline.delete"
    case lift = "timeline.lift"
    case freezeFrame = "clip.freeze"
    case changeFraming = "clip.change-framing"
    case unlinkAudio = "clip.unlink-audio"
    case speedUp = "clip.speed-up"
    case slowDown = "clip.slow-down"
    case resetSpeed = "clip.speed-reset"
    case refreshWaveforms = "timeline.refresh-waveforms"
    case addVideoLayer = "layer.add-video"
    case addAdjustmentLayer = "layer.add-adjustment"
    case addTextLayer = "layer.add-text"
    case addAudioLayer = "layer.add-audio"
    case layerUp = "layer.up"
    case layerDown = "layer.down"
    case deleteLayer = "layer.delete"
    case sourceTogglePlayback = "source.toggle-playback"
    case sourcePreviousFrame = "source.previous-frame"
    case sourceNextFrame = "source.next-frame"
    case markIn = "source.mark-in"
    case markOut = "source.mark-out"
    case sourceInsert = "source.insert"
    case sourceOverwrite = "source.overwrite"
    case sourceClose = "source.close"
    case showAgentChanges = "agent.show-changes"
    case undoAgentChange = "agent.undo-changes"
    case dismissAgentChange = "agent.dismiss-changes"
    case openExportOutput = "export.open-output"
    case revealExportOutput = "export.reveal-output"
    case clearRecentProjects = "project.clear-recents"

    public var id: String { rawValue }

    /// Speeds the Speed tab, the clip menu and Speed up / Slow down step through.
    public static let speedPresets: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    /// `2×`, `1.5×`, `0.75×`.
    public static func speedLabel(_ speed: Double) -> String {
        let text = speed == speed.rounded() ? String(Int(speed)) : String(format: "%g", (speed * 100).rounded() / 100)
        return text + "×"
    }

    /// Inspector tabs, for `ui.view --inspector`.
    public static let inspectorTabs = ["video", "audio", "text", "color", "speed"]

    public var title: String {
        switch self {
        case .undo: "Undo"
        case .redo: "Redo"
        case .newProject: "New project"
        case .openProject: "Open project…"
        case .saveProject: "Save"
        case .importMedia: "Import footage…"
        case .showHistory: "History"
        case .showReview: "Review"
        case .showPlugins: "Plugins"
        case .showDoctor: "Doctor"
        case .showSettings: "Settings"
        case .showExport: "Export…"
        case .showSections: "Sections"
        case .toggleAgentDock: "Show or hide the agent dock"
        case .askAgent: "Ask agent"
        case .togglePlayback: "Play or pause"
        case .previousFrame: "Previous frame"
        case .nextFrame: "Next frame"
        case .backSecond: "Back one second"
        case .forwardSecond: "Forward one second"
        case .toggleCompare: "Compare color before/after"
        case .toggleSafeArea: "Safe area"
        case .toggleSnap: "Snap"
        case .zoomIn: "Zoom timeline in"
        case .zoomOut: "Zoom timeline out"
        case .zoomFit: "Zoom timeline to fit"
        case .split: "Split selected clip at the playhead"
        case .delete: "Delete selected clip (ripple)"
        case .lift: "Lift selected clip (leave a gap)"
        case .freezeFrame: "Freeze frame"
        case .changeFraming: "Change framing"
        case .unlinkAudio: "Unlink audio"
        case .speedUp: "Speed up selected clip"
        case .slowDown: "Slow down selected clip"
        case .resetSpeed: "Reset selected clip to normal speed"
        case .refreshWaveforms: "Refresh waveforms"
        case .addVideoLayer: "Add video layer"
        case .addAdjustmentLayer: "Add adjustment layer"
        case .addTextLayer: "Add text layer"
        case .addAudioLayer: "Add audio layer"
        case .layerUp: "Move selected layer up"
        case .layerDown: "Move selected layer down"
        case .deleteLayer: "Delete selected empty layer"
        case .sourceTogglePlayback: "Play or pause the source viewer"
        case .sourcePreviousFrame: "Source previous frame"
        case .sourceNextFrame: "Source next frame"
        case .markIn: "Mark source in"
        case .markOut: "Mark source out"
        case .sourceInsert: "Insert source range at the playhead"
        case .sourceOverwrite: "Overwrite with source range at the playhead"
        case .sourceClose: "Close the source viewer (back to the timeline viewer)"
        case .showAgentChanges: "Show the latest agent changes"
        case .undoAgentChange: "Undo the latest agent change"
        case .dismissAgentChange: "Dismiss the agent change notice"
        case .openExportOutput: "Open the last exported video"
        case .revealExportOutput: "Reveal the last exported video in Finder"
        case .clearRecentProjects: "Clear recent projects"
        }
    }

    /// The shortcut shown on the button or menu item.
    public var shortcut: UIShortcut? { shortcuts.first }

    /// Every key that runs the action; later ones work while the timeline has keyboard focus.
    public var shortcuts: [UIShortcut] {
        switch self {
        case .split: [UIShortcut("b", [.command]), UIShortcut("s")]
        case .delete: [UIShortcut("delete")]
        case .lift: [UIShortcut("delete", [.shift])]
        // Timeline-only, like `s`: a global ⇧Z would swallow capital Z typed in text fields.
        case .zoomFit: [UIShortcut("z", [.shift])]
        // Arrow keys step the playhead while the timeline has keyboard focus.
        case .previousFrame: [UIShortcut("left")]
        case .nextFrame: [UIShortcut("right")]
        case .backSecond: [UIShortcut("left", [.shift])]
        case .forwardSecond: [UIShortcut("right", [.shift])]
        default: primaryShortcut.map { [$0] } ?? []
        }
    }

    private var primaryShortcut: UIShortcut? {
        switch self {
        case .undo: UIShortcut("z", [.command])
        case .redo: UIShortcut("z", [.command, .shift])
        case .newProject: UIShortcut("n", [.command])
        case .openProject: UIShortcut("o", [.command])
        case .saveProject: UIShortcut("s", [.command])
        case .showReview: UIShortcut("r", [.command, .shift])
        case .showExport: UIShortcut("e", [.command])
        case .toggleAgentDock: UIShortcut("j", [.command])
        case .askAgent: UIShortcut("k", [.command])
        case .togglePlayback: UIShortcut("space")
        case .zoomIn: UIShortcut("=", [.command])
        case .zoomOut: UIShortcut("-", [.command])
        case .sourceTogglePlayback: UIShortcut("space")
        case .markIn: UIShortcut("i")
        case .markOut: UIShortcut("o")
        case .sourceInsert: UIShortcut("e")
        case .sourceOverwrite: UIShortcut("q")
        default: nil
        }
    }

    /// Actions that may show an alert or file panel; `ui.action` starts them and returns at once,
    /// and the agent answers the dialog with `ui.dialog` / `ui.respond`.
    public var mayShowModal: Bool { [.newProject, .openProject, .importMedia].contains(self) }

    /// The action with this ID, or every action bound to this shortcut. One shortcut can mean
    /// different actions in different places (`space` plays the source viewer when it is shown);
    /// the caller picks the one that is available.
    public static func matching(_ text: String) -> [UIAction] {
        let value = text.trimmingCharacters(in: .whitespaces)
        if let action = UIAction(rawValue: value.lowercased()) { return [action] }
        guard let shortcut = UIShortcut(parsing: value) else { return [] }
        return allCases.filter { $0.shortcuts.contains(shortcut) }
    }
}
