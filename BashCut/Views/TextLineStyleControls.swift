import BashCutProject
import SwiftUI

/// Inspector › Text › Lines (text phase 2): each line of a title can have its own font, size, text and outline colour
/// (`textStyle.lines`), so one title can mix two fonts. Every change is `setLineStyle`, like `text.line-style`.
struct TextLineStyleControls: View {
    @Bindable var document: ProjectDocument
    let item: Item

    private var lines: [String] { item.text.components(separatedBy: "\n") }

    var body: some View {
        if lines.count > 1 {
            DisclosureGroup("Lines") {
                ForEach(Array(lines.prefix(TextLineStyles.maximumLines).enumerated()), id: \.offset) { index, text in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(text.isEmpty ? String(localized: "Empty line") : text).lineLimit(1).bold()
                            Spacer()
                            if style(index) != nil {
                                Button { apply([:], line: index, clear: true) } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }.buttonStyle(.borderless).help("Use the title's look for this line")
                            }
                        }
                        TextFontFields(
                            preset: item.textPreset,
                            style: Binding(
                                get: { style(index) ?? [:] },
                                set: { fields in
                                    var patch: [String: JSONValue] = [:]
                                    for key in ["font", "fill", "stroke"] { patch[key] = fields[key] ?? .null }
                                    apply(patch, line: index, coalesce: true)
                                }),
                            language: document.contentLanguage,
                            inherited: currentStyle.filter { ["font", "fill", "stroke"].contains($0.key) })
                        HStack {
                            Text("Size")
                            Slider(
                                value: Binding(
                                    get: { TextLineStyles.scale(currentStyle, line: index) },
                                    set: { apply(["scale": .number(($0 * 100).rounded() / 100)], line: index, coalesce: true) }),
                                in: 0.3...3)
                            Text(String(format: "%.2g×", TextLineStyles.scale(currentStyle, line: index)))
                                .monospacedDigit().frame(width: 40)
                        }
                    }
                    Divider()
                }
            }
        }
    }

    /// The item's text style as stored now (the view's copy is stale right after an edit).
    private var currentStyle: [String: JSONValue] {
        document.project.tracks.flatMap(\.items).first { $0.id == item.id }?["textStyle"]?.object ?? [:]
    }

    private func style(_ index: Int) -> [String: JSONValue]? { TextLineStyles.style(currentStyle, line: index) }

    private func apply(_ patch: [String: JSONValue], line: Int, clear: Bool = false, coalesce: Bool = false) {
        do { try document.setLineStyle(patch, line: line, clear: clear, item: item.id, coalesce: coalesce) } catch {
            document.message = error.localizedDescription
        }
    }
}
