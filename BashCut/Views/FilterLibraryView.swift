import BashCutProject
import SwiftUI

struct FilterLibraryView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Original") { document.patchSelected(["color": .object([:])], label: "Reset color") }
                .disabled(document.selected == nil)
            Button("Muted film") {
                document.patchSelected(
                    ["color": .object(["saturation": .number(0.8), "contrast": .number(0.9)])],
                    label: "Muted film")
            }.disabled(document.selected == nil)
            Button("Black & white") {
                document.patchSelected(
                    ["color": .object(["saturation": .integer(0)])], label: "Black & white")
            }.disabled(document.selected == nil)
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
                        .disabled(document.selected == nil)
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
}
