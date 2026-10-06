import BashCutProject
import CoreText
import Foundation

/// Fonts for text items (#412): the project's own `fonts/` folder, registered for this process only (preview and
/// export find them by PostScript name; nothing is installed on the Mac), and the fonts installed on the Mac.
/// A `textStyle.font` that resolves to neither falls back to Helvetica in `TextRenderer`; `isAvailable` lets review
/// flag it.
public enum ProjectFonts {
    public static let folder = "fonts"
    public static let extensions: Set<String> = ["ttf", "otf", "ttc"]

    public struct Font: Sendable, Equatable {
        public let postScriptName: String
        public let family: String
        public let style: String
        /// The file in the project's fonts folder; nil for an installed font.
        public let file: URL?
        /// Has the letters Vietnamese needs (ă â đ ê ô ơ ư and the stacked tone marks such as ệ ữ ở).
        public let vietnamese: Bool

        public var json: JSONValue {
            var value: [String: JSONValue] = [
                "name": .string(postScriptName), "family": .string(family), "style": .string(style),
                "vietnamese": .bool(vietnamese), "source": .string(file == nil ? "installed" : "project"),
            ]
            if let file { value["file"] = .string(file.lastPathComponent) }
            return .object(value)
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered: [URL] = []
    nonisolated(unsafe) private static var availability: [String: Bool] = [:]

    /// The font files in `projectRoot/fonts`, sorted by name.
    public static func files(projectRoot: URL) -> [URL] {
        let directory = projectRoot.appendingPathComponent(folder, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { extensions.contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
            .map { directory.appendingPathComponent($0) }
    }

    /// Registers the project's fonts for this process, replacing the previous project's (nil: none).
    @discardableResult
    public static func activate(projectRoot: URL?) -> [Font] {
        let files = projectRoot.map(Self.files) ?? []
        lock.lock()
        let stale = registered.filter { !files.contains($0) }
        let fresh = files.filter { !registered.contains($0) }
        registered = files
        availability.removeAll()
        lock.unlock()
        for url in stale { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
        for url in fresh { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        if !stale.isEmpty || !fresh.isEmpty { TextRenderer.clearCache() }
        return files.flatMap(fonts(in:))
    }

    /// Checks `source` is a font file CoreText reads, copies it into `projectRoot/fonts` and registers it.
    public static func importFont(from source: URL, projectRoot: URL) throws -> [Font] {
        guard extensions.contains(source.pathExtension.lowercased()) else {
            throw FontError("Fonts must be .ttf, .otf or .ttc files")
        }
        let found = fonts(in: source)
        guard !found.isEmpty else { throw FontError("\(source.lastPathComponent) is not a font file") }
        let directory = projectRoot.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(source.lastPathComponent)
        if target.standardizedFileURL != source.standardizedFileURL {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
        }
        activate(projectRoot: projectRoot)
        return fonts(in: target)
    }

    /// The project's fonts first, then the installed ones (without the project's names).
    public static func list(projectRoot: URL?, installed includeInstalled: Bool = true) -> [Font] {
        let own = (projectRoot.map(files) ?? []).flatMap(fonts(in:))
        guard includeInstalled else { return own }
        let ownNames = Set(own.map(\.postScriptName))
        return own + installed.filter { !ownNames.contains($0.postScriptName) }
    }

    /// The fonts installed on this Mac, read once (about a thousand; reading them takes a moment).
    public static let installed: [Font] = {
        let names = (CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []).filter { !$0.hasPrefix(".") }
        return names.sorted().map(installedFont)
    }()

    /// Whether `name` resolves to that font rather than the Helvetica fallback.
    public static func isAvailable(_ name: String) -> Bool {
        lock.lock()
        if let known = availability[name] {
            lock.unlock()
            return known
        }
        lock.unlock()
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        let found = CTFontCopyPostScriptName(font) as String == name
        lock.lock()
        availability[name] = found
        lock.unlock()
        return found
    }

    private static func fonts(in file: URL) -> [Font] {
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor] ?? []
        return descriptors.map { descriptor in
            let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
            return describe(font, file: file)
        }
    }

    private static func installedFont(_ name: String) -> Font {
        describe(CTFontCreateWithName(name as CFString, 12, nil), file: nil)
    }

    private static func describe(_ font: CTFont, file: URL?) -> Font {
        Font(
            postScriptName: CTFontCopyPostScriptName(font) as String, family: CTFontCopyFamilyName(font) as String,
            style: CTFontCopyName(font, kCTFontStyleNameKey) as String? ?? "", file: file,
            vietnamese: coversVietnamese(font))
    }

    private static let vietnameseSample = "ăâđêôơưĂÂĐÊÔƠƯệữởấằẫỳ"

    static func coversVietnamese(_ font: CTFont) -> Bool {
        let set = CTFontCopyCharacterSet(font)
        return vietnameseSample.unicodeScalars.allSatisfy { CFCharacterSetIsLongCharacterMember(set, $0.value) }
    }

    public struct FontError: LocalizedError {
        public let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
