import BashCutDocument
import BashCutProject
import SwiftUI
import UniformTypeIdentifiers

/// The Brand panel (#453): the kit the project uses, and the saved kits. A click applies a kit to the whole project
/// (its palette and fonts restyle every text tied to brand roles, in one undo step); New Brand Kit… starts from the
/// project's kit. `library apply <brand>` and `library add --kind brand` do the same.
struct BrandLibraryView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            current
            Button("New Brand Kit…", systemImage: "plus") { document.beginNewBrand() }
            LibraryItemsSection(document: document, kinds: [.brand], tile: tile)
            Text("Click a kit to use it in this project: titles and cards tied to the brand take its colours and fonts. "
                + "Recipes, graphics and voiceover read it too.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var current: some View {
        if let params = document.project["brand"]?.object, let kit = try? LibraryBrand(params: Self.kitParams(params)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("In this project").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") { document.clearBrand() }.buttonStyle(.borderless).font(.caption)
                }
                HStack(spacing: 8) {
                    BrandSwatches(kit: kit)
                    Text(verbatim: params["name"]?.string ?? "").lineLimit(1)
                }
            }
            Divider()
        }
    }

    private func tile(_ item: LibraryItem) -> some View {
        Button { document.applyBrandFromLibrary(item) } label: {
            HStack(spacing: 8) {
                if let kit = try? LibraryBrand(params: item.params) { BrandSwatches(kit: kit) }
                VStack(alignment: .leading, spacing: 2) {
                    LibraryView.title(item)
                    if let fonts = (try? LibraryBrand(params: item.params))?.fonts, !fonts.isEmpty {
                        Text(verbatim: LibraryBrand.fontRoles.compactMap { fonts[$0] }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if document.project["brand"]?.object["library"]?.string == item.reference {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered).disabled(document.fileURL == nil)
    }

    /// The project's `brand` without where it came from.
    static func kitParams(_ params: [String: JSONValue]) -> [String: JSONValue] {
        params.filter { $0.key != "library" && $0.key != "name" }
    }
}

/// A kit's palette as small circles, in role order.
struct BrandSwatches: View {
    let kit: LibraryBrand

    var body: some View {
        HStack(spacing: -4) {
            ForEach(LibraryBrand.colorRoles.filter { kit.palette[$0] != nil }, id: \.self) { role in
                Circle().fill(Color(hex: kit.palette[role] ?? "#FFFFFF"))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
                    .help(LocalizedStringKey(role.capitalized))
            }
        }
    }
}

/// A brand kit's palette, fonts, logo, mascot poses, voice and disclosure in the library item sheet.
struct BrandKitFields: View {
    @Bindable var document: ProjectDocument
    @Binding var params: [String: JSONValue]
    @State private var stickers: [LibraryItem] = []
    @State private var newPose = ""
    @State private var cutting = false

    var body: some View {
        Section("Palette") {
            ForEach(LibraryBrand.colorRoles, id: \.self) { role in color(role) }
        }
        Section("Fonts") {
            ForEach(LibraryBrand.fontRoles, id: \.self) { role in
                TextField(LocalizedStringKey(role.capitalized), text: text(group: "fonts", role), prompt: Text("System"))
            }
        }
        Section("Logo and mascot") {
            stickerPicker("Logo", selection: Binding(
                get: { params["logo"]?.string ?? "" },
                set: { params["logo"] = $0.isEmpty ? nil : .string($0) }))
            ForEach(poses, id: \.self) { pose in
                HStack {
                    stickerPicker(LocalizedStringKey(pose), selection: Binding(
                        get: { params["mascot"]?.object[pose]?.string ?? "" },
                        set: { setPose(pose, $0.isEmpty ? nil : $0) }))
                    Button { setPose(pose, nil) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("Remove this pose")
                }
            }
            HStack {
                TextField("New pose", text: $newPose, prompt: Text("wave"))
                Button("Add") {
                    let pose = newPose.trimmingCharacters(in: .whitespaces)
                    guard !pose.isEmpty, let first = stickers.first else { return }
                    setPose(pose, first.reference)
                    newPose = ""
                }
                .disabled(stickers.isEmpty || newPose.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("From picture…") { poseFromPicture() }
                    .disabled(cutting || newPose.trimmingCharacters(in: .whitespaces).isEmpty || document.fileURL == nil)
                    .help("Cut the subject out of a photo and use it as this pose (library brand-pose)")
            }
        }
        Section("Voice") {
            TextField("Provider", text: text(group: "voice", "provider"), prompt: Text("voice.synthesize provider"))
            TextField("Voice", text: text(group: "voice", "voice"))
        }
        TextField("Disclosure", text: Binding(
            get: { params["disclosure"]?.string ?? "" },
            set: { params["disclosure"] = $0.isEmpty ? nil : .string($0) }), prompt: Text("Ảnh tạo bằng AI"))
            .task { stickers = (try? document.libraryCatalog.panelItems([.sticker]))?.filter { $0.file != nil } ?? [] }
    }

    /// Cuts a photo's subject out as a sticker and uses it as the new pose (`library brand-pose --image`).
    private func poseFromPicture() {
        let pose = newPose.trimmingCharacters(in: .whitespaces)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard !pose.isEmpty, panel.runModal() == .OK, let url = panel.url else { return }
        cutting = true
        Task {
            defer { cutting = false }
            do {
                let sticker = try await document.poseSticker(from: url, pose: pose)
                setPose(pose, sticker)
                newPose = ""
                stickers = (try? document.libraryCatalog.panelItems([.sticker]))?.filter { $0.file != nil } ?? []
            } catch {
                document.message = error.localizedDescription
            }
        }
    }

    private var poses: [String] { (params["mascot"]?.object.keys).map { $0.sorted() } ?? [] }

    private func setPose(_ pose: String, _ reference: String?) {
        var mascot = params["mascot"]?.object ?? [:]
        mascot[pose] = reference.map(JSONValue.string)
        params["mascot"] = mascot.isEmpty ? nil : .object(mascot)
    }

    private func color(_ role: String) -> some View {
        HStack {
            ColorPicker(LocalizedStringKey(role.capitalized), selection: Binding(
                get: { Color(hex: params["palette"]?.object[role]?.string ?? "#FFFFFF") },
                set: { set(group: "palette", role, $0.hex) }), supportsOpacity: false)
            if params["palette"]?.object[role] != nil {
                Button { set(group: "palette", role, nil) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless).help("Leave this colour unset")
            } else {
                Text("Unset").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func text(group: String, _ key: String) -> Binding<String> {
        Binding(get: { params[group]?.object[key]?.string ?? "" }, set: { set(group: group, key, $0.isEmpty ? nil : $0) })
    }

    private func set(group: String, _ key: String, _ value: String?) {
        var fields = params[group]?.object ?? [:]
        fields[key] = value.map(JSONValue.string)
        params[group] = fields.isEmpty ? nil : .object(fields)
    }

    private func stickerPicker(_ title: LocalizedStringKey, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag("")
            ForEach(stickers, id: \.reference) { LibraryView.title($0).tag($0.reference) }
            if !selection.wrappedValue.isEmpty, !stickers.contains(where: { $0.reference == selection.wrappedValue }) {
                Text(verbatim: selection.wrappedValue).tag(selection.wrappedValue)
            }
        }
    }
}
