import BashCutAutomation
import BashCutProject
import SwiftUI

/// Inspector › Speed › Curve and Reverse: CapCut-style ramp presets with a preview of the curve, and playing the
/// clip backwards. Both are one undoable edit, like `clip speed-curve` and `clip reverse`.
struct SpeedCurveControls: View {
    @Bindable var document: ProjectDocument
    let item: Item
    @AppStorage("speedChangesLength") private var changesLength = true

    private var selection: String { document.speedCurvePreset(of: item) ?? "none" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Curve").font(.headline)
            Picker("Curve", selection: Binding(get: { selection }, set: { apply($0) })) {
                Text("None").tag("none")
                ForEach(SpeedCurve.presets, id: \.id) { preset in Text(LocalizedStringKey(preset.title)).tag(preset.id) }
                if selection == "custom" { Text("Custom").tag("custom") }
            }.labelsHidden()
            if let curve = item.speedCurve {
                CurveGraph(curve: curve).frame(height: 54)
                Text(String(format: String(localized: "Average %@"), UIAction.speedLabel(curve.average)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            let reversed = item.fields["reversed"] != nil
            Button {
                do { _ = try document.reverseClip(item.id) } catch { document.message = error.localizedDescription }
            } label: {
                Label(reversed ? "Play Forward" : "Reverse", systemImage: reversed ? "forward" : "backward")
            }
            .disabled(document.jobs.jobs.contains { $0.method == "clip.reverse" && $0.isActive })
            .help(reversed ? "Point the clip back at the original footage"
                : "Render a reversed copy of the footage this clip uses and play it backwards")
        }
    }

    private func apply(_ preset: String) {
        guard preset != selection, preset != "custom" else { return }
        do {
            try document.setClipSpeedCurve(
                preset == "none" ? nil : SpeedCurve.preset(preset), item: item.id, keepDuration: !changesLength)
        } catch { document.message = error.localizedDescription }
    }
}

/// The speed over the clip, 0.1×–16× on a log scale, with 1× marked.
private struct CurveGraph: View {
    let curve: SpeedCurve

    var body: some View {
        Canvas { context, size in
            func y(_ speed: Double) -> CGFloat {
                let range = log2(Project.speedRange.upperBound) - log2(Project.speedRange.lowerBound)
                return size.height * (1 - (log2(speed) - log2(Project.speedRange.lowerBound)) / range)
            }
            var normal = Path()
            normal.move(to: CGPoint(x: 0, y: y(1)))
            normal.addLine(to: CGPoint(x: size.width, y: y(1)))
            context.stroke(normal, with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            var line = Path()
            for (index, point) in curve.points.enumerated() {
                let location = CGPoint(x: point.t * size.width, y: y(point.speed))
                if index == 0 { line.move(to: location) } else { line.addLine(to: location) }
                context.fill(Path(ellipseIn: CGRect(x: location.x - 2.5, y: location.y - 2.5, width: 5, height: 5)),
                             with: .color(.cyan))
            }
            context.stroke(line, with: .color(.cyan), lineWidth: 1.5)
        }
        .background(.white.opacity(0.04)).cornerRadius(4)
    }
}
