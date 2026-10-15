import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import SwiftUI

/// Inspector › Speed: presets, a slider and a field for constant speed, whether the clip's length follows the
/// speed (CapCut-style, the default) and pitch preservation. Every change is `setClipSpeed`, like `clip.speed`.
struct SpeedControls: View {
    @Bindable var document: ProjectDocument
    let item: Item
    @AppStorage("speedChangesLength") private var changesLength = true
    @State private var dragging: Double?
    @State private var typed = ""

    private var speed: Double { dragging ?? item.speed }

    var body: some View {
        if item.mediaID == nil {
            Text("Speed applies to video and audio clips.").foregroundStyle(.secondary)
        } else if item.fields["freezeFrame"] != nil {
            Text("A freeze frame has no speed. Remove the freeze to change it.").foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.speedCurve == nil || dragging != nil ? UIAction.speedLabel(speed) : String(localized: "Curve"))
                        .font(.title2.monospacedDigit().bold())
                    Spacer()
                    Text(lengthText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(UIAction.speedPresets, id: \.self) { preset in
                        Button(UIAction.speedLabel(preset)) { apply(preset) }
                            .buttonStyle(.bordered).controlSize(.small)
                            .tint(item.speedCurve == nil && abs(item.speed - preset) < 0.001 ? .cyan : nil)
                    }
                }
                Slider(
                    value: Binding(get: { log2(speed) }, set: { dragging = Self.rounded(pow(2, $0)) }),
                    in: log2(0.25)...log2(4)
                ) { editing in
                    // macOS can report the end of a drag twice; take the value once.
                    guard !editing, let value = dragging else { return }
                    dragging = nil
                    apply(value)
                }
                HStack {
                    TextField("Speed", text: $typed).textFieldStyle(.roundedBorder).frame(width: 70)
                        .onSubmit {
                            if let value = Double(typed.replacingOccurrences(of: "×", with: "")
                                .replacingOccurrences(of: ",", with: "."))
                            { apply(value) }
                        }
                    Text("0.1×–16×").font(.caption2).foregroundStyle(.secondary)
                }
                Toggle("Change clip length", isOn: $changesLength)
                Text(changesLength
                    ? "Faster clips get shorter and later clips on the layer move up."
                    : "The clip keeps its length and uses more or less of the source.")
                    .font(.caption2).foregroundStyle(.secondary)
                Toggle("Preserve audio pitch", isOn: Binding(
                    get: { item["preservePitch"] != .bool(false) },
                    set: { value in
                        do {
                            try document.setClipSpeed(item.speed, item: item.id, keepDuration: true, preservePitch: value)
                        } catch { document.message = error.localizedDescription }
                    }))
                if item.linkedItemID != nil {
                    Label("Linked sound changes too", systemImage: "link").font(.caption2).foregroundStyle(.secondary)
                }
                SpeedCurveControls(document: document, item: item)
            }
            .onAppear { typed = String(format: "%g", item.speed) }
            .onChange(of: item.speed) { typed = String(format: "%g", item.speed) }
        }
    }

    /// Current length, and the length `speed` would give while dragging.
    private var lengthText: String {
        let fps = document.project.fps
        let now = Timecode.duration(item.duration, fps: fps)
        guard let dragging else { return now }
        let next = document.duration(of: item, at: dragging, keepDuration: !changesLength)
        return now + " → " + Timecode.duration(next, fps: fps)
    }

    private func apply(_ value: Double) {
        // Compare with the project, not this view's copy of the item, which is stale right after an edit.
        let current = document.project.tracks.flatMap(\.items).first { $0.id == item.id }?.speed ?? item.speed
        guard abs(value - current) > 0.0001 else { return }
        do { try document.setClipSpeed(value, item: item.id, keepDuration: !changesLength) } catch {
            document.message = error.localizedDescription
        }
    }

    /// Slider values snap to 0.05× steps.
    static func rounded(_ value: Double) -> Double { (value * 20).rounded() / 20 }
}
