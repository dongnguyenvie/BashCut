import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import SwiftUI

/// The Inspector with nothing selected (P1-7): the project's settings. Each row opens the editor the toolbar and the
/// timeline already have: the format and platform menus, and the sections popover.
struct ProjectInspectorView: View {
    @Bindable var document: ProjectDocument
    /// The toolbar's format menu and its platform menu, drawn here too.
    let formatMenu: AnyView
    let platformMenu: AnyView
    @State private var showSections = false
    @State private var newSectionLabel = ""

    var body: some View {
        let project = document.project
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.headline).lineLimit(2)
                Text("Select a timeline item to edit it").foregroundStyle(.secondary)
            }
            Divider()
            row("Format") { formatMenu }
            row("Frame rate") { Text(String(format: "%.2f fps", project.fps.value)).monospacedDigit() }
            row("Clips") { clipsMenu }
            row("Length") {
                let length = Timecode.string(project.duration, fps: project.fps)
                Text(length + " · " + Timecode.duration(project.duration, fps: project.fps)).monospacedDigit()
            }
            row("Sections") { sectionsButton }
            row("Outputs") { platformMenu }
            Text(outputs).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    /// Fill or fit: how clips sit in the frame, the project's background behaviour.
    private var clipsMenu: some View {
        Menu {
            ForEach([true, false], id: \.self) { fill in
                Button {
                    do { try document.setClipFill(fill) } catch { document.message = error.localizedDescription }
                } label: {
                    let title: LocalizedStringKey = fill ? "Clips fill the frame" : "Clips fit inside the frame"
                    if document.project.clipsFill == fill { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            Text(document.project.clipsFill ? "Fill the frame" : "Fit inside")
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private var sectionsButton: some View {
        let markers = document.project.sectionMarkers
        return Button {
            showSections = true
        } label: {
            Text(markers.isEmpty ? String(localized: "None") : String(format: String(localized: "%d sections"), markers.count))
        }
        .buttonStyle(.link)
        .popover(isPresented: $showSections) {
            SectionManagerView(document: document, newLabel: $newSectionLabel, done: { showSections = false })
        }
    }

    private var outputs: String {
        let titles = document.outputPresets.map { String(localized: String.LocalizationValue($0.title)) }
        return titles.isEmpty ? String(localized: "No platform chosen") : titles.joined(separator: ", ")
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder _ value: () -> some View) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            value()
        }
    }
}
