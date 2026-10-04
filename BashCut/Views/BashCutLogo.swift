import SwiftUI

/// The BashCut mark: a shell prompt above a timeline with a playhead, drawn as vectors so it is crisp at any size
/// and present in SwiftPM builds, which carry no asset catalog. It is the single source of the app icon:
/// `scripts/render-app-icon.sh` renders AppIcon.appiconset from this view. Coordinates are in a 512-point space.
struct BashCutLogo: View {
    /// Draws the icon's dark rounded tile behind the mark; without it the mark sits on the surrounding background.
    var tile = true
    /// Draws waveforms in the clips; small sizes read better without them.
    var waveforms = true

    private static let cyan = Color(red: 0.24, green: 0.80, blue: 1.00)
    private static let blue = Color(red: 0.16, green: 0.42, blue: 1.00)
    private static let violet = Color(red: 0.48, green: 0.26, blue: 0.94)
    /// Waveform bar heights per clip, as fractions of the clip height.
    private static let waveforms: [[CGFloat]] = [
        [0.15, 0.3, 0.5, 0.35, 0.6, 0.4, 0.25, 0.45, 0.2],
        [0.2, 0.45, 0.3, 0.65, 0.4, 0.55, 0.25, 0.5, 0.3, 0.15],
        [0.25, 0.5, 0.35, 0.6, 0.3, 0.45, 0.2, 0.4],
        [0.15, 0.4, 0.55, 0.3, 0.6, 0.35, 0.45, 0.2],
    ]
    private static let clips: [CGRect] = [
        CGRect(x: 48, y: 316, width: 84, height: 70),
        CGRect(x: 140, y: 316, width: 106, height: 70),
        CGRect(x: 266, y: 316, width: 96, height: 70),
        CGRect(x: 370, y: 316, width: 94, height: 70),
    ]

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 512
            context.translateBy(x: (size.width - 512 * scale) / 2, y: (size.height - 512 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            if tile { drawTile(in: &context) }
            drawPrompt(in: context)
            drawTimeline(in: context)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "BashCut"))
    }

    private func drawTile(in context: inout GraphicsContext) {
        let tile = Path(roundedRect: CGRect(x: 0, y: 0, width: 512, height: 512), cornerRadius: 114, style: .continuous)
        context.fill(tile, with: .linearGradient(
            Gradient(colors: [Color(red: 0.07, green: 0.10, blue: 0.17), Color(red: 0.02, green: 0.03, blue: 0.06)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: 512)))
        context.clip(to: tile)
    }

    private func drawPrompt(in context: GraphicsContext) {
        var glow = context
        glow.addFilter(.shadow(color: Self.cyan.opacity(0.55), radius: 18))
        let gradient = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Self.cyan, Self.blue]), startPoint: CGPoint(x: 160, y: 110), endPoint: CGPoint(x: 250, y: 260))
        var chevron = Path()
        chevron.move(to: CGPoint(x: 168, y: 112))
        chevron.addLine(to: CGPoint(x: 246, y: 182))
        chevron.addLine(to: CGPoint(x: 168, y: 252))
        glow.stroke(chevron, with: gradient, style: StrokeStyle(lineWidth: 44, lineCap: .round, lineJoin: .round))
        glow.fill(Path(roundedRect: CGRect(x: 268, y: 224, width: 92, height: 40), cornerRadius: 14), with: .linearGradient(
            Gradient(colors: [Self.cyan, Self.blend(Self.cyan, Self.blue, 0.45)]),
            startPoint: CGPoint(x: 268, y: 224), endPoint: CGPoint(x: 360, y: 264)))
    }

    private func drawTimeline(in context: GraphicsContext) {
        let track = Path(roundedRect: CGRect(x: 38, y: 304, width: 436, height: 94), cornerRadius: 22)
        context.fill(track, with: .color(.white.opacity(0.05)))
        context.stroke(track, with: .color(Self.blue.opacity(0.35)), lineWidth: 2)

        for (index, clip) in Self.clips.enumerated() {
            let mix = Double(index) / Double(Self.clips.count - 1)
            let color = Self.blend(Self.blue, Self.violet, mix)
            context.fill(Path(roundedRect: clip, cornerRadius: 9), with: .linearGradient(
                Gradient(colors: [color.opacity(0.95), color.opacity(0.6)]),
                startPoint: CGPoint(x: clip.midX, y: clip.minY), endPoint: CGPoint(x: clip.midX, y: clip.maxY)))
            context.stroke(Path(roundedRect: clip, cornerRadius: 9), with: .color(color), lineWidth: 2)
            guard waveforms else { continue }
            let bars = Self.waveforms[index]
            let step = (clip.width - 24) / CGFloat(bars.count - 1)
            for (bar, height) in bars.enumerated() {
                let barHeight = clip.height * height
                let rect = CGRect(x: clip.minX + 12 + CGFloat(bar) * step - 2, y: clip.midY - barHeight / 2,
                                  width: 4, height: barHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.white.opacity(0.35)))
            }
        }

        var glow = context
        glow.addFilter(.shadow(color: Self.cyan.opacity(0.8), radius: 10))
        glow.fill(Path(roundedRect: CGRect(x: 253, y: 290, width: 6, height: 118), cornerRadius: 3),
                  with: .color(Color(red: 0.75, green: 0.95, blue: 1.0)))
        var head = Path()
        head.move(to: CGPoint(x: 240, y: 280))
        head.addLine(to: CGPoint(x: 272, y: 280))
        head.addLine(to: CGPoint(x: 256, y: 300))
        head.closeSubpath()
        glow.fill(head, with: .color(Color(red: 0.75, green: 0.95, blue: 1.0)))
    }

    private static func blend(_ from: Color, _ to: Color, _ amount: Double) -> Color {
        let a = NSColor(from).usingColorSpace(.sRGB) ?? .systemBlue
        let b = NSColor(to).usingColorSpace(.sRGB) ?? .systemPurple
        return Color(red: a.redComponent + (b.redComponent - a.redComponent) * amount,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * amount,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * amount)
    }
}
