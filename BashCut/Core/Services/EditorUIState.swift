import Foundation
import Observation

/// Editor view state that is not part of the project: timeline zoom and scroll requests, toggles, the
/// open library panel and inspector tab, and which editor sheets are showing. `ui.view`, `ui.panel`,
/// `ui.open` and `ui.dialog` read and change it; nothing here is saved with the project.
@MainActor @Observable
public final class EditorUIState {
    public static let timelineZoomRange: ClosedRange<Double> = 10...140
    public static let zoomStep = 1.25

    /// Timeline pixels per second.
    public var timelineScale = 50.0
    public var timelineReveal: TimelineReveal?
    public var snapping = true
    public var showSafeArea = false
    public var showAgentDock = true
    public var libraryTab: LibraryTab = .media
    /// One of `UIAction.inspectorTabs`.
    public var inspectorTab = "video"

    // Editor sheets and popovers; `ModalCenter` reports them to automation.
    public var showNewProject = false
    public var showExport = false
    public var showExportReport = false
    public var showAgentChanges = false
    public var showExternalChanges = false
    public var showLegacyImportReport = false
    public var showReview = false
    public var showHistory = false
    public var showPlugins = false
    public var showSettings = false
    public var showDoctor = false
    public var showAsk = false
    public var showSections = false

    public init() {}

    public var canZoomIn: Bool { timelineScale < Self.timelineZoomRange.upperBound }
    public var canZoomOut: Bool { timelineScale > Self.timelineZoomRange.lowerBound }

    public func setTimelineZoom(_ value: Double) {
        timelineScale = min(max(value, Self.timelineZoomRange.lowerBound), Self.timelineZoomRange.upperBound)
    }

    public func zoomIn() { setTimelineZoom(timelineScale * Self.zoomStep) }

    public func zoomOut() { setTimelineZoom(timelineScale / Self.zoomStep) }

    /// Asks the timeline to scroll `frame` (clamped to `0...duration`) into view.
    public func revealInTimeline(_ frame: Int, duration: Int) {
        timelineReveal = TimelineReveal(frame: min(max(0, frame), max(0, duration)))
    }

    /// Closes the sheets that describe the previous project when another one opens.
    public func closeProjectSheets() {
        showExportReport = false
        showAgentChanges = false
        showExternalChanges = false
        showLegacyImportReport = false
    }

    /// Sheets that open unconditionally by name (`ui.open`).
    public static let toggledDialogs: [String: ReferenceWritableKeyPath<EditorUIState, Bool>] = [
        "review": \.showReview, "history": \.showHistory, "plugins": \.showPlugins, "settings": \.showSettings,
        "doctor": \.showDoctor, "ask": \.showAsk, "sections": \.showSections,
    ]
}

/// A one-off request for the timeline to scroll a frame into view.
public struct TimelineReveal: Equatable, Sendable {
    public let frame: Int
    public let id = UUID()

    public init(frame: Int) { self.frame = frame }
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
