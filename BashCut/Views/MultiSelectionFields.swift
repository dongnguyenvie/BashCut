import BashCutAutomation
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
                Text("\(start)–\(end) frames").foregroundStyle(.secondary)
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
            HStack {
                Button("Send to Agent") { document.run(.sendToAgent) }
                QuickEditMenu(document: document)
            }
            Text("Drag any selected clip to move them all. Esc clears the selection.").foregroundStyle(.secondary)
        }
    }
}

/// Inspector with several items selected (#357 follow-up): the properties they share — opacity, volume, framing
/// (fill, zoom, pan, tilt, rotation), backdrop and speed — set on every selected item they apply to, as one undo
/// step (a slider drag coalesces). A value that differs between the items shows the first one's, marked Mixed.
/// Agents do the same with `timeline.apply` `patchItems` (`items: [...]`), `clip.backdrop --items` and
/// `clip.speed --items`.
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
        let pictures = targets.filter { $0.track.kind == TrackKind.video && $0.item.mediaID != nil }.map(\.item.id)
        if !pictures.isEmpty { BackdropControls(document: document, itemIDs: pictures) }
        let timed = targets.filter { $0.item.mediaID != nil && $0.item.fields["freezeFrame"] == nil }.map(\.item)
        if !timed.isEmpty { MultiSelectionSpeed(document: document, items: timed) }
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

/// Speed for several selected clips: the presets and a typed value, each applied to every clip as one undo step
/// with the single-clip rules (`setClipSpeeds`, like `clip.speed --items`); the Change clip length setting is shared
/// with the single-clip Inspector.
private struct MultiSelectionSpeed: View {
    let document: ProjectDocument
    let items: [Item]
    @AppStorage("speedChangesLength") private var changesLength = true
    @State private var typed = ""

    var body: some View {
        let speeds = items.map { $0.speedCurve == nil ? $0.speed : -1 }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Speed")
                if Set(speeds).count > 1 { Text("Mixed").foregroundStyle(.secondary) }
                Spacer()
                TextField("Speed", text: $typed).textFieldStyle(.roundedBorder).frame(width: 60)
                    .onSubmit {
                        if let value = Double(typed.replacingOccurrences(of: "×", with: "")
                            .replacingOccurrences(of: ",", with: "."))
                        { apply(value) }
                    }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(UIAction.speedPresets, id: \.self) { preset in
                    Button(UIAction.speedLabel(preset)) { apply(preset) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(speeds.allSatisfy { abs($0 - preset) < 0.001 } ? .cyan : nil)
                }
            }
            Toggle("Change clip length", isOn: $changesLength)
        }
        .onAppear { typed = Self.text(speeds) }
        .onChange(of: speeds) { typed = Self.text(speeds) }
    }

    /// The first clip's speed for the field, empty for a ramp.
    private static func text(_ speeds: [Double]) -> String {
        speeds.first.map { $0 < 0 ? "" : String(format: "%g", $0) } ?? ""
    }

    private func apply(_ value: Double) {
        do {
            try document.setClipSpeeds(value, items: items.map(\.id), keepDuration: !changesLength)
        } catch { document.message = error.localizedDescription }
    }
}
