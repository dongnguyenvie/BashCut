import BashCutProject
import SwiftUI

struct FilterLibraryView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style kits").font(.headline)
            ForEach(document.project.styleKits) { kit in
                Button { document.runStyleKit(kit) } label: { title(kit.title, builtIn: kit.isBuiltIn) }
                    .help("Grades the whole video and restyles every caption in one undoable step.")
                    .contextMenu {
                        if !kit.isBuiltIn {
                            Button("Delete style kit", role: .destructive) { document.deleteCustomStyleKit(kit) }
                        }
                    }
            }.disabled(document.project.contentDuration == 0)
            Divider()
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
            ForEach(document.project.looks) { look in
                Button { document.applyLook(look) } label: { title(look.title, builtIn: look.isBuiltIn) }
                    .contextMenu {
                        if !look.isBuiltIn {
                            Button("Delete look", role: .destructive) { document.deleteCustomLook(look) }
                        }
                    }
            }.disabled(document.fileURL == nil)
            LibraryItemsSection(document: document, kinds: [.look], saveKinds: [.look]) { item in
                Button {
                    if document.selected == nil { document.placeFromLibrary(item) } else { document.applyFromLibrary(item) }
                } label: {
                    LibraryView.title(item).frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(document.fileURL == nil)
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

    /// Built-in titles are UI strings; custom ones are user content and stay as typed.
    private func title(_ text: String, builtIn: Bool) -> Text {
        builtIn ? Text(LocalizedStringKey(text)) : Text(verbatim: text)
    }
}
