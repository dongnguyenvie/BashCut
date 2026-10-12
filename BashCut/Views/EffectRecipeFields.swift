import BashCutProject
import SwiftUI

/// An effect preset's recipe in the library item sheet: its steps and parameters as JSON, checked as it is typed
/// (`library update --params` saves the same object).
struct EffectRecipeFields: View {
    @Binding var text: String

    var body: some View {
        let problem: String? = {
            do {
                _ = try EffectRecipe.params(editorText: text)
                return nil
            } catch { return error.localizedDescription }
        }()
        VStack(alignment: .leading, spacing: 4) {
            Text("Recipe").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 11, design: .monospaced))
                .autocorrectionDisabled()
                .frame(minHeight: 140, maxHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(problem == nil ? Color.secondary.opacity(0.3) : .red))
            Text(verbatim: problem ?? "")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
                .opacity(problem == nil ? 0 : 1)
            Text("Steps: motion, keyframes, speed, speedCurve, reverse, freeze, patch, sfx, text; \"$name\" uses a parameter.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
