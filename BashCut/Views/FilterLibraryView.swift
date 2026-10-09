import BashCutProject
import SwiftUI

/// The Filters panel: library looks (filter stacks, #79) in the shared library UI, plus the project's 3D LUTs.
struct FilterLibraryView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Looks").font(.headline)
                Spacer()
                Button("Add adjustment", systemImage: "camera.filters") {
                    do { try document.addAdjustment() } catch { document.message = error.localizedDescription }
                }.disabled(document.fileURL == nil)
            }
            Text(
                document.selected == nil
                    ? "With nothing selected, a look adds an adjustment that grades every layer below it."
                    : "A look grades the selected clip or adjustment."
            ).font(.caption).foregroundStyle(.secondary)
            LibraryItemsSection(
                document: document, kinds: [.look], saveKinds: [.look], fileKind: .look
            ) { item in
                Button { use(item) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        LibraryView.title(item)
                        if let summary = summary(item) {
                            Text(summary).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(document.fileURL == nil)
            }
            Divider()
            HStack {
                Text("3D LUTs").font(.headline)
                Spacer()
                Button("Import .cube…", action: document.importColorLUT)
            }
            if document.project.colorLUTs.isEmpty {
                Text("No LUTs imported.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(document.project.colorLUTs) { lut in
                HStack {
                    Button(lut.name) { document.applyColorLUT(lut.id) }
                    Spacer()
                    Menu {
                        Button("Delete LUT", role: .destructive) { document.deleteColorLUT(lut) }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                }
            }
            if let lutID = document.selected?["color"]?.object["lut"]?.string,
                document.project.colorLUTs.contains(where: { $0.id == lutID })
            {
                Slider(
                    value: Binding(
                        get: { document.selected?["color"]?.object["lutStrength"]?.double ?? 1 },
                        set: { value in document.setColorLUTStrength(value) }), in: 0...1)
                Button("Remove LUT") { document.applyColorLUT(nil) }
            }
        }
    }

    private func use(_ item: LibraryItem) {
        if document.selected == nil { document.placeFromLibrary(item) } else { document.applyFromLibrary(item) }
    }

    private func summary(_ item: LibraryItem) -> String? {
        item.file != nil ? String(localized: "With LUT") : nil
    }
}

/// A look's grade and LUT in the library item sheet (#79); `library update --params` sets the same fields.
struct FilterStackFields: View {
    @Binding var stack: FilterStack
    /// Whether the look keeps its own LUT; nil when it has none.
    @Binding var keepsLUT: Bool?

    var body: some View {
        slider("Exposure", key: "exposure", default: 0, in: -3...3)
        slider("Contrast", key: "contrast", default: 1, in: 0...2)
        slider("Saturation", key: "saturation", default: 1, in: 0...2)
        if let keeps = keepsLUT {
            Toggle("Keep its LUT", isOn: Binding(get: { keeps }, set: { keepsLUT = $0 }))
            if keeps { slider("LUT strength", key: "lutStrength", default: 1, in: 0...1) }
        }
    }

    private func slider(
        _ title: LocalizedStringKey, key: String, default value: Double, in range: ClosedRange<Double>
    ) -> some View {
        let binding = Binding(
            get: { stack.color[key]?.double ?? value },
            set: { stack.color[key] = .number(($0 * 100).rounded() / 100) })
        return LabeledContent(title) {
            HStack {
                Slider(value: binding, in: range)
                Text(binding.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit().frame(width: 40, alignment: .trailing)
            }
        }
    }
}
