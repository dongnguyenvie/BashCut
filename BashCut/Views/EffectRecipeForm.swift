import BashCutProject
import SwiftUI

/// The recipe editor's form: a row per step (its op and its fields as text), steps added, removed and moved, written
/// back to the same JSON text the JSON editor shows (`EffectRecipe.formSteps` / `params(_:steps:)`). Parameters and
/// nested values (keys, patch, textStyle) are edited as compact JSON in their field.
struct EffectRecipeForm: View {
    @Binding var text: String

    private var params: [String: JSONValue]? {
        guard case .object(let params)? = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else { return nil }
        return params
    }

    var body: some View {
        if let params {
            let steps = EffectRecipe.formSteps(params)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        row(step, index: index, steps: steps, params: params)
                    }
                    Menu("Add step") {
                        ForEach(EffectRecipe.stepKinds, id: \.self) { op in
                            Button(op) { write(params, steps + [EffectRecipe.FormStep.template(op)]) }
                        }
                    }
                    .fixedSize()
                }
            }
            .frame(minHeight: 140, maxHeight: 260)
        } else {
            Text("Fix the JSON first: the form needs a JSON object.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(
        _ step: EffectRecipe.FormStep, index: Int, steps: [EffectRecipe.FormStep], params: [String: JSONValue]
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(verbatim: "\(index + 1).").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Picker("Step", selection: Binding(
                    get: { step.op },
                    set: { op in
                        var next = steps
                        next[index] = EffectRecipe.FormStep.template(op)
                        write(params, next)
                    })
                ) {
                    ForEach(EffectRecipe.stepKinds, id: \.self) { Text(verbatim: $0).tag($0) }
                    if !EffectRecipe.stepKinds.contains(step.op) { Text(verbatim: step.op).tag(step.op) }
                }
                .labelsHidden().fixedSize()
                Spacer()
                Button { move(index, by: -1, steps: steps, params: params) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0).help("Move up")
                Button { move(index, by: 1, steps: steps, params: params) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == steps.count - 1).help("Move down")
                Button {
                    var next = steps
                    next.remove(at: index)
                    write(params, next)
                } label: { Image(systemName: "minus.circle") }.help("Remove step")
            }
            .buttonStyle(.borderless)
            ForEach(Array(step.fields.enumerated()), id: \.offset) { fieldIndex, field in
                HStack(spacing: 4) {
                    Text(verbatim: field.key).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    TextField(field.key, text: Binding(
                        get: { field.text },
                        set: { value in
                            var next = steps
                            next[index].fields[fieldIndex].text = value
                            write(params, next)
                        }))
                    .font(.system(size: 11, design: .monospaced)).textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }

    private func move(_ index: Int, by offset: Int, steps: [EffectRecipe.FormStep], params: [String: JSONValue]) {
        var next = steps
        next.swapAt(index, index + offset)
        write(params, next)
    }

    private func write(_ params: [String: JSONValue], _ steps: [EffectRecipe.FormStep]) {
        text = EffectRecipe.editorText(EffectRecipe.params(params, steps: steps))
    }
}
