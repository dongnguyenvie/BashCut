import BashCutProject
import SwiftUI

struct SectionManagerView: View {
    @Bindable var document: ProjectDocument
    @Binding var newLabel: String
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sections").font(.headline)
                Spacer()
                Button("Done", action: done)
            }
            HStack {
                TextField("Section name", text: $newLabel)
                    .onSubmit(addSection)
                Button("Add at playhead", action: addSection)
                    .disabled(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if document.project.sectionMarkers.isEmpty {
                Text("No sections yet.").foregroundStyle(.secondary)
            } else {
                List(document.project.sectionMarkers) { marker in
                    SectionRow(document: document, marker: marker)
                }
                .frame(height: min(280, Double(document.project.sectionMarkers.count) * 42 + 12))
            }
            Text("Drag a section boundary in the timeline band to move it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 440)
    }

    private func addSection() {
        let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        let revision = document.project.revision
        document.apply(
            .upsertSection(id: UUID().uuidString, label: label, atFrame: document.playhead),
            label: "Add section")
        if document.project.revision != revision { newLabel = "" }
    }
}

private struct SectionRow: View {
    @Bindable var document: ProjectDocument
    let marker: TimelineMarker
    @State private var label: String

    init(document: ProjectDocument, marker: TimelineMarker) {
        self.document = document
        self.marker = marker
        _label = State(initialValue: marker.label)
    }

    var body: some View {
        HStack {
            TextField("Section name", text: $label)
                .onSubmit(save)
            Text(format(marker.at)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button(role: .destructive) {
                document.apply(.deleteSection(id: marker.id), label: "Delete section")
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private func save() {
        guard label != marker.label else { return }
        document.apply(
            .upsertSection(id: marker.id, label: label, atFrame: marker.at),
            label: "Rename section")
    }

    private func format(_ frame: Int) -> String {
        String(format: "%.2fs", Double(frame) / document.project.fps.value)
    }
}
