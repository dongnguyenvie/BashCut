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

        /// Whether the font has every letter `language` is written with; nil for a language macOS does not know.
        public func covers(_ language: String) -> Bool? { ProjectFonts.covers(postScriptName, language: language) }

        /// `language`: adds `covers` for that language when macOS knows its letters.
        public func json(language: String? = nil) -> JSONValue {
            var value: [String: JSONValue] = [
                "name": .string(postScriptName), "family": .string(family), "style": .string(style),
                "source": .string(file != nil ? "project" : postScriptName.hasPrefix(ProjectFonts.systemPrefix) ? "system" : "installed"),
            ]
            if let file { value["file"] = .string(file.lastPathComponent) }
            if let language, let covers = covers(language) { value["covers"] = .bool(covers) }
            return .object(value)
        }
    }

    /// Names that draw with the Mac's own San Francisco: `System-` + an optional width (Condensed, Compressed,
    /// Expanded) + a weight (Regular, Medium, Semibold, Bold, Heavy, Black), such as `System-CondensedBlack`. Every
    /// Mac has it, and it places Vietnamese stacked tone marks correctly (Helvetica Neue's condensed faces do not).
    public static let systemPrefix = "System-"
    static let systemWeights: [(String, CGFloat)] = [
        ("Regular", 0), ("Medium", 0.23), ("Semibold", 0.3), ("Bold", 0.4), ("Heavy", 0.56), ("Black", 0.62),
    ]
    static let systemWidths: [(String, CGFloat)] = [("", 0), ("Condensed", -0.2), ("Compressed", -0.3), ("Expanded", 0.2)]

    /// Every `System-…` name, widths then weights.
    public static let systemNames: [String] = systemWidths.flatMap { width in
        systemWeights.map { systemPrefix + width.0 + $0.0 }
    }

    /// The font `name` draws with at `size`: a `System-…` name or a PostScript name (Helvetica when unknown).
    public static func font(_ name: String, size: CGFloat) -> CTFont {
        guard let traits = systemTraits(name), let base = CTFontCreateUIFontForLanguage(.system, size, nil) else {
            return CTFontCreateWithName(name as CFString, size, nil)
        }
        let attributes = [kCTFontTraitsAttribute: [kCTFontWeightTrait: traits.weight, kCTFontWidthTrait: traits.width]]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base), attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    static func systemTraits(_ name: String) -> (weight: CGFloat, width: CGFloat)? {
        guard name.hasPrefix(systemPrefix) else { return nil }
        let rest = name.dropFirst(systemPrefix.count)
        for (widthName, width) in systemWidths where rest.hasPrefix(widthName) {
            if let weight = systemWeights.first(where: { $0.0 == rest.dropFirst(widthName.count) }) {
                return (weight.1, width)
            }
        }
        return nil
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered: [URL] = []
    nonisolated(unsafe) private static var availability: [String: Bool] = [:]
    nonisolated(unsafe) private static var coverage: [String: Bool] = [:]
    nonisolated(unsafe) private static var alphabets: [String: CFCharacterSet?] = [:]

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

    /// The file in the project's fonts folder that holds `name` (a PostScript name); nil for an installed or unknown
    /// font. A text preset saved to the library keeps this file, so the preset draws the same in another project.
    public static func file(named name: String, projectRoot: URL) -> URL? {
        files(projectRoot: projectRoot).first { file in fonts(in: file).contains { $0.postScriptName == name } }
    }

    /// Brings a library text preset's font file into the project at `projectRoot` when the project lacks `name`:
    /// copied into its fonts folder and registered, like `fonts import`. Returns the fonts added; empty when the
    /// project has the font already or `file` does not hold `name` (the preset's font changed since it was saved).
    @discardableResult
    public static func adopt(_ file: URL, name: String, projectRoot: URL) throws -> [Font] {
        guard extensions.contains(file.pathExtension.lowercased()), self.file(named: name, projectRoot: projectRoot) == nil,
            fonts(in: file).contains(where: { $0.postScriptName == name })
        else { return [] }
        return try importFont(from: file, projectRoot: projectRoot)
    }

    /// The project's fonts first, then the installed ones (without the project's names).
    public static func list(projectRoot: URL?, installed includeInstalled: Bool = true) -> [Font] {
        let own = (projectRoot.map(files) ?? []).flatMap(fonts(in:))
        guard includeInstalled else { return own }
        let ownNames = Set(own.map(\.postScriptName))
        return own + installed.filter { !ownNames.contains($0.postScriptName) }
    }

    /// The `System-…` fonts, then the fonts installed on this Mac, read once (about a thousand; reading them takes
    /// a moment).
    public static let installed: [Font] = {
        let names = (CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []).filter { !$0.hasPrefix(".") }
        let system = systemNames.map { name in
            Font(postScriptName: name, family: "System", style: String(name.dropFirst(systemPrefix.count)), file: nil)
        }
        return system + names.sorted().map(installedFont)
    }()

    /// Whether `name` resolves to that font rather than the Helvetica fallback.
    /// The characters of `text` that `name` has no glyphs for, each once, in order (spaces and line breaks aside).
    /// Emoji are left out: no text font has them, and Core Text always draws them in Apple Color Emoji.
    public static func missingCharacters(_ name: String, text: String) -> String {
        let font = font(name, size: 12)
        var seen = Set<Character>()
        var missing = ""
        for character in text where !character.isWhitespace && !isEmoji(character) && seen.insert(character).inserted {
            let units = Array(String(character).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            if !CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) { missing.append(character) }
        }
        return missing
    }

    /// An emoji drawn as a picture: one with emoji presentation (🎉), or a sequence such as ✨, ❤️ or 1️⃣.
    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        return first.properties.isEmojiPresentation || (first.properties.isEmoji && scalars.count > 1)
    }

    public static func isAvailable(_ name: String) -> Bool {
        lock.lock()
        if let known = availability[name] {
            lock.unlock()
            return known
        }
        lock.unlock()
        let found = systemTraits(name) != nil || CTFontCopyPostScriptName(font(name, size: 12)) as String == name
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
            style: CTFontCopyName(font, kCTFontStyleNameKey) as String? ?? "", file: file)
    }

    /// Whether font `name` has every letter of `language` (a BCP 47 tag such as vi, fr or ja: its exemplar
    /// characters in upper and lower case, with accents and tone marks); nil when macOS does not know the language.
    public static func covers(_ name: String, language: String) -> Bool? {
        guard let letters = alphabet(language) else { return nil }
        let key = name + "|" + language
        lock.lock()
        if let known = coverage[key] {
            lock.unlock()
            return known
        }
        lock.unlock()
        let covered = CFCharacterSetIsSupersetOfSet(CTFontCopyCharacterSet(font(name, size: 12)), letters)
        lock.lock()
        coverage[key] = covered
        lock.unlock()
        return covered
    }

    /// The letters `language` is written with, from the locale data; nil for a tag whose language macOS does not know.
    public static func alphabet(_ language: String) -> CFCharacterSet? {
        lock.lock()
        if let known = alphabets[language] {
            lock.unlock()
            return known
        }
        lock.unlock()
        let code = Locale(identifier: language).language.languageCode?.identifier ?? ""
        let letters: CFCharacterSet? = Locale.LanguageCode.isoLanguageCodes.contains(Locale.LanguageCode(code))
            ? CFLocaleCreate(nil, CFLocaleIdentifier(rawValue: language as CFString))
                .flatMap { CFLocaleGetValue($0, .exemplarCharacterSet) }
                .map { unsafeDowncast($0, to: CFCharacterSet.self) }
            : nil
        lock.lock()
        alphabets[language] = .some(letters)
        lock.unlock()
        return letters
    }

    public struct FontError: LocalizedError {
        public let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
