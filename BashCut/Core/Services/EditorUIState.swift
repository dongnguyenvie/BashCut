import BashCutProject
import Foundation
import Observation

/// Editor view state that is not part of the project: timeline zoom and scroll requests, toggles, the
/// open library panel and inspector tab, and which editor sheets are showing. `ui.view`, `ui.panel`,
/// `ui.open` and `ui.dialog` read and change it; nothing here is saved with the project.
@MainActor @Observable
public final class EditorUIState {
    /// Timeline pixels per second: from a whole long video in view to single frames.
    public static let timelineZoomRange: ClosedRange<Double> = 1...600
    public static let zoomStep = 1.25
    /// Width of the track-name column left of frame 0, and the margin kept after the end when fitting.
    public static let timelineLeading = 140.0
    public static let fitMargin = 40.0

    /// Timeline pixels per second.
    public private(set) var timelineScale = 50.0
    public var timelineReveal: TimelineReveal?
    /// The point a zoom keeps in place; the timeline consumes each new request once. Not observed: it is set
    /// with `timelineScale`, whose change already updates the timeline.
    @ObservationIgnored public private(set) var timelineZoomAnchor: TimelineZoomAnchor?
    /// Visible timeline width in points, reported by the timeline view; used to fit the timeline.
    @ObservationIgnored public var timelineViewportWidth = 900.0
    public var snapping = true
    public var showSafeArea = false
    /// nil fits the frame in the viewer; otherwise the output's scale (see `EditorViewerZoom`).
    public var viewerZoom: Double?
    public var showAgentDock = true
    public var libraryTab: LibraryTab = .media
    /// Search and filters of each library panel, by panel name.
    public var libraryFilters: [String: LibraryPanelFilter] = [:]
    /// The library item sheet: Save selection as…, Duplicate & Edit… or Rename….
    public var libraryEditor: LibraryEditorRequest?
    /// The Effects panel's Apply with… sheet: an effect recipe's parameters and the part of the clip (#76).
    public var effectApply: EffectApplyRequest?
    /// One of `UIAction.inspectorTabs`.
    public var inspectorTab = "video"
    /// One of `UIAction.settingsSections`: the section the Settings sheet shows.
    public var settingsSection = "general"
    /// One of `UIAction.knowledgeSections`: the section the Knowledge window shows.
    public var knowledgeSection = "lessons"

    // Editor sheets and popovers; `ModalCenter` reports them to automation.
    public var showNewProject = false
    public var showExport = false
    public var showExportReport = false
    /// The Export button's popover while an export runs.
    public var showExportProgress = false
    public var showAgentChanges = false
    public var showExternalChanges = false
    public var showLegacyImportReport = false
    public var showReview = false
    public var showHistory = false
    public var showPlugins = false
    public var showSettings = false
    public var showDoctor = false
    /// Software Update: this version and whether a newer release is out (BashCut › Check for Updates…).
    public var showUpdates = false
    /// Software Update opened by itself for a new release: it shows what is known without checking again.
    public var updatesPrompt = false
    public var showAsk = false
    public var showSections = false
    /// The command palette (⇧⌘P) and the keyboard-shortcuts sheet (⌘/), both built from the menu bar.
    public var showCommands = false
    public var showShortcuts = false
    /// Edits plugin hooks proposed, waiting for review.
    public var showPluginProposals = false

    public init() {}

    public var canZoomIn: Bool { timelineScale < Self.timelineZoomRange.upperBound }
    public var canZoomOut: Bool { timelineScale > Self.timelineZoomRange.lowerBound }

    /// Sets the zoom, clamped to the range. With an `anchor` frame the timeline keeps that frame where it is
    /// on screen (`viewOffset` from the left of the visible area, or its current position when nil).
    public func setTimelineZoom(_ value: Double, anchor: Int? = nil, viewOffset: Double? = nil) {
        guard value.isFinite else { return }
        timelineScale = min(max(value, Self.timelineZoomRange.lowerBound), Self.timelineZoomRange.upperBound)
        if let anchor { timelineZoomAnchor = TimelineZoomAnchor(frame: max(0, anchor), viewOffset: viewOffset) }
    }

    /// Zoom buttons and shortcuts keep the playhead in place.
    public func zoomIn(around playhead: Int? = nil) { setTimelineZoom(timelineScale * Self.zoomStep, anchor: playhead) }

    public func zoomOut(around playhead: Int? = nil) { setTimelineZoom(timelineScale / Self.zoomStep, anchor: playhead) }

    /// Multiplies the zoom by `factor` around the frame under the pointer (pinch and ⌘-scroll).
    public func magnifyTimeline(by factor: Double, at frame: Int, viewOffset: Double) {
        guard factor.isFinite, factor > 0 else { return }
        setTimelineZoom(timelineScale * factor, anchor: frame, viewOffset: viewOffset)
    }

    /// The slider position: zoom is multiplicative, so the slider moves on a log scale.
    public var timelineZoomSliderValue: Double { log(timelineScale) }
    public static var timelineZoomSliderRange: ClosedRange<Double> {
        log(timelineZoomRange.lowerBound)...log(timelineZoomRange.upperBound)
    }

    public func setTimelineZoomSliderValue(_ value: Double, around playhead: Int? = nil) {
        setTimelineZoom(exp(value), anchor: playhead)
    }

    /// The zoom that shows `duration` frames at `fps` in the visible width, with a margin after the end.
    public func fitZoom(duration: Int, fps: Double) -> Double {
        let seconds = Double(max(1, duration)) / max(1, fps)
        let width = max(100, timelineViewportWidth - Self.timelineLeading - Self.fitMargin)
        return min(max(width / seconds, Self.timelineZoomRange.lowerBound), Self.timelineZoomRange.upperBound)
    }

    /// Shows the whole timeline from its start.
    public func zoomToFit(duration: Int, fps: Double) {
        setTimelineZoom(fitZoom(duration: duration, fps: fps), anchor: 0, viewOffset: Self.timelineLeading)
    }

    /// Asks the timeline to scroll `frame` (clamped to `0...duration`) into view.
    public func revealInTimeline(_ frame: Int, duration: Int) {
        timelineReveal = TimelineReveal(frame: min(max(0, frame), max(0, duration)))
    }

    /// Closes the sheets that describe the previous project when another one opens.
    public func closeProjectSheets() {
        showExportReport = false
        showExportProgress = false
        showAgentChanges = false
        showExternalChanges = false
        showLegacyImportReport = false
        showPluginProposals = false
    }

    /// Sheets that open unconditionally by name (`ui.open`).
    public static let toggledDialogs: [String: ReferenceWritableKeyPath<EditorUIState, Bool>] = [
        "review": \.showReview, "history": \.showHistory, "plugins": \.showPlugins, "settings": \.showSettings,
        "doctor": \.showDoctor, "ask": \.showAsk, "sections": \.showSections, "commands": \.showCommands,
        "shortcuts": \.showShortcuts, "updates": \.showUpdates,
    ]
}

/// A one-off request to keep `frame` at `viewOffset` points from the left of the visible timeline after a zoom.
/// A nil offset keeps the frame where it was before the zoom (centered if it was off screen).
public struct TimelineZoomAnchor: Equatable, Sendable {
    public let frame: Int
    public let viewOffset: Double?
    public let id = UUID()

    public init(frame: Int, viewOffset: Double?) {
        self.frame = frame
        self.viewOffset = viewOffset
    }
}

/// A one-off request for the timeline to scroll a frame into view.
public struct TimelineReveal: Equatable, Sendable {
    public let frame: Int
    public let id = UUID()

    public init(frame: Int) { self.frame = frame }
}

/// What a library panel shows: items matching the search, in one pack, with one tag, from one scope (nil: all).
public struct LibraryPanelFilter: Equatable, Sendable {
    public var query = ""
    public var pack: String?
    public var tag: String?
    /// A `LibraryScope` raw value.
    public var scope: String?

    public init() {}

    public var isActive: Bool { !query.isEmpty || pack != nil || tag != nil || scope != nil }
}

/// What the library item sheet saves, with the fields the user can change before saving.
public struct LibraryEditorRequest: Identifiable {
    public enum Mode {
        /// A new item of this kind from the timeline selection.
        case saveSelection(LibraryKind)
        /// A copy of any item (built-in and plugin ones too) under a new ID.
        case duplicate(LibraryItem)
        /// A new version of a saved item with another name, tags or pack.
        case rename(LibraryItem)
    }

    public let id = UUID()
    public var mode: Mode
    public var name: String
    /// Comma-separated.
    public var tags: String
    public var pack: String
    public var scope: LibraryScope
    /// A transition preset's kind, duration, easing and sound, edited in the sheet (#77); nil for other kinds.
    public var transition: TransitionPreset?
    /// A look's grade and LUT name, edited in the sheet (#79); nil for other kinds.
    public var look: FilterStack?
    /// Whether the look keeps its own .cube LUT; nil when it has none.
    public var keepsLUT: Bool?
    /// An audio item's role and loop flag, edited in the sheet (#78); nil for other kinds.
    public var audio: LibraryAudio?
    /// Save to Library… on project audio: the media saved instead of the timeline selection.
    public var mediaID: String?
    /// A sticker's size, position and animation, edited in the sheet (#64); nil for other kinds.
    public var sticker: LibrarySticker?

    public init(
        mode: Mode, name: String, tags: [String] = [], pack: String? = nil, scope: LibraryScope,
        transition: TransitionPreset? = nil, look: FilterStack? = nil, keepsLUT: Bool? = nil
    ) {
        self.mode = mode
        self.name = name
        self.tags = tags.joined(separator: ", ")
        self.pack = pack ?? ""
        self.scope = scope
        self.transition = transition
        self.look = look
        self.keepsLUT = keepsLUT
    }
}

/// What the Effects panel's Apply with… sheet applies (#76): an effect preset with parameter values, on the whole
/// clip or the frames `from..<to` of it.
public struct EffectApplyRequest: Identifiable {
    public let id = UUID()
    public var item: LibraryItem
    public var itemID: String
    public var parameters: [EffectRecipe.Parameter]
    public var values: [String: Double]
    public var useRange: Bool
    /// Timeline frames; `clip` bounds them.
    public var from: Int
    public var to: Int
    public var clip: Range<Int>

    public init(item: LibraryItem, itemID: String, parameters: [EffectRecipe.Parameter], clip: Range<Int>, playhead: Int) {
        self.item = item
        self.itemID = itemID
        self.parameters = parameters
        values = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.value) })
        self.clip = clip
        let start = clip.contains(playhead) && playhead < clip.upperBound - 1 ? playhead : clip.lowerBound
        useRange = false
        from = start
        to = clip.upperBound
    }

    /// The overrides that differ from the defaults.
    public var overrides: [String: Double] {
        values.filter { name, value in parameters.first { $0.name == name }?.value != value }
    }

    /// The range to apply to, or nil for the whole clip.
    public var range: Range<Int>? {
        guard useRange else { return nil }
        let lower = min(max(from, clip.lowerBound), clip.upperBound - 1)
        return lower..<min(max(to, lower + 1), clip.upperBound)
    }
}

/// Left-rail library panels; `CommandCatalog.libraryPanels` lists their lowercased names.
public enum LibraryTab: String, CaseIterable, Identifiable, Sendable {
    case media = "Media"
    case audio = "Audio"
    case text = "Text"
    case stickers = "Stickers"
    case effects = "Effects"
    case transitions = "Transitions"
    case filters = "Filters"
    case voice = "Voice"

    public var id: String { rawValue }

    /// The automation name (`ui.panel`).
    public var panelName: String { rawValue.lowercased() }

    public init?(panelName: String) {
        guard let tab = Self.allCases.first(where: { $0.panelName == panelName }) else { return nil }
        self = tab
    }

    public var icon: String {
        switch self {
        case .media: return "film"
        case .audio: return "music.note"
        case .text: return "textformat"
        case .stickers: return "star"
        case .effects: return "sparkles"
        case .transitions: return "arrow.left.arrow.right"
        case .filters: return "circle.lefthalf.filled"
        case .voice: return "mic"
        }
    }
}
