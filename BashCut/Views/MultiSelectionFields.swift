import BashCutProject
import SwiftUI

/// Several clips selected: their count and extent, a shared Mute switch, the shared properties and the bulk actions.
struct MultiSelectionInspector: View {
    let document: ProjectDocument

    var body: some View {
        let items = document.selectedItems
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: String(localized: "%d clips selected"), items.count)).font(.callout.bold())
            if let start = items.map(\.at).min(), let end = items.map(\.end).max() {
                Text(String(format: "%d–%d frames", start, end)).foregroundStyle(.secondary)
            }
            if items.contains(where: { $0.mediaID != nil }) {
                Toggle(
                    "Mute",
                    isOn: Binding(
                        get: { SelectionEdits.allMuted(document.selectedIDs, in: document.project) },
                        set: { _ in document.run(.muteClips) }))
            }
            MultiSelectionFields(document: document)
            Divider()
            HStack {
                Button("Copy") { document.run(.copyClips) }
                Button("Cut") { document.run(.cutClips) }
            }
            HStack {
                Button("Delete") { document.run(.delete) }
                Button("Lift") { document.run(.lift) }
            }
            Button("Send to Agent") { document.run(.sendToAgent) }
            Text("Drag any selected clip to move them all. Esc clears the selection.").foregroundStyle(.secondary)
        }
    }
}

/// Inspector with several items selected (#357 follow-up): the properties they share — opacity, volume and framing
/// (fill, zoom, pan, tilt, rotation) — set on every selected item they apply to, as one undo step (a slider drag
/// coalesces). A value that differs between the items shows the first one's, marked Mixed. Agents do the same with
/// `timeline.apply` `patchItems` (`items: [...]`); `clip.backdrop --items` sets a backdrop on several.
struct MultiSelectionFields: View {
    let document: ProjectDocument

    private struct Target {
        let item: Item
        let track: Track
    }

    private var targets: [Target] {
        let wanted = Set(document.selectedIDs)
        return document.project.tracks.flatMap { track in
            track.items.filter { wanted.contains($0.id) }.map { Target(item: $0, track: track) }
        }
    }

    var body: some View {
        let targets = targets
        if targets.contains(where: { SelectionEdits.applies(key: "opacity", to: $0.item, on: $0.track) }) {
            number("Opacity", key: "opacity", fallback: 1, range: 0...1, targets: targets)
        }
        if targets.contains(where: { SelectionEdits.applies(key: "volumeDb", to: $0.item, on: $0.track) }) {
            number("Volume (dB)", key: "volumeDb", fallback: 0, range: -60...12, targets: targets)
        }
        if targets.contains(where: { SelectionEdits.applies(key: "transform", to: $0.item, on: $0.track) }) {
            let fills = targets.filter { SelectionEdits.applies(key: "fill", to: $0.item, on: $0.track) }
                .map { document.project.fills($0.item) }
            Toggle(Set(fills).count > 1 ? "Fill frame (mixed)" : "Fill frame", isOn: Binding(
                get: { fills.first ?? false },
                set: { document.patchSelection("fill", value: .bool($0), label: "Fill frame") }))
            number("Zoom", key: "zoom", group: "transform", fallback: 1, range: 0.25...3, targets: targets)
            number("Pan", key: "pan", group: "transform", fallback: 0, range: -600...600, targets: targets)
            number("Tilt", key: "tilt", group: "transform", fallback: 0, range: -600...600, targets: targets)
            number("Rotation", key: "rotation", group: "transform", fallback: 0, range: -180...180, targets: targets)
        }
    }

    private func number(
        _ title: LocalizedStringKey, key: String, group: String? = nil, fallback: Double, range: ClosedRange<Double>,
        targets: [Target]
    ) -> some View {
        let values = targets.filter { SelectionEdits.applies(key: group ?? key, to: $0.item, on: $0.track) }.map { target in
            (group.map { target.item[$0]?.object[key] } ?? target.item[key])?.double ?? fallback
        }
        let binding = Binding<Double>(
            get: { values.first ?? fallback },
            set: { value in
                guard value.isFinite else { return }
                let bounded = (min(range.upperBound, max(range.lowerBound, value)) * 1_000).rounded() / 1_000
                document.patchSelection(key, group: group, value: .number(bounded), label: "Change " + key, coalescing: true)
            })
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                if Set(values).count > 1 { Text("Mixed").foregroundStyle(.secondary) }
                Spacer()
                TextField(title, value: binding, format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 60).textFieldStyle(.roundedBorder)
            }
            Slider(value: binding, in: range)
        }
    }
}
