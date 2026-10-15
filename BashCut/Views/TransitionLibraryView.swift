import BashCutDocument
import BashCutEngine
import BashCutProject
import SwiftUI

struct TransitionLibraryView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transitions").font(.headline)
            Text("Select a clip beside a cut, or text, a sticker or an overlay for its In, then choose a transition, or drag a tile onto an item.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(TransitionMotion.groups, id: \.name) { group in
                Text(LocalizedStringKey(group.name)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileMinimum))], spacing: 8) {
                    ForEach(group.kinds, id: \.self) { kind in
                        // The same tile as the library's transition presets below (N4), with its moving preview.
                        PictureTile(
                            caption: Text(Self.title(kind)), help: Text(Self.title(kind)),
                            action: { document.setSelectedTransition(kind: kind) },
                            picture: { hovering in
                                TransitionPreviewPicture(
                                    motion: TransitionMotion.resolved(kind: kind, motion: nil),
                                    easing: TimelineTransition.defaultEasing, symbol: Self.symbol(kind), playing: hovering)
                            })
                        .onDrag { NSItemProvider(object: TimelineCanvas.transitionPasteboardPrefix + kind as NSString) }
                    }
                }
            }
            if let active = document.selectedTransition {
                Divider()
                LabeledContent("Active") { Text(Self.title(active.kind)) }
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
                TransitionPresetRow(document: document, item: item, summary: Self.summary(item))
            }
        }
        .task {
            // Once per launch, off the main thread: previews no built-in kind or preset of any scope shows go.
            let catalog = document.libraryCatalog
            await TransitionPreviewStore.shared.pruneOnce {
                let presets = (try? catalog.items(matching: LibraryCatalog.Filter(kinds: [.transitionPreset]))) ?? []
                return TransitionPreview.wantedKeys(presets: presets.compactMap { try? TransitionPreset(params: $0.params) })
            }
        }
    }

    /// "whip-right" reads "Whip right".
    static func title(_ kind: String) -> LocalizedStringKey {
        LocalizedStringKey(titleKey(kind))
    }

    static func titleKey(_ kind: String) -> String {
        let words = kind.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
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
        var parts = [String(localized: String.LocalizationValue(titleKey(preset.kind)))]
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

    /// The built-in tiles are as wide as the library's tiles at the panel's tile size.
    private var tileMinimum: Double {
        let layout = document.libraryLayout()
        return layout.isList ? LibraryPanelLayout.minimumRange.upperBound : layout.tileMinimum
    }

    /// The icon a transition's tile shows until its preview is rendered.
    static func symbol(_ kind: String) -> String { icons[kind] ?? "rectangle.split.2x1" }

    private static let icons: [String: String] = [
        "dissolve": "circle.lefthalf.filled",
        "whip": "arrow.left",
        "whip-right": "arrow.right",
        "whip-up": "arrow.up",
        "whip-down": "arrow.down",
        "blink": "sun.max.fill",
        "zoom": "plus.magnifyingglass",
        "crash-zoom": "arrow.up.left.and.arrow.down.right",
        "crash-out": "arrow.down.right.and.arrow.up.left",
        "spin": "arrow.counterclockwise",
        "roll": "arrow.counterclockwise",
        "roll-right": "arrow.clockwise",
        "shutter": "camera.aperture",
        "swing": "rotate.3d",
        "arc": "arrow.uturn.left",
        "arc-right": "arrow.uturn.right",
        "glitch": "waveform.path.ecg",
        "halftone": "circle.grid.3x3.fill",
        "wipe-up": "rectangle.split.1x2",
        "wipe-down": "rectangle.split.1x2.fill",
        "barn-door": "rectangle.split.3x1",
        "iris": "circle.circle",
        "diamond": "diamond",
        "infinite-zoom": "infinity",
        "infinite-out": "square.on.square",
        "screen-in": "rectangle.inset.filled",
        "screen-out": "rectangle.center.inset.filled",
        "blur": "drop.halffull",
        "seamless-zoom": "scope",
        "flash": "bolt.fill",
        "dip-black": "moon.fill",
        "double-exposure": "square.on.square.dashed",
        "flicker": "light.beacon.max",
        "color-shift": "paintpalette",
        "kaleidoscope": "snowflake",
        "slide": "rectangle.righthalf.inset.filled.arrow.right",
        "slide-up": "rectangle.bottomhalf.inset.filled",
    ]
}

/// A transition preset in the list layout: its preview (playing on hover), name and summary.
private struct TransitionPresetRow: View {
    let document: ProjectDocument
    let item: LibraryItem
    let summary: String
    @State private var hovering = false

    var body: some View {
        Button { document.applyFromLibrary(item) } label: {
            HStack(spacing: 6) {
                TransitionPreviewPicture(preset: item, playing: hovering)?
                    .frame(width: 48, height: 27).clipShape(RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 2) {
                    LibraryView.title(item)
                    Text(summary).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(document.selected == nil)
        .onHover { hovering = $0 }
    }
}

/// A transition preset's kind, duration, easing and sound (with its offset from the cut and volume) in the library
/// item sheet (#77); `library update --params`
/// sets the same fields.
struct TransitionPresetFields: View {
    @Bindable var document: ProjectDocument
    @Binding var preset: TransitionPreset

    @State private var sounds: [LibraryItem] = []

    var body: some View {
        Picker("Transition", selection: $preset.kind) {
            ForEach(kinds, id: \.self) { Text(TransitionLibraryView.title($0)).tag($0) }
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
        if preset.sfx != nil {
            Stepper(
                "Sound offset: \(preset.sfxOffset ?? 0) frames",
                value: Binding(get: { preset.sfxOffset ?? 0 }, set: { preset.sfxOffset = $0 == 0 ? nil : $0 }),
                in: TransitionPreset.sfxOffsetRange)
                .help("Negative starts the sound before the cut")
            LabeledContent("Sound volume") {
                Slider(
                    value: Binding(get: { preset.sfxVolumeDb ?? 0 }, set: { preset.sfxVolumeDb = $0 == 0 ? nil : $0.rounded() }),
                    in: TransitionPreset.sfxVolumeRange, step: 1)
                Text(verbatim: "\(Int((preset.sfxVolumeDb ?? 0).rounded())) dB").monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        }
    }

    private var kinds: [String] {
        TimelineTransition.renderedKinds.contains(preset.kind)
            ? TimelineTransition.renderedKinds : TimelineTransition.renderedKinds + [preset.kind]
    }
}
