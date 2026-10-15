import BashCutDocument
import BashCutProject
import BashCutAutomation
import BashCutEngine
import SwiftUI

struct InspectorView: View {
    @Bindable var document: ProjectDocument
    /// The toolbar's format and platform menus, which the project view (nothing selected) shows too.
    let formatMenu: AnyView
    let platformMenu: AnyView
    private var kind: InspectorItemKind? {
        guard document.selectedItems.count <= 1, let item = document.selected else { return nil }
        let media = item.mediaID.flatMap { id in document.project.media.first { $0.id == id } }
        return InspectorItemKind(item: item, track: document.selectedItemTrack, media: media)
    }
    /// The tabs that apply to the selected item; all of them for a multi-selection.
    private var tabs: [String] { kind?.tabs ?? ["video", "audio", "text", "color", "speed"] }
    /// Tab title ("Video"); the document stores it lowercased so agents can set it with `ui view --inspector`. A tab
    /// that does not apply to the item falls back to its first one, without changing what was stored.
    private var tab: String { (tabs.contains(document.ui.inspectorTab) ? document.ui.inspectorTab : tabs[0]).capitalized }
    var body: some View {
        VStack(spacing: 0) {
            if document.selected != nil {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(tabs, id: \.self) { id in
                            Button(LocalizedStringKey(id.capitalized)) { document.ui.inspectorTab = id }
                                .buttonStyle(.borderless)
                                .foregroundStyle(tab == id.capitalized ? .cyan : .secondary)
                        }
                    }.font(.caption).padding(8)
                }
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if document.selectedItems.count > 1 {
                        MultiSelectionInspector(document: document)
                    } else if let item = document.selected {
                        if let kind {
                            InspectorHeader(
                                item: item, kind: kind, track: document.selectedItemTrack,
                                media: item.mediaID.flatMap { id in document.project.media.first { $0.id == id } },
                                project: document.project)
                        }
                        if item.linkedItemID != nil {
                            Label("Linked A/V", systemImage: "link")
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
                            PluginInspectorViews(document: document, item: item)
                        }
                        Divider()
                        trimButtons(item)
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
                        ProjectInspectorView(document: document, formatMenu: formatMenu, platformMenu: platformMenu)
                    }
                    let actionTab = document.selected == nil ? document.ui.inspectorTab : tab.lowercased()
                    PluginActionStrip(document: document, placement: "inspector." + actionTab)
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
            if item.mediaID != nil { BackdropControls(document: document, item: item) }
            number("Zoom", group: "transform", key: "zoom", defaultValue: 1, range: 0.25...3)
            number("Pan", group: "transform", key: "pan", defaultValue: 0, range: -600...600)
            number("Tilt", group: "transform", key: "tilt", defaultValue: 0, range: -600...600)
            number("Rotation", group: "transform", key: "rotation", defaultValue: 0, range: -180...180)
            number("Opacity", key: "opacity", defaultValue: 1, range: 0...1)
            if item.mediaID != nil { cropControls(item) }
            Divider()
            MotionControls(document: document, item: item, forText: false)
            Divider()
            ItemTransitionControls(document: document, item: item)
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
                trackNumber("Hold gaps under (frames)", key: "duckMinGapFrames", defaultValue: holdDefault, range: 0...900, integer: true)
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
            TextFontFields(
                preset: item.textPreset,
                style: Binding(
                    get: { document.selected?["textStyle"]?.object ?? [:] },
                    set: { document.patchSelected(["textStyle": .object($0)], label: "Text style", coalescing: true) }),
                language: document.contentLanguage,
                addFont: document.fileURL == nil ? nil : { document.importFont() })
            TextLineStyleControls(document: document, item: item)
            number(
                "Outline", group: "textStyle", key: "strokeWidth",
                defaultValue: TextPresetStyle.defaults(item.textPreset)["strokeWidth"] ?? 0, range: 0...12)
            Picker(
                "Word by word",
                selection: Binding(
                    get: { document.selected?.wordStyle ?? "none" },
                    set: { value in
                        guard let id = document.selectedID, value != "custom" else { return }
                        do { try document.setWordStyle(value == "none" ? nil : .string(value), items: [id]) } catch {
                            document.message = error.localizedDescription
                        }
                    })
            ) {
                Text("Off").tag("none")
                Text("Highlight word").tag("highlight")
                Text("Karaoke").tag("karaoke")
                Text("Reveal word by word").tag("reveal")
                if item.wordStyle == "custom" { Text("Custom").tag("custom") }
            }
            if let style = item["wordStyle"], item.wordStyle != nil {
                Button("Use on all captions") {
                    do { try document.setWordStyle(style) } catch { document.message = error.localizedDescription }
                }
                Text(item["words"] == nil ? "Timing estimated from word length" : "Timing from speech")
                    .foregroundStyle(.secondary)
            }
            Divider()
            MotionControls(document: document, item: item, forText: true)
            Divider()
            ItemTransitionControls(document: document, item: item)
        } else {
            Text("Select a caption to edit text.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var colorControls: some View {
        number("Exposure", group: "color", key: "exposure", defaultValue: 0, range: -2...2)
        number("Contrast", group: "color", key: "contrast", defaultValue: 1, range: 0.5...1.5)
        number("Saturation", group: "color", key: "saturation", defaultValue: 1, range: 0...2)
    }

    func number(
        _ title: String, group: String? = nil, key: String, defaultValue: Double,
        range: ClosedRange<Double>, integer: Bool = false
    ) -> some View {
        // Transform, opacity, volume and crop are animatable: once the item has keys for one, the control reads and
        // sets the key at the playhead.
        let animatable = group == "transform" || (group == nil && key == "opacity") ? key
            : group == nil && key == "volumeDb" ? "volume" : group == "crop" ? "crop." + key : nil
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

extension InspectorView {
    /// Trim and roll the selected item's edges to the playhead.
    @ViewBuilder func trimButtons(_ item: Item) -> some View {
        Button("Trim start to playhead") {
            document.apply(
                .trim(item: item.id, edge: .start, toFrame: document.playhead, ripple: true), label: "Trim start")
        }
        Button("Trim end to playhead") {
            document.apply(.trim(item: item.id, edge: .end, toFrame: document.playhead, ripple: true), label: "Trim end")
        }
        Button("Roll start to playhead") {
            document.apply(.roll(item: item.id, edge: .start, toFrame: document.playhead), label: "Roll cut")
        }
        Button("Roll end to playhead") {
            document.apply(.roll(item: item.id, edge: .end, toFrame: document.playhead), label: "Roll cut")
        }
    }
}

extension InspectorView {
    /// The hold of a Music layer that sets none: 2.5 s in frames (#630).
    fileprivate var holdDefault: Double { (MusicDucking.defaultMinGapSeconds * document.project.fps.value).rounded() }
}
