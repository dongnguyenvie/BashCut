import BashCutDocument
import BashCutProject
import SwiftUI

/// The Effects panel's Apply with… sheet (#76): an effect recipe's parameters and, optionally, the part of the clip
/// it changes. `library apply --set … --from … --to …` does the same.
struct EffectApplySheet: View {
    @Bindable var document: ProjectDocument
    @Binding var request: EffectApplyRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apply \(LibraryView.title(request.item))").font(.headline)
            Form {
                if request.parameters.isEmpty {
                    Text("This effect has no settings.").foregroundStyle(.secondary)
                }
                ForEach(request.parameters, id: \.name) { parameter in
                    parameterRow(parameter)
                }
                Toggle("Only part of the clip", isOn: $request.useRange)
                if request.useRange {
                    frameRow("From frame", value: $request.from)
                    frameRow("To frame", value: $request.to)
                    Text("Frames \(request.clip.lowerBound)–\(request.clip.upperBound) are in the clip. The clip is split there.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Reset") {
                    request.values = Dictionary(uniqueKeysWithValues: request.parameters.map { ($0.name, $0.value) })
                }
                .disabled(request.overrides.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel) { document.ui.effectApply = nil }.keyboardShortcut(.cancelAction)
                Button("Apply") { document.commitEffectApply() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 380)
    }

    private func parameterRow(_ parameter: EffectRecipe.Parameter) -> some View {
        let value = Binding(
            get: { request.values[parameter.name] ?? parameter.value },
            set: { request.values[parameter.name] = Self.rounded($0, parameter) })
        let label = parameter.label.map { Text(LocalizedStringKey($0)) } ?? Text(verbatim: parameter.name)
        return HStack {
            Slider(value: value, in: parameter.minimum...parameter.maximum) { label }
            Text(verbatim: Self.format(value.wrappedValue)).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }

    private func frameRow(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
        HStack {
            TextField(title, value: value, format: .number)
            Button("Playhead") { value.wrappedValue = document.playhead }
                .help("Use the playhead's frame")
        }
    }

    /// Whole-number parameters (frames) stay whole; others keep two decimals.
    private static func rounded(_ value: Double, _ parameter: EffectRecipe.Parameter) -> Double {
        let whole = parameter.value.rounded() == parameter.value && parameter.minimum.rounded() == parameter.minimum
            && parameter.maximum.rounded() == parameter.maximum && parameter.maximum - parameter.minimum >= 4
        return whole ? value.rounded() : (value * 100).rounded() / 100
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}
