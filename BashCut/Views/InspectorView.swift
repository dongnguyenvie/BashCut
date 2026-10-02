import BashCutProject
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
                    if let item = document.selected {
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
            number("Zoom", group: "transform", key: "zoom", defaultValue: 1, range: 0.25...3)
            number("Pan", group: "transform", key: "pan", defaultValue: 0, range: -600...600)
            number("Tilt", group: "transform", key: "tilt", defaultValue: 0, range: -600...600)
            number("Opacity", key: "opacity", defaultValue: 1, range: 0...1)
        case "Audio":
            audioControls(item)
        case "Text":
            textControls(item)
        case "Color":
            colorControls
        default:
            number("Speed", key: "speed", defaultValue: 1, range: 0.25...4)
            Toggle(
                "Preserve audio pitch",
                isOn: Binding(
                    get: { document.selected?["preservePitch"] != .bool(false) },
                    set: { preservePitch($0, item: item) }))
            Text("Changing speed keeps timeline duration; source bounds must still fit.").font(
                .caption
            ).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func audioControls(_ item: Item) -> some View {
        number("Volume (dB)", key: "volumeDb", defaultValue: 0, range: -60...12)
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
        } else {
            Text("Select a caption to edit text.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var colorControls: some View {
        number("Exposure", group: "color", key: "exposure", defaultValue: 0, range: -2...2)
        number("Contrast", group: "color", key: "contrast", defaultValue: 1, range: 0.5...1.5)
        number("Saturation", group: "color", key: "saturation", defaultValue: 1, range: 0...2)
    }

    private func preservePitch(_ enabled: Bool, item: Item) {
        var operations: [EditOperation] = [
            .setProperties(item: item.id, patch: ["preservePitch": .bool(enabled)])
        ]
        if let linked = item.linkedItemID {
            operations.append(
                .setProperties(item: linked, patch: ["preservePitch": .bool(enabled)]))
        }
        document.apply(
            .group(label: "Preserve audio pitch", author: .user, ops: operations),
            label: "Preserve audio pitch")
    }
    private func number(
        _ title: String, group: String? = nil, key: String, defaultValue: Double,
        range: ClosedRange<Double>, integer: Bool = false
    ) -> some View {
        let binding = Binding<Double>(
            get: {
                let value = group.map { document.selected?[$0]?.object[key] } ?? document.selected?[key]
                return value?.double ?? defaultValue
            },
            set: {
                guard $0.isFinite else { return }
                let bounded = min(range.upperBound, max(range.lowerBound, $0))
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
