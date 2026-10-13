import BashCutProject
import SwiftUI

/// An effect preset's recipe in the library item sheet: a form with a row per step, or its steps and parameters as
/// JSON, checked as it is typed (`library update --params` saves the same object).
struct EffectRecipeFields: View {
    @Binding var text: String

    /// What is wrong with `text` in the user's language, or nil when it is a valid recipe. The checker's own detail
    /// (which step and field) stays as written: it names JSON keys.
    static func problem(_ text: String) -> String? {
        do {
            _ = try EffectRecipe.params(editorText: text)
            return nil
        } catch EffectRecipe.EditorProblem.notJSON {
            return String(localized: "The recipe is not valid JSON")
        } catch EffectRecipe.EditorProblem.notObject {
            return String(localized: "The recipe must be a JSON object such as {\"steps\": […]}")
        } catch EffectRecipe.EditorProblem.invalidRecipe(let detail) {
            return String(format: String(localized: "Not a valid recipe: %@"), detail)
        } catch { return error.localizedDescription }
    }

    @AppStorage("recipeEditorForm") private var form = true

    var body: some View {
        let problem = Self.problem(text)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recipe").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Recipe editor", selection: $form) {
                    Text("Form").tag(true)
                    Text("JSON").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if form {
                EffectRecipeForm(text: $text)
            } else {
                TextEditor(text: $text)
                    .font(.system(size: 11, design: .monospaced))
                    .autocorrectionDisabled()
                    .frame(minHeight: 140, maxHeight: 220)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(problem == nil ? Color.secondary.opacity(0.3) : .red))
            }
            Text(verbatim: problem ?? "")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
                .opacity(problem == nil ? 0 : 1)
            Text("Steps: motion, keyframes, speed, speedCurve, reverse, freeze, patch, sfx, text; \"$name\" uses a parameter.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
