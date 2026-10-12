import AppKit
import BashCutDocument
import BashCutProject
import SwiftUI

struct NewProjectView: View {
    @Bindable var document: ProjectDocument
    @Environment(\.dismiss) private var dismiss
    @State private var setup = ProjectSetup()
    @State private var parent: URL?
    @State private var footage: URL?
    @State private var error = ""
    /// Brand kits saved on this Mac, from plugins or built in (#453); a project's own kits stay with that project.
    @State private var brands: [LibraryItem] = []
    @State private var brand: String?
    @FocusState private var nameFocused: Bool

    /// nil is Auto: the first video or image clip sets the shape; picking a shape fixes it.
    private var frame: Binding<ProjectSetup.Canvas?> {
        Binding(
            get: { setup.canvasFromFirstClip ? nil : setup.canvas },
            set: { choice in
                setup.canvasFromFirstClip = choice == nil
                setup.canvas = choice ?? .portrait
            })
    }

    private var valid: Bool { parent != nil && (try? setup.project()) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New project").font(.title2.bold())
            Form {
                TextField("Project name", text: $setup.name).focused($nameFocused)
                Picker("Frame", selection: frame) {
                    Text("Auto · from the first clip").tag(ProjectSetup.Canvas?.none)
                    Divider()
                    Text("Portrait · 9:16").tag(ProjectSetup.Canvas?.some(.portrait))
                    Text("Landscape · 16:9").tag(ProjectSetup.Canvas?.some(.landscape))
                    Text("Square · 1:1").tag(ProjectSetup.Canvas?.some(.square))
                }
                Picker("Resolution", selection: $setup.resolution) {
                    Text("HD · 720").tag(ProjectSetup.Resolution.hd)
                    Text("Full HD · 1080").tag(ProjectSetup.Resolution.fullHD)
                    Text("4K · 2160").tag(ProjectSetup.Resolution.ultraHD)
                }
                Picker("Frame rate", selection: $setup.rate) {
                    ForEach(ProjectSetup.Rate.allCases, id: \.self) { rate in
                        Text(rate.rawValue + " fps").tag(rate)
                    }
                }
                TextField("Content language", text: $setup.contentLanguage)
                    .help("Language tag for captions and narration, such as vi, en or en-US.")
                if !brands.isEmpty {
                    Picker("Brand kit", selection: $brand) {
                        Text("None").tag(String?.none)
                        ForEach(brands, id: \.reference) { LibraryView.title($0).tag(String?.some($0.reference)) }
                    }
                    .help("Palette, fonts, logo, mascot and voice the new project starts with; change it later in the Brand panel.")
                }
                folderRow("Save in", url: parent) { parent = chooseFolder() ?? parent }
                folderRow("Footage folder (optional)", url: footage) { footage = chooseFolder() ?? footage }
                if footage != nil {
                    Button("Clear footage selection") { footage = nil }
                }
            }.formStyle(.columns)
            Text("Original footage is referenced without copying or modifying it. Import clips after creating the project.")
                .font(.caption).foregroundStyle(.secondary)
            if let parent, !setup.folderName.isEmpty {
                Text(parent.appendingPathComponent(setup.folderName).path)
                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Text(setup.canvasFromFirstClip
                    ? String(format: String(localized: "Auto · %dp short side"), setup.resolution.rawValue)
                    : "\(setup.dimensions.width) × \(setup.dimensions.height)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                if document.creatingProject { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create project", action: create).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).disabled(!valid)
            }
        }.padding(24).frame(width: 540)
            .disabled(document.creatingProject)
            .interactiveDismissDisabled(document.creatingProject)
            .onAppear {
                nameFocused = true
                parent = parent ?? document.settings.defaultProjectsFolder
            }
            .task { brands = ((try? document.libraryCatalog.panelItems([.brand])) ?? []).filter { $0.scope != .project } }
    }

    private func folderRow(_ title: LocalizedStringKey, url: URL?, action: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                if let url {
                    Text(Self.displayPath(url)).lineLimit(1).truncationMode(.middle).help(url.path)
                } else {
                    Text("Not selected").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose…", action: action)
                    .accessibilityLabel(title)
            }.accessibilityElement(children: .contain)
        }.accessibilityElement(children: .contain)
    }

    /// "~/Movies/BashCut" rather than only "BashCut", so the default folder is recognizable.
    static func displayPath(_ url: URL) -> String {
        (url.resolvingSymlinksInPath().path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = parent
        return ModalCenter.shared.open(panel, name: "choose-folder")?.first
    }

    private func create() {
        guard let parent, !document.saving, !document.busy,
            document.confirmDiscard(removeRecovery: false)
        else { return }
        document.creatingProject = true
        document.busy = true
        error = ""
        Task {
            defer {
                document.creatingProject = false
                document.busy = false
            }
            do {
                _ = try await document.createProject(setup, in: parent, footage: footage)
                if let brand, let item = brands.first(where: { $0.reference == brand }) {
                    try document.applyBrand(item)
                }
                document.settings.rememberProjectsFolder(parent)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
