import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation
import Observation

/// The editor's side panes, Inspector and Agent; the raw values are what `ui view --right-tab` takes. They were the two
/// tabs of one right column (P1-6) and are now separate columns, each shown or hidden on its own.
public enum RightColumnTab: String, CaseIterable, Sendable { case inspector, agent }

/// Editor view state that is not part of the project: timeline zoom and scroll requests, toggles, the
/// open library panel and inspector tab, and which editor sheets are showing. `ui.view`, `ui.panel`,
/// `ui.open` and `ui.dialog` read and change it; nothing here is saved with the project.
@MainActor @Observable
public final class EditorUIState {
    /// Timeline pixels per second: from a whole long video in view to single frames.
    public static let timelineZoomRange: ClosedRange<Double> = 1...600
    public static let zoomStep = 1.25
    /// The layer header left of frame 0 (#531): compact shows short IDs (V1, A1) and switches, wide adds the full
    /// names; the user drags its edge anywhere in the range.
    public static let compactTimelineLeading = 78.0
    public static let wideTimelineLeading = 160.0
    public static let timelineLeadingRange: ClosedRange<Double> = compactTimelineLeading...280
    /// A window at least this wide (points) gets the wide header until the user picks a width.
    public static let wideHeaderWindowWidth = 1280.0
    /// The header width a window of this width starts with: named layers when there is room for them.
    public static func defaultTimelineLeading(windowWidth: Double) -> Double {
        windowWidth >= wideHeaderWindowWidth ? wideTimelineLeading : compactTimelineLeading
    }
    /// The margin kept after the end when fitting.
    public static let fitMargin = 40.0

    /// Width of the layer header; `ProjectDocument.setTimelineHeaderWidth` changes it and remembers it in Settings.
    public var timelineLeading = compactTimelineLeading
    /// Whether the timeline shows its empty layers (`TimelineTrackFolding`) instead of one folded row.
    public var showEmptyTracks = false
    /// Whether the header is too narrow for layer names (closer to compact than to wide).
    public var timelineHeaderCompact: Bool {
        timelineLeading < (Self.compactTimelineLeading + Self.wideTimelineLeading) / 2
    }

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
    /// The agent dock: a column of its own at the window's right edge, the full height beside the timeline too (a
    /// terminal needs the height). Independent of the Inspector, so selecting or editing never hides it.
    public var showAgentDock = true
    /// The library panel left of the viewer and the right column beside it; hidden to give a small window room (#528).
    public var showLibraryPanel = true
    /// The Inspector: a column beside the viewer, with the timeline spanning the editor's width under it.
    public var showInspector = true
    /// The agent lives in its own window, so the window has no agent column.
    public var agentPoppedOut = false

    /// The Inspector column is on screen.
    public var inspectorShown: Bool { showInspector }
    /// The agent column is on screen: the dock is open and the agent is not in its own window.
    public var agentColumnShown: Bool { showAgentDock && !agentPoppedOut }

    /// `ui view --right-tab` (or a menu): show that pane. The other pane stays as it is.
    public func selectRightTab(_ tab: RightColumnTab) {
        switch tab {
        case .inspector: showInspector = true
        case .agent: showAgentDock = true
        }
    }

    /// The library panel's width in points when dragged (`LibraryPanelMetrics.widthRange`); nil: the default for the screen.
    public var libraryWidth: Double?
    /// The wide library panel (760 pt over the viewer, with a category sidebar); Esc leaves it.
    public var libraryWide = false
    /// Tile size and grid or list per panel name; `ProjectDocument.setLibraryLayout` remembers them in Settings.
    public var libraryLayouts: [String: LibraryPanelLayout] = [:]
    public var libraryTab: LibraryTab = .media
    /// The tool the Tools panel shows (a `ToolID`, or `<plugin>/<view>` for a plugin's tool view), nil for the first.
    public var selectedTool: String?
    /// The plugin whose rail panel replaces the library panel (plugin API 8), or nil for the library.
    public var pluginPanel: String?
    /// The view each plugin panel shows, by plugin ID.
    public var pluginPanelViews: [String: String] = [:]
    /// The plugin view shown in a sheet (`<plugin>/<view>`, plugin API 8 `location: sheet`).
    public var pluginSheet: String?
    /// Plugin views open in a window of their own (`<plugin>/<view>`, plugin API 11 `location: window`).
    public var pluginWindows: Set<String> = []
    /// The window view docked over the viewer instead of its window; Undock or Esc leaves it.
    public var dockedPluginView: String?
    /// Plugin overlays on the timeline and viewer (#407), ready to draw; `setPluginOverlays` changes them.
    @ObservationIgnored public private(set) var pluginOverlays = PluginOverlayIndex([:])
    /// Goes up whenever `pluginOverlays` changes (observed, so the timeline compares a number, not the overlays).
    public private(set) var pluginOverlayRevision = 0
    /// Each plugin's overlay set as it sent it.
    @ObservationIgnored public private(set) var pluginOverlaySets: [String: [PluginOverlay]] = [:]

    /// Replaces `plugin`'s overlays (an empty set removes them); not saved with the project.
    public func setPluginOverlays(_ plugin: String, _ overlays: [PluginOverlay]) {
        guard pluginOverlaySets[plugin] ?? [] != overlays else { return }
        pluginOverlaySets[plugin] = overlays.isEmpty ? nil : overlays
        pluginOverlays = PluginOverlayIndex(pluginOverlaySets)
        pluginOverlayRevision += 1
    }

    /// Removes the overlays of every plugin `keep` refuses (all of them with no `keep`).
    public func clearPluginOverlays(keeping keep: (String) -> Bool = { _ in false }) {
        let kept = pluginOverlaySets.filter { keep($0.key) }
        guard kept.count != pluginOverlaySets.count else { return }
        pluginOverlaySets = kept
        pluginOverlays = PluginOverlayIndex(kept)
        pluginOverlayRevision += 1
    }

    /// One of `UIAction.mediaSources`: what the Media panel lists.
    public var mediaSource = "footage"
    /// Search and filters of each library panel, by panel name.
    public var libraryFilters: [String: LibraryPanelFilter] = [:]
    /// The library item sheet: Save selection as…, Duplicate & Edit… or Rename….
    public var libraryEditor: LibraryEditorRequest?
    /// The Effects panel's Apply with… sheet: an effect recipe's parameters and the part of the clip (#76).
    public var effectApply: EffectApplyRequest?
    /// A library panel's Search… or Generate… sheet: a plugin's candidates to preview and save (#81).
    public var librarySearch: LibrarySearchRequest?
    /// One of `UIAction.inspectorTabs`.
    public var inspectorTab = "video"
    /// One of `UIAction.settingsSections`: the section the Settings sheet shows.
    public var settingsSection = "general"
    /// The Settings search box: while it has text, Settings lists the matching settings of every section.
    public var settingsSearch = ""
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
    /// Quick Edit › Other…: the request typed for the selected clips (#449).
    public var showQuickEdit = false
    public var quickEditDraft = ""
    public var showSections = false
    /// The command palette (⇧⌘P) and the keyboard-shortcuts sheet (⌘/), both built from the menu bar.
    public var showCommands = false
    public var showShortcuts = false
    /// The All assets search (⇧⌘F, P2-B1) and its last query, kept while it is closed.
    public var showAssetSearch = false
    public var assetSearchQuery = ""
    /// Open Recent › View All… (⌃R): every remembered project, searchable (#529).
    public var showRecents = false
    /// Voice panel › Clone a voice… (#532).
    public var showVoiceClone = false
    /// Edits plugin hooks proposed, waiting for review.
    public var showPluginProposals = false

    public init(timelineLeading: Double = compactTimelineLeading) { self.timelineLeading = timelineLeading }

    /// The remembered layout: the timeline header's width and the library panel's width, tile sizes and grid or list.
    @MainActor
    public convenience init(settings: SettingsModel) {
        self.init(timelineLeading: settings.timelineHeaderWidth)
        libraryWidth = settings.libraryPanelWidth
        libraryLayouts = settings.libraryPanelLayouts
    }

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
        let width = max(100, timelineViewportWidth - timelineLeading - Self.fitMargin)
        return min(max(width / seconds, Self.timelineZoomRange.lowerBound), Self.timelineZoomRange.upperBound)
    }

    /// Shows the whole timeline from its start.
    public func zoomToFit(duration: Int, fps: Double) {
        setTimelineZoom(fitZoom(duration: duration, fps: fps), anchor: 0, viewOffset: timelineLeading)
    }

    /// Asks the timeline to scroll `frame` (clamped to `0...duration`) into view.
    public func revealInTimeline(_ frame: Int, duration: Int) {
        timelineReveal = TimelineReveal(frame: min(max(0, frame), max(0, duration)))
    }

    /// Closes the sheets that describe the previous project when another one opens.
    public func closeProjectSheets() {
        showExportReport = false
        showQuickEdit = false
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
        "shortcuts": \.showShortcuts, "updates": \.showUpdates, "recents": \.showRecents,
        "assets": \.showAssetSearch,
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

/// What a library panel shows: items matching the search, in one pack, with one tag, from one scope or source (nil: all).
public struct LibraryPanelFilter: Equatable, Sendable {
    public var query = ""
    public var pack: String?
    public var tag: String?
    /// A `LibraryScope` raw value.
    public var scope: String?
    /// A `LibrarySource` raw value (the chips under the search field); nil: all.
    public var source: String?
    /// "recent" or "favorites": a list shown instead of the home view; nil: the home view.
    public var collection: String?

    public init(query: String = "") { self.query = query }

    /// Whether the panel lists matches instead of its home view.
    public var isActive: Bool {
        !query.isEmpty || pack != nil || tag != nil || scope != nil || source != nil || collection != nil
    }
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
    /// A text preset's size, position, outline and animation, edited in the sheet (#380); nil for other kinds.
    public var textPreset: LibraryTextPreset?
    /// A brand kit's params, edited in the sheet (#453); nil for other kinds.
    public var brand: [String: JSONValue]?
    /// An effect preset's recipe as JSON text, edited in the sheet; nil for other kinds.
    public var recipe: String?

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

/// A library panel's Search… or Generate… sheet (#81): what to ask a `library.search` or `library.generate` provider
/// for, and the candidates it returned. `library search`, `library generate` and `library add --from-result` do the
/// same.
public struct LibrarySearchRequest: Identifiable {
    public let id = UUID()
    /// `library.search` or `library.generate`.
    public var capability: String
    /// The kinds the panel shows; `kind` is one of them.
    public var kinds: [LibraryKind]
    public var kind: LibraryKind
    /// Provider ID; nil uses the first one that serves the kind.
    public var provider: String?
    /// The search text or prompt.
    public var text = ""
    /// Where Save puts a candidate.
    public var scope: LibraryScope
    /// The running or last job.
    public var jobID: String?
    public var running = false
    public var candidates: [LibraryCandidate] = []
    public var error: String?
    /// Indexes of the candidates saved from this sheet.
    public var saved: Set<Int> = []

    public init(capability: String, kinds: [LibraryKind], scope: LibraryScope) {
        self.capability = capability
        self.kinds = kinds
        kind = kinds.first ?? .audio
        self.scope = scope
    }

    public var isGenerate: Bool { capability == PluginAPI.libraryGenerate }
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

/// Left-rail panels; `CommandCatalog.libraryPanels` lists their lowercased names. The eight asset panels come
/// first (`assets`, ⌘1…⌘8); `tools` follows the rail's divider (⌘T) and holds Voiceover and the plugin tools.
public enum LibraryTab: String, CaseIterable, Identifiable, Sendable {
    case media = "Media"
    case audio = "Audio"
    case text = "Text"
    case stickers = "Stickers"
    case effects = "Effects"
    case transitions = "Transitions"
    case filters = "Filters"
    case brand = "Brand"
    case tools = "Tools"

    public var id: String { rawValue }

    /// The panels of library items, in rail order (⌘1…⌘8).
    public static var assets: [LibraryTab] { allCases.filter(\.isAsset) }

    public var isAsset: Bool { self != .tools }

    /// The automation name (`ui.panel`).
    public var panelName: String { rawValue.lowercased() }

    /// The panel named `panelName`. The built-in tool ids (`captions`, `voice`, `beats`) name the Tools panel; `voice`
    /// was a panel of its own before Tools (`Self.toolForPanelName` says which tool a name selects).
    /// Whether the panel has a tile size and a grid or list (P1-10): its items are tiles of one library section.
    public var hasTileLayout: Bool { [.text, .stickers, .effects, .transitions, .filters].contains(self) }

    public init?(panelName: String) {
        if Self.toolForPanelName(panelName) != nil {
            self = .tools
            return
        }
        guard let tab = Self.allCases.first(where: { $0.panelName == panelName }) else { return nil }
        self = tab
    }

    /// The tool a panel name selects inside Tools: `voice` (the old Voice panel), `captions` and `beats`; nil otherwise.
    public static func toolForPanelName(_ name: String) -> String? { ToolID.builtIn.contains(name) ? name : nil }

    public var icon: String {
        switch self {
        case .media: return "film"
        case .audio: return "music.note"
        case .text: return "textformat"
        case .stickers: return "star"
        case .effects: return "sparkles"
        case .transitions: return "arrow.left.arrow.right"
        case .filters: return "circle.lefthalf.filled"
        case .brand: return "paintpalette"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}
