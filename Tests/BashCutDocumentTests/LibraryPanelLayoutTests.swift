import BashCutDocument
import Foundation
import Testing

@MainActor
struct LibraryPanelLayoutTests {
    private let suite = "bashcut-library-layout-tests-" + UUID().uuidString

    @Test("The panel starts at 372 pt on a screen of 1680 pt or more and 300 pt below, and a dragged width stays in 300…520")
    func widths() {
        #expect(LibraryPanelMetrics.defaultWidth(screenWidth: 1920) == 372)
        #expect(LibraryPanelMetrics.defaultWidth(screenWidth: 1680) == 372)
        #expect(LibraryPanelMetrics.defaultWidth(screenWidth: 1440) == 300)
        #expect(LibraryPanelMetrics.clamp(120) == 300)
        #expect(LibraryPanelMetrics.clamp(444.6) == 445)
        #expect(LibraryPanelMetrics.clamp(900) == 520)
        #expect(LibraryPanelMetrics.wideWidth == 760)
    }

    @Test("A tile size is 0…1 and maps to a tile width; a layout round-trips through JSON")
    func layout() throws {
        #expect(LibraryPanelLayout(tileSize: -3).tileSize == 0)
        #expect(LibraryPanelLayout(tileSize: 9).tileSize == 1)
        #expect(LibraryPanelLayout(tileSize: 0).tileMinimum == LibraryPanelLayout.minimumRange.lowerBound)
        #expect(LibraryPanelLayout(tileSize: 1).tileMinimum == LibraryPanelLayout.minimumRange.upperBound)
        let layout = LibraryPanelLayout(tileSize: 0.75, isList: true)
        #expect(try JSONDecoder().decode(LibraryPanelLayout.self, from: JSONEncoder().encode(layout)) == layout)
    }

    @Test("Width and each panel's layout are remembered in Settings")
    func remembered() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsModel(defaults: defaults)
        #expect(settings.libraryPanelWidth == nil)
        #expect(settings.libraryPanelLayouts.isEmpty)
        settings.libraryPanelWidth = 480
        settings.libraryPanelLayouts = ["stickers": LibraryPanelLayout(tileSize: 0.9), "effects": LibraryPanelLayout(isList: true)]
        let again = SettingsModel(defaults: defaults)
        #expect(again.libraryPanelWidth == 480)
        #expect(again.libraryPanelLayouts["stickers"]?.tileSize == 0.9)
        #expect(again.libraryPanelLayouts["effects"]?.isList == true)
        // A stored width outside the range is pulled back in.
        defaults.set(2000.0, forKey: "libraryPanelWidth")
        #expect(SettingsModel(defaults: defaults).libraryPanelWidth == 520)
        #expect(LibraryTab.stickers.hasTileLayout && !LibraryTab.media.hasTileLayout && !LibraryTab.audio.hasTileLayout)
    }
}
