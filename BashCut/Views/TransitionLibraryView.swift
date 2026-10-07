import BashCutProject
import SwiftUI

struct TransitionLibraryView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transitions").font(.headline)
            Text("Select a video clip beside a cut, then choose a transition.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                ForEach(TimelineTransition.renderedKinds, id: \.self) { kind in
                    Button {
                        document.setSelectedTransition(kind: kind)
                    } label: {
                        Label(title(kind), systemImage: icon(kind))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let active = document.selectedTransition {
                Divider()
                LabeledContent("Active") { Text(title(active.kind)) }
                Stepper(
                    "Duration: \(active.duration) frames",
                    onIncrement: { document.adjustSelectedTransitionDuration(by: 3) },
                    onDecrement: { document.adjustSelectedTransitionDuration(by: -3) })
                Picker("Easing", selection: Binding(
                    get: { active.easing }, set: { document.setSelectedTransitionEasing($0) }
                )) {
                    ForEach(Self.easings(with: active.easing), id: \.self) { Text(Self.easingTitle($0)).tag($0) }
                }
                Button("Remove transition", role: .destructive) {
                    document.removeSelectedTransition()
                }
            }
            Divider()
            LibraryItemsSection(document: document, kinds: [.transitionPreset], saveKinds: [.transitionPreset]) { item in
                Button { document.applyFromLibrary(item) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        LibraryView.title(item)
                        Text(Self.summary(item)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(document.selected == nil)
            }
        }
    }

    private func title(_ kind: String) -> LocalizedStringKey {
        LocalizedStringKey(kind.capitalized)
    }

    static func easingTitle(_ easing: String) -> LocalizedStringKey {
        switch easing {
        case "in": "Ease in"
        case "out": "Ease out"
        case "inOut": "Ease in and out"
        case TimelineTransition.defaultEasing: "Linear"
        default: "\(easing)"
        }
    }

    /// The named easings, plus `current` when it is a curve of its own (a cubic-bezier set by an agent or a preset).
    static func easings(with current: String?) -> [String] {
        guard let current, !TimelineTransition.easings.contains(current) else { return TimelineTransition.easings }
        return TimelineTransition.easings + [current]
    }

    /// Kind, length, easing and whether the preset has a sound, under its name.
    private static func summary(_ item: LibraryItem) -> String {
        guard let preset = try? TransitionPreset(params: item.params) else { return "" }
        var parts = [String(localized: String.LocalizationValue(preset.kind.capitalized))]
        if let duration = preset.duration { parts.append(String(localized: "\(duration) frames")) }
        if let easing = preset.easing, easing != TimelineTransition.defaultEasing {
            parts.append(String(localized: easingValue(easing)))
        }
        if preset.sfx != nil || item.file != nil { parts.append(String(localized: "Sound")) }
        return parts.joined(separator: " · ")
    }

    private static func easingValue(_ easing: String) -> String.LocalizationValue {
        switch easing {
        case "in": "Ease in"
        case "out": "Ease out"
        case "inOut": "Ease in and out"
        default: "Linear"
        }
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "dissolve": "circle.lefthalf.filled"
        case "whip": "arrow.right"
        case "blink": "sun.max.fill"
        case "zoom": "plus.magnifyingglass"
        case "spin": "arrow.clockwise"
        case "shutter": "camera.aperture"
        default: "rectangle.split.2x1"
        }
    }
}

/// A transition preset's kind, duration, easing and sound in the library item sheet (#77); `library update --params`
/// sets the same fields.
struct TransitionPresetFields: View {
    @Bindable var document: ProjectDocument
    @Binding var preset: TransitionPreset

    @State private var sounds: [LibraryItem] = []

    var body: some View {
        Picker("Transition", selection: $preset.kind) {
            ForEach(kinds, id: \.self) { Text(LocalizedStringKey($0.capitalized)).tag($0) }
        }
        Stepper(
            "Duration: \(preset.duration ?? 15) frames",
            value: Binding(get: { preset.duration ?? 15 }, set: { preset.duration = $0 }),
            in: 1...TransitionPreset.maximumDuration)
        Picker("Easing", selection: Binding(
            get: { preset.easing ?? TimelineTransition.defaultEasing }, set: { preset.easing = $0 }
        )) {
            ForEach(TransitionLibraryView.easings(with: preset.easing), id: \.self) {
                Text(TransitionLibraryView.easingTitle($0)).tag($0)
            }
        }
        Picker("Sound", selection: Binding(get: { preset.sfx ?? "" }, set: { preset.sfx = $0.isEmpty ? nil : $0 })) {
            Text("None").tag("")
            if preset.sfx == ProjectDocument.ownTransitionSound {
                Text("Its own sound").tag(ProjectDocument.ownTransitionSound)
            }
            ForEach(sounds, id: \.reference) { LibraryView.title($0).tag($0.reference) }
            if let sfx = preset.sfx, sfx != ProjectDocument.ownTransitionSound, !sounds.contains(where: { $0.reference == sfx }) {
                Text(verbatim: sfx).tag(sfx)
            }
        }
        .task { sounds = (try? document.libraryCatalog.panelItems([.audio])) ?? [] }
    }

    private var kinds: [String] {
        TimelineTransition.renderedKinds.contains(preset.kind)
            ? TimelineTransition.renderedKinds : TimelineTransition.renderedKinds + [preset.kind]
    }
}
