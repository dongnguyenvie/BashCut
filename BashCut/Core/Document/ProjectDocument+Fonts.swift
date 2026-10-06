import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Observation
import UniformTypeIdentifiers

/// The open project's own fonts, observed by the font menus so a font added from the menu or `fonts import` shows
/// at once.
@MainActor @Observable final class ProjectFontCatalog {
    static let shared = ProjectFontCatalog()
    private(set) var fonts: [ProjectFonts.Font] = []

    /// Registers the fonts of the project at `projectRoot` (nil: none) and publishes them.
    func activate(projectRoot: URL?) { fonts = ProjectFonts.activate(projectRoot: projectRoot) }
}

/// Project fonts (#415): Inspector › Text › Font › Add Font… and `fonts import` copy a font into the project's
/// `fonts` folder, which is registered for this process whenever the project opens.
extension ProjectDocument {
    func importFont() {
        guard fileURL != nil else {
            message = String(localized: "Save the project before adding a font")
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ProjectFonts.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        guard let sources = ModalCenter.shared.open(panel, name: "import-font"), !sources.isEmpty else { return }
        do {
            var names: [String] = []
            for source in sources { names += try importFont(from: source).map(\.postScriptName) }
            message = String(localized: "Font added: \(names.joined(separator: ", "))")
        } catch { message = error.localizedDescription }
    }

    /// Copies `source` into the project's fonts folder and registers it; returns the fonts in the file.
    @discardableResult
    func importFont(from source: URL) throws -> [ProjectFonts.Font] {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Save the project before adding a font")
        }
        let fonts = try ProjectFonts.importFont(from: source, projectRoot: root)
        ProjectFontCatalog.shared.activate(projectRoot: root)
        DebugLog.write("project", "font added: \(fonts.map(\.postScriptName).joined(separator: ", "))")
        rebuild()
        return fonts
    }
}
