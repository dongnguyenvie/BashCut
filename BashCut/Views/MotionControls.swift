import BashCutProject
import SwiftUI

/// Inspector › Video/Text › Animation: presets, a keyframe for every property at the playhead, and which
/// properties are animated. Sliders of animated properties set keys at the playhead (see `InspectorView`).
struct MotionControls: View {
    @Bindable var document: ProjectDocument
    let item: Item
    let forText: Bool

    private var animated: [String] { item.motion?.keys.filter { !$0.value.isEmpty }.map(\.key).sorted() ?? [] }

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
                PlayheadKeyframeButton(
                    document: document, item: item, title: "Keyframe at playhead",
                    help: "Records zoom, pan, tilt, rotation and opacity here; then change a slider at another frame"
                ) { run { try document.keyframeAll() } }
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

/// A "keyframe at playhead" button, enabled while the playhead is inside the item. It is its own view so only it
/// redraws as the playhead moves during playback, not the whole Inspector.
struct PlayheadKeyframeButton: View {
    let document: ProjectDocument
    let item: Item
    let title: LocalizedStringKey
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: "diamond", action: action)
            .disabled(!(item.at..<item.end).contains(document.playhead))
            .help(help)
    }
}
