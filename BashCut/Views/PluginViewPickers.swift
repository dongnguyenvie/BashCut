import BashCutEngine
import BashCutPlugin
import BashCutProject
import SwiftUI

/// A `colorPicker` component (`views.colorPicker`): a colour well. The colour panel reports every step of a drag, so
/// the change goes to the plugin 250 ms after the colour stops moving (one event per pick, not one per step).
struct PluginColorPickerView: View {
    let node: PluginViewNode
    @Bindable var model: PluginViewModel
    @State private var hex = "#FFFFFF"
    @State private var debounce: Task<Void, Never>?

    private var alpha: Bool { node.bool("alpha") }

    var body: some View {
        ColorPicker(selection: Binding(
            get: { Self.color(hex) },
            set: { color in
                let next = Self.hex(color, alpha: alpha)
                guard next != hex else { return }
                hex = next
                debounce?.cancel()
                debounce = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    model.send(PluginViewEvent(node: node.id, kind: .change, value: .string(next)))
                }
            }), supportsOpacity: alpha
        ) {
            HStack(spacing: 4) {
                Text(verbatim: node.string("label") ?? "").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(verbatim: hex).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .disabled(node.bool("disabled"))
        .onAppear { hex = current }
        .onChange(of: model.values[node.id]) { _, _ in
            if debounce == nil || debounce?.isCancelled == true { hex = current }
        }
        .onDisappear { debounce?.cancel() }
    }

    private var current: String {
        model.values[node.id]?.string.flatMap { PluginViewColor.normalized($0, alpha: alpha) }
            ?? (alpha ? "#FFFFFFFF" : "#FFFFFF")
    }

    static func color(_ hex: String) -> Color {
        let parts = PluginViewColor.components(hex) ?? (1, 1, 1, 1)
        return Color(.sRGB, red: parts.red, green: parts.green, blue: parts.blue, opacity: parts.alpha)
    }

    static func hex(_ color: Color, alpha: Bool) -> String {
        let value = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return PluginViewColor.hex(
            red: value.redComponent, green: value.greenComponent, blue: value.blueComponent,
            alpha: value.alphaComponent, includeAlpha: alpha)
    }
}

/// A `fontPicker` component (`views.fontPicker`): the project's fonts, then the installed families (the fonts
/// `fonts list` lists). `by: font` (default) picks a face by PostScript name; `by: family` picks a family name (what
/// CSS `font-family` wants). Fonts that lack letters of the project's content language are marked.
struct PluginFontPickerView: View {
    let node: PluginViewNode
    @Bindable var model: PluginViewModel

    private var byFamily: Bool { node.string("by") == "family" }

    var body: some View {
        let value = model.values[node.id]?.string ?? ""
        let own = ProjectFontCatalog.shared.fonts
        // The label above the menu: beside it, a long label in a narrow column (the Inspector) left the menu a few
        // pixels wide.
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: node.string("label") ?? "").font(.caption).foregroundStyle(.secondary)
            Menu(value.isEmpty ? String(localized: "Choose a font") : value) {
                if !own.isEmpty {
                    Section("Project") {
                        if byFamily {
                            ForEach(Self.families(own), id: \.name) { family in pick(family.name, fonts: family.fonts) }
                        } else {
                            ForEach(own, id: \.postScriptName) { font in pick(font, full: true) }
                        }
                    }
                }
                Section("Installed") {
                    ForEach(Self.installed, id: \.name) { family in
                        if byFamily {
                            pick(family.name, fonts: family.fonts)
                        } else {
                            Menu(family.name) {
                                ForEach(family.fonts, id: \.postScriptName) { font in pick(font, full: false) }
                            }
                        }
                    }
                }
            }.disabled(node.bool("disabled")).frame(maxWidth: .infinity, alignment: .leading)
        }
        if !value.isEmpty, !byFamily, !ProjectFonts.isAvailable(value) {
            Label("\(value) is not available and draws as Helvetica", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private var language: String { model.document.contentLanguage }

    private func pick(_ font: ProjectFonts.Font, full: Bool) -> some View {
        let title = font.style.isEmpty ? font.postScriptName : full ? "\(font.family) \(font.style)" : font.style
        return Button(marked(title, lacking: !language.isEmpty && font.covers(language) == false)) {
            send(font.postScriptName)
        }
    }

    private func pick(_ family: String, fonts: [ProjectFonts.Font]) -> some View {
        Button(marked(family, lacking: !language.isEmpty && fonts.allSatisfy { $0.covers(language) == false })) {
            send(family)
        }
    }

    private func marked(_ title: String, lacking: Bool) -> String {
        guard lacking else { return title }
        let name = Locale.current.localizedString(forIdentifier: language) ?? language
        return String(localized: "\(title) (missing \(name) letters)")
    }

    private func send(_ value: String) {
        model.send(PluginViewEvent(node: node.id, kind: .change, value: .string(value)))
    }

    private struct Family {
        let name: String
        let fonts: [ProjectFonts.Font]
    }

    private static func families(_ fonts: [ProjectFonts.Font]) -> [Family] {
        Dictionary(grouping: fonts, by: \.family).map { Family(name: $0.key, fonts: $0.value) }.sorted { $0.name < $1.name }
    }

    private static let installed = families(ProjectFonts.installed)
}
