import BashCutProject
import BashCutAutomation
import SwiftUI

struct InspectorView: View {
    @Bindable var document: ProjectDocument
    /// Tab title ("Video"); the document stores it lowercased so agents can set it with `ui view --inspector`.
    private var tab: String { document.ui.inspectorTab.capitalized }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("INSPECTOR").font(.caption.bold())
                Spacer()
            }.padding(10)
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(["Video", "Audio", "Text", "Color", "Speed"], id: \.self) { name in
                        Button(LocalizedStringKey(name)) { document.ui.inspectorTab = name.lowercased() }
                            .buttonStyle(.borderless)
                            .foregroundStyle(tab == name ? .cyan : .secondary)
                    }
                }.font(.caption).padding(8)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if document.selectedItems.count > 1 {
                        MultiSelectionInspector(document: document)
                    } else if let item = document.selected {
                        Text(item.id).font(.caption.monospaced()).lineLimit(1).textSelection(.enabled)
                        Text(String(format: "%d–%d frames", item.at, item.end)).font(.caption).foregroundStyle(
                            .secondary)
                        if let linkedID = item.linkedItemID {
                            HStack {
                                Label("Linked A/V", systemImage: "link")
                                Spacer()
                                Text(linkedID).lineLimit(1).foregroundStyle(.secondary)
                            }
                            Button("Unlink audio", systemImage: "link.badge.minus") {
                                document.unlinkSelectedAudio()
                            }
                        }
                        if document.selectedItemTrack?.isAdjustment == true {
                            Text("An adjustment grades every layer below it. Set its look in the Color tab or Filters.")
                                .foregroundStyle(.secondary)
                            Divider()
                            if tab == "Color" { colorControls }
                        } else {
                            details(item)
                        }
                        Divider()
                        Button("Trim start to playhead") {
                            document.apply(
                                .trim(item: item.id, edge: .start, toFrame: document.playhead, ripple: true),
                                label: "Trim start")
                        }
                        Button("Trim end to playhead") {
                            document.apply(
                                .trim(item: item.id, edge: .end, toFrame: document.playhead, ripple: true),
                                label: "Trim end")
                        }
                        Button("Roll start to playhead") {
                            document.apply(
                                .roll(item: item.id, edge: .start, toFrame: document.playhead), label: "Roll cut")
                        }
                        Button("Roll end to playhead") {
                            document.apply(
                                .roll(item: item.id, edge: .end, toFrame: document.playhead), label: "Roll cut")
                        }
                        if item.mediaID != nil {
                            TextField(
                                "Source in (frames)",
                                value: Binding(
                                    get: { document.selected?.sourceIn ?? 0 },
                                    set: { document.apply(.slip(item: item.id, sourceIn: $0), label: "Slip clip") }
                                ), format: .number
                            ).textFieldStyle(.roundedBorder)
                            Button(
                                item.fields["freezeFrame"] == nil ? "Freeze at playhead" : "Remove freeze frame",
                                systemImage: item.fields["freezeFrame"] == nil ? "snowflake" : "play.fill"
                            ) {
                                document.toggleFreezeSelected()
                            }
                        }
                    } else {
                        Text("Select a timeline item").foregroundStyle(.secondary)
                    }
                    PluginActionStrip(document: document, placement: "inspector." + document.ui.inspectorTab)
                }.font(.caption).padding(10)
            }
        }.background(Color.white.opacity(0.025))
    }

    /// Tags and the current tab's controls for a clip or caption.
    @ViewBuilder private func details(_ item: Item) -> some View {
        Picker(
            "Role",
            selection: Binding(
                get: { document.selected?["tag"]?.object["role"]?.string ?? "broll" },
                set: {
                    patchNested("tag", "role", .string($0))
                })
        ) {
            Text("Speech").tag("speech")
            Text("B-roll").tag("broll")
            Text("Under VO").tag("underVO")
        }
        TextField(
            "Section",
            text: Binding(
                get: { document.selected?["tag"]?.object["section"]?.string ?? "" },
                set: {
                    patchNested("tag", "section", .string($0), coalescing: true)
                })
        ).textFieldStyle(.roundedBorder)
        Divider()
        switch tab {
        case "Video":
            HStack {
                Button("Change framing") {
                    let preset = ReframePreset.next(after: item)
                    document.patchSelected(preset.patch, label: "Change framing")
                }
                Spacer()
                Text(
                    LocalizedStringKey(
                        ReframePreset.current(for: item)?.title ?? "Custom"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Fill frame", isOn: Binding(
                get: { document.project.fills(item) },
                set: { document.patchSelected(["fill": .bool($0)], label: "Fill frame") }))
                .help("Fill crops the clip to cover the frame; off shows it whole with bars")
            number("Zoom", group: "transform", key: "zoom", defaultValue: 1, range: 0.25...3)
            number("Pan", group: "transform", key: "pan", defaultValue: 0, range: -600...600)
            number("Tilt", group: "transform", key: "tilt", defaultValue: 0, range: -600...600)
            number("Rotation", group: "transform", key: "rotation", defaultValue: 0, range: -180...180)
            number("Opacity", key: "opacity", defaultValue: 1, range: 0...1)
            Divider()
            MotionControls(document: document, item: item, forText: false)
        case "Audio":
            audioControls(item)
        case "Text":
            textControls(item)
        case "Color":
            colorControls
        default:
            SpeedControls(document: document, item: item)
        }
    }

    @ViewBuilder private func audioControls(_ item: Item) -> some View {
        number("Volume (dB)", key: "volumeDb", defaultValue: 0, range: -60...12)
        PlayheadKeyframeButton(
            document: document, item: item, title: "Keyframe volume at playhead",
            help: "Keys the volume here; then change it at another frame to fade between keys"
        ) {
            do { try document.setKeyframe("volume", value: nil) } catch { document.message = error.localizedDescription }
        }
        Toggle(
            "Mute",
            isOn: Binding(
                get: { document.selected?["muted"] == .bool(true) },
                set: {
                    document.patchSelected(["muted": .bool($0)], label: "Mute")
                }))
        number(
            "Fade in (frames)", key: "fadeIn", defaultValue: 0,
            range: 0...Double(item.duration / 2), integer: true)
        number(
            "Fade out (frames)", key: "fadeOut", defaultValue: 0,
            range: 0...Double(item.duration / 2), integer: true)
        if document.selectedItemTrack?.role == "music" {
            Divider()
            Toggle(
                "Duck under speech",
                isOn: Binding(
                    get: {
                        let track = document.selectedItemTrack
                        return track?["duckingEnabled"] != .bool(false)
                            && track?["duckUnderSpeechDb"]?.double != nil
                    },
                    set: {
                        document.patchSelectedTrack(
                            [
                                "duckingEnabled": .bool($0),
                                "duckUnderSpeechDb": document.selectedItemTrack?[
                                    "duckUnderSpeechDb"] ?? .integer(-14),
                            ], label: "Music ducking")
                    }))
            if document.selectedItemTrack?["duckingEnabled"] != .bool(false),
                document.selectedItemTrack?["duckUnderSpeechDb"]?.double != nil
            {
                trackNumber(
                    "Duck level (dB)", key: "duckUnderSpeechDb",
                    defaultValue: -14, range: -60...0)
                trackNumber(
                    "Attack (frames)", key: "duckAttackFrames",
                    defaultValue: 3, range: 0...120, integer: true)
                trackNumber(
                    "Release (frames)", key: "duckReleaseFrames",
                    defaultValue: 8, range: 0...240, integer: true)
            }
        }
    }

    @ViewBuilder private func textControls(_ item: Item) -> some View {
        if item["text"] != nil {
            TextEditor(
                text: Binding(
                    get: { document.selected?.text ?? "" },
                    set: {
                        document.patchSelected(
                            ["text": .string($0)], label: "Edit caption", coalescing: true)
                    })
            ).frame(height: 100)
            Picker(
                "Style",
                selection: Binding(
                    get: { document.selected?.textPreset ?? "bold-outline" },
                    set: {
                        document.patchSelected(["textPreset": .string($0)], label: "Caption style")
                    })
            ) {
                Text("Bold Outline").tag("bold-outline")
                Text("Cinematic Serif").tag("cinematic-serif")
                Text("Keyword Sticker").tag("keyword-sticker")
                Text("Place Card").tag("place-card")
                Text("Hook Title").tag("hook-title")
                Text("Chapter Card").tag("chapter-card")
            }
            number(
                "Font size", group: "textStyle", key: "size", defaultValue: 0.055,
                range: 0.02...0.15)
            number(
                "Vertical position", group: "textStyle", key: "positionY", defaultValue: 0.18,
                range: 0.05...0.9)
            Picker(
                "Word by word",
                selection: Binding(
                    get: { document.selected?.wordStyle ?? "none" },
                    set: { value in
                        guard let id = document.selectedID else { return }
                        do { try document.setWordStyle(value == "none" ? nil : value, items: [id]) } catch {
                            document.message = error.localizedDescription
                        }
                    })
            ) {
                Text("Off").tag("none")
                Text("Highlight word").tag("highlight")
                Text("Karaoke").tag("karaoke")
                Text("Reveal word by word").tag("reveal")
            }
            if let style = item.wordStyle {
                Button("Use on all captions") {
                    do { try document.setWordStyle(style) } catch { document.message = error.localizedDescription }
                }
                Text(item["words"] == nil ? "Timing estimated from word length" : "Timing from speech")
                    .foregroundStyle(.secondary)
            }
            Divider()
            MotionControls(document: document, item: item, forText: true)
        } else {
            Text("Select a caption to edit text.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var colorControls: some View {
        number("Exposure", group: "color", key: "exposure", defaultValue: 0, range: -2...2)
        number("Contrast", group: "color", key: "contrast", defaultValue: 1, range: 0.5...1.5)
        number("Saturation", group: "color", key: "saturation", defaultValue: 1, range: 0...2)
    }

    private func number(
        _ title: String, group: String? = nil, key: String, defaultValue: Double,
        range: ClosedRange<Double>, integer: Bool = false
    ) -> some View {
        // Transform, opacity and volume are animatable: once the item has keys for one, the control reads and sets
        // the key at the playhead.
        let animatable = group == "transform" || (group == nil && key == "opacity") ? key
            : group == nil && key == "volumeDb" ? "volume" : nil
        func isAnimated() -> Bool { animatable.flatMap { document.selected?.motion?.keys[$0] } != nil }
        let binding = Binding<Double>(
            get: {
                if let animatable, isAnimated(), let item = document.selected {
                    return document.motionValue(animatable, item: item)
                }
                let value = group.map { document.selected?[$0]?.object[key] } ?? document.selected?[key]
                return value?.double ?? defaultValue
            },
            set: {
                guard $0.isFinite else { return }
                let bounded = min(range.upperBound, max(range.lowerBound, $0))
                if let animatable, isAnimated() {
                    do { try document.setKeyframe(animatable, value: bounded, coalesce: true) } catch {
                        document.message = error.localizedDescription
                    }
                    return
                }
                let value: JSONValue = integer ? .integer(Int(bounded.rounded())) : .number(bounded)
                if let group {
                    patchNested(group, key, value, coalescing: true)
                } else {
                    document.patchSelected([key: value], label: title, coalescing: true)
                }
            })
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LocalizedStringKey(title))
                if isAnimated() {
                    Image(systemName: "diamond.fill").font(.system(size: 7)).foregroundStyle(.cyan)
                        .help("Animated: changes set a keyframe at the playhead")
                }
                Spacer()
                TextField(
                    LocalizedStringKey(title), value: binding,
                    format: .number.precision(.fractionLength(0...2))
                ).frame(width: 60).textFieldStyle(.roundedBorder)
            }
            Slider(value: binding, in: range)
        }
    }
    private func patchNested(_ group: String, _ key: String, _ value: JSONValue, coalescing: Bool = false) {
        var fields = document.selected?[group]?.object ?? [:]
        fields[key] = value
        var patch: [String: JSONValue] = [group: .object(fields)]
        if group == "transform" { patch["reframePreset"] = .string("custom") }
        document.patchSelected(patch, label: "Change " + key, coalescing: coalescing)
    }
    private func trackNumber(
        _ title: String, key: String, defaultValue: Double,
        range: ClosedRange<Double>, integer: Bool = false
    ) -> some View {
        let binding = Binding<Double>(
            get: { document.selectedItemTrack?[key]?.double ?? defaultValue },
            set: {
                guard $0.isFinite else { return }
                let bounded = min(range.upperBound, max(range.lowerBound, $0))
                let value: JSONValue = integer ? .integer(Int(bounded.rounded())) : .number(bounded)
                document.patchSelectedTrack([key: value], label: title, coalescing: true)
            })
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LocalizedStringKey(title))
                Spacer()
                TextField(
                    LocalizedStringKey(title), value: binding,
                    format: .number.precision(.fractionLength(0...2))
                ).frame(width: 60).textFieldStyle(.roundedBorder)
            }
            Slider(value: binding, in: range)
        }
    }
}

/// Inspector › Speed: presets, a slider and a field for constant speed, whether the clip's length follows the
/// speed (CapCut-style, the default) and pitch preservation. Every change is `setClipSpeed`, like `clip.speed`.
private struct SpeedControls: View {
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

/// Several clips selected: their count and extent, a shared Mute switch and the bulk actions.
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
