import BashCutProject
import SwiftUI

/// The Filters panel: looks (filter stacks, #79), style kits and the project's own looks in the shared library UI,
/// plus the project's 3D LUTs.
struct FilterLibraryView: View {
    @Bindable var document: ProjectDocument

    /// The params key that marks a style kit, and the one that marks a project look, among the panel's entries.
    private static let styleKitKey = "styleKit"
    private static let projectLookKey = "projectLook"

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
                document: document, kinds: [.look], saveKinds: [.look], fileKind: .look, extraItems: entries,
                extraActions: actions
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
                .disabled(isDisabled(item))
                .help(item.params[Self.styleKitKey] == nil
                    ? Text(verbatim: "") : Text("Grades the whole video and restyles every caption in one undoable step."))
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

    /// Style kits and the project's own looks (`style save`, `looks save`), shown with the library's looks. IDs carry
    /// a colon, which library IDs never have, so they never clash with an item.
    private var entries: [LibraryItem] {
        let kits = document.project.styleKits.map { kit in
            LibraryItem(
                id: "kit:\(kit.id)", kind: .look, name: kit.title, pack: "Style kits",
                params: [Self.styleKitKey: .string(kit.id)], scope: kit.isBuiltIn ? .builtIn : .project)
        }
        let looks = document.project.customLooks.map { look in
            LibraryItem(
                id: "look:\(look.id)", kind: .look, name: look.title, pack: "Project looks",
                params: ["color": .object(look.color), Self.projectLookKey: .string(look.id)], scope: .project)
        }
        return kits + looks
    }

    private func actions(_ item: LibraryItem) -> [LibraryPanelAction] {
        let project = document.project
        if let kit = item.params[Self.styleKitKey]?.string.flatMap(project.styleKit), !kit.isBuiltIn {
            return [LibraryPanelAction(title: "Delete style kit", destructive: true) { document.deleteCustomStyleKit(kit) }]
        }
        if let look = item.params[Self.projectLookKey]?.string.flatMap(project.look) {
            return [LibraryPanelAction(title: "Delete look", destructive: true) { document.deleteCustomLook(look) }]
        }
        return []
    }

    private func use(_ item: LibraryItem) {
        let project = document.project
        if let kit = item.params[Self.styleKitKey]?.string.flatMap(project.styleKit) {
            document.runStyleKit(kit)
        } else if let look = item.params[Self.projectLookKey]?.string.flatMap(project.look) {
            document.applyLook(look)
        } else if document.selected == nil {
            document.placeFromLibrary(item)
        } else {
            document.applyFromLibrary(item)
        }
    }

    private func isDisabled(_ item: LibraryItem) -> Bool {
        item.params[Self.styleKitKey] != nil ? document.project.contentDuration == 0 : document.fileURL == nil
    }

    private func summary(_ item: LibraryItem) -> String? {
        if item.params[Self.styleKitKey] != nil { return String(localized: "Style kit") }
        return item.file != nil ? String(localized: "With LUT") : nil
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
