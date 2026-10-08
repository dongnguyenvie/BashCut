import AppKit
import BashCutEngine
import BashCutProject
import SwiftUI

/// Font, text colour and outline colour of a text style (#413), shared by Inspector › Text and the text preset sheet.
/// Unset fields show the preset's own; the font menu lists the project's fonts first, then the installed families,
/// and marks the fonts that lack letters of the content language.
struct TextFontFields: View {
    let preset: String?
    @Binding var style: [String: JSONValue]
    /// The project's content language (BCP 47); empty when not set, and then no font is marked.
    var language = ""
    /// Shows Add Font… (needs a saved project).
    var addFont: (() -> Void)?

    var body: some View {
        let font = style["font"]?.string
        LabeledContent("Font") {
            Menu(font ?? String(localized: "Preset (\(TextPresetStyle.font(preset)))")) {
                Button("Preset (\(TextPresetStyle.font(preset)))") { style["font"] = nil }
                let own = ProjectFontCatalog.shared.fonts
                if !own.isEmpty {
                    Section("Project") {
                        ForEach(own, id: \.postScriptName) { item in button(item, family: true) }
                    }
                }
                Section("Installed") {
                    ForEach(Self.families, id: \.name) { family in
                        Menu(family.name) {
                            ForEach(family.fonts, id: \.postScriptName) { item in button(item) }
                        }
                    }
                }
                if let addFont {
                    Divider()
                    Button("Add Font…", action: addFont)
                }
            }
        }
        if let font, !ProjectFonts.isAvailable(font) {
            Label("\(font) is not available and draws as Helvetica", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
        colorPicker("Text colour", key: "fill", fallback: TextPresetStyle.fill(preset))
        colorPicker("Outline colour", key: "stroke", fallback: "#000000")
    }

    /// `family`: the title names the family too (the project's fonts are not grouped by family).
    private func button(_ item: ProjectFonts.Font, family: Bool = false) -> some View {
        let title = item.style.isEmpty ? item.postScriptName : family ? "\(item.family) \(item.style)" : item.style
        let lacking = !language.isEmpty && item.covers(language) == false
        let name = Locale.current.localizedString(forIdentifier: language) ?? language
        return Button(lacking ? String(localized: "\(title) (missing \(name) letters)") : title) {
            style["font"] = .string(item.postScriptName)
        }
    }

    private func colorPicker(_ title: LocalizedStringKey, key: String, fallback: String) -> some View {
        HStack {
            ColorPicker(title, selection: Binding(
                get: { Color(hex: style[key]?.string ?? fallback) },
                set: { style[key] = .string($0.hex) }), supportsOpacity: false)
            if style[key] != nil {
                Button { style[key] = nil } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless).help("Use the preset's colour")
            }
        }
    }

    private struct Family {
        let name: String
        let fonts: [ProjectFonts.Font]
    }

    private static let families: [Family] = Dictionary(grouping: ProjectFonts.installed, by: \.family)
        .map { Family(name: $0.key, fonts: $0.value) }.sorted { $0.name < $1.name }
}

extension Color {
    /// `#RRGGBB`; anything else is white.
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(
            .sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255)
    }

    /// `#RRGGBB` in sRGB.
    var hex: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .white
        func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(color.redComponent), byte(color.greenComponent), byte(color.blueComponent))
    }
}
