import BashCutEngine
import BashCutProject
import SwiftUI

/// A text preset card in the Text panel: the sample text in the preset's look, sized, raised and outlined as the item
/// stores it (#380), with a mark when it animates.
struct TextPresetTile: View {
    let item: LibraryItem

    private static let height: CGFloat = 64

    var body: some View {
        let style = (try? LibraryTextPreset(params: item.params)) ?? LibraryTextPreset(textPreset: "bold-outline")
        let preset = style.textPreset
        let size = TextPresetFields.value("size", style)
        let raise = TextPresetFields.value("positionY", style)
        let outline = TextPresetFields.value("strokeWidth", style)
        let points = min(28, max(9, 15 * size / (TextPresetStyle.defaults(preset)["size"] ?? 0.055)))
        Text(verbatim: style.text ?? item.name)
            .font(
                style.textStyle["font"]?.string.map { Font.custom($0, size: points) }
                    ?? .system(
                        size: points, weight: preset == "cinematic-serif" ? .regular : .bold,
                        design: preset == "cinematic-serif" || preset == "chapter-card" ? .serif : .default))
            .foregroundStyle(style.textStyle["fill"]?.string.map(Color.init(hex:))
                ?? (preset == "keyword-sticker" ? .black : .white))
            .shadow(color: .black.opacity(outline > 0 ? 1 : 0), radius: min(2, outline / 3))
            .lineLimit(1).minimumScaleFactor(0.5)
            .padding(.horizontal, 6)
            .padding(.bottom, min(Self.height - 22, Self.height * raise))
            .frame(
                maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height,
                alignment: preset == "place-card" ? .bottomLeading : .bottom)
            .background(.black.opacity(0.3))
            .overlay(alignment: .bottomTrailing) {
                if style.animation != nil || style.animationKeys != nil {
                    let animation = style.animation ?? "Custom"
                    Image(systemName: "play.square").font(.system(size: 9)).foregroundStyle(.secondary).padding(4)
                        .help(LocalizedStringKey(MotionPreset.all.first { $0.id == animation }?.title ?? animation))
                }
            }
    }
}

/// A text preset's size, position, outline, font, colours (#414) and animation in the item sheet (#380). A field the item does not store
/// shows the preset's own value; Use preset style clears them all.
struct TextPresetFields: View {
    @Binding var style: LibraryTextPreset

    var body: some View {
        slider("Font size", key: "size", in: 0.02...0.15, format: { String(format: "%.1f%%", $0 * 100) })
            .help("Font size as a share of the frame's short side")
        slider("Vertical position", key: "positionY", in: 0.05...0.9, format: { "\(Int(($0 * 100).rounded()))%" })
            .help("Baseline height from the bottom of the frame")
        slider("Outline", key: "strokeWidth", in: 0...12, format: { "\(Int($0.rounded())) pt" })
        TextFontFields(preset: style.textPreset, style: $style.textStyle)
        Picker("Animation", selection: Binding(
            get: { style.animation ?? (style.animationKeys == nil ? "none" : "custom") },
            set: { value in
                guard value != "custom" else { return }
                style.animation = value == "none" ? nil : value
                style.animationKeys = nil
            })
        ) {
            Text("None").tag("none")
            if style.animationKeys != nil { Text("Custom").tag("custom") }
            ForEach(MotionPreset.all.filter { $0.forText || $0.id == style.animation }) { preset in
                Text(LocalizedStringKey(preset.title)).tag(preset.id)
            }
        }
        Button("Use preset style") { style.textStyle = [:] }
            .disabled(style.textStyle.isEmpty)
            .help("Clears the stored size, position, outline, font and colours")
    }

    /// The stored value of `key`, or the preset's own.
    static func value(_ key: String, _ style: LibraryTextPreset) -> Double {
        style.textStyle[key]?.double ?? TextPresetStyle.defaults(style.textPreset)[key] ?? 0
    }

    private func slider(
        _ title: LocalizedStringKey, key: String, in range: ClosedRange<Double>, format: @escaping (Double) -> String
    ) -> some View {
        let current = Self.value(key, style)
        return HStack {
            Slider(value: Binding(
                get: { min(range.upperBound, max(range.lowerBound, current)) },
                set: { style.textStyle[key] = .number(($0 * 1000).rounded() / 1000) }),
                in: range) { Text(title) }
            Text(verbatim: format(current))
                .font(.caption.monospacedDigit())
                .foregroundStyle(style.textStyle[key] == nil ? .secondary : .primary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
