import BashCutProject
import SwiftUI

/// Inspector › Video/Text › Animation: presets, a keyframe for every property at the playhead, and which
/// properties are animated. Sliders of animated properties set keys at the playhead (see `InspectorView`).
struct MotionControls: View {
    @Bindable var document: ProjectDocument
    let item: Item
    let forText: Bool

    private var animated: [String] { item.motion?.keys.filter { !$0.value.isEmpty }.map(\.key).sorted() ?? [] }
    private var insideItem: Bool { (item.at..<item.end).contains(document.playhead) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Animation").font(.caption.bold())
                Spacer()
                Menu("Presets") {
                    ForEach(MotionPreset.all.filter { $0.forText == forText || $0.id == "zoom-punch" }) { preset in
                        Button(LocalizedStringKey(preset.title)) { run { try document.applyMotionPreset(preset.id) } }
                    }
                    if !animated.isEmpty {
                        Divider()
                        Button("Remove animation", role: .destructive) { run { try document.applyMotionPreset("none") } }
                    }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            HStack {
                Button("Keyframe at playhead", systemImage: "diamond") { run { try document.keyframeAll() } }
                    .disabled(!insideItem)
                    .help("Records zoom, pan, tilt, rotation and opacity here; then change a slider at another frame")
            }
            if !animated.isEmpty {
                Text(String(format: String(localized: "Animated: %@"), animated.joined(separator: ", ")))
                    .foregroundStyle(.cyan)
                Text("Sliders of animated properties set a keyframe at the playhead.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func run(_ body: () throws -> Int) {
        do { _ = try body() } catch { document.message = error.localizedDescription }
    }
}
