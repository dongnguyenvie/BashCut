import Foundation

/// The recipe editor's form (a row per step, beside the JSON): each step's `op` and its other fields as text, read
/// from and written back to the same params `library update --params` saves. Only `steps` changes; `parameters` and
/// other keys stay as they are, and an older `{patch}` preset becomes one patch step.
extension EffectRecipe {
    public struct FormField: Sendable, Equatable {
        public var key: String
        /// The value as typed: a string as it is, anything else as compact JSON.
        public var text: String

        public init(key: String, text: String) {
            self.key = key
            self.text = text
        }
    }

    public struct FormStep: Sendable, Equatable {
        public var op: String
        public var fields: [FormField]

        public init(op: String, fields: [FormField] = []) {
            self.op = op
            self.fields = fields
        }

        /// A new step of `op` with the fields it needs, ready to fill in.
        public static func template(_ op: String) -> FormStep {
            let keys: [String: [(String, String)]] = [
                "motion": [("preset", "")], "keyframes": [("keys", "{}")], "speed": [("speed", "2")],
                "speedCurve": [("preset", "")], "freeze": [("t", "0")], "patch": [("patch", "{}")],
                "sfx": [("sfx", ""), ("t", "0")], "text": [("text", ""), ("t", "0")],
            ]
            return FormStep(op: op, fields: (keys[op] ?? []).map { FormField(key: $0.0, text: $0.1) })
        }
    }

    /// The steps of `params` as form rows, fields in key order.
    public static func formSteps(_ params: [String: JSONValue]) -> [FormStep] {
        let steps: [[String: JSONValue]]
        if case .array(let list)? = params["steps"] {
            steps = list.map(\.object)
        } else if case .object(let patch)? = params["patch"], !patch.isEmpty {
            steps = [["op": .string("patch"), "patch": .object(patch)]]
        } else {
            steps = []
        }
        return steps.map { step in
            FormStep(
                op: step["op"]?.string ?? "",
                fields: step.filter { $0.key != "op" }.sorted { $0.key < $1.key }.map { FormField(key: $0.key, text: formText($0.value)) })
        }
    }

    /// Step fields that always hold text, so a title such as "2026" is not read as a number.
    public static let formTextKeys: Set<String> = ["preset", "sfx", "text", "textPreset", "wordStyle", "ease"]

    /// `params` with its steps replaced by the form's. An empty field stays an empty string, so the form keeps it to
    /// fill in (the check names it until it is).
    public static func params(_ params: [String: JSONValue], steps: [FormStep]) -> [String: JSONValue] {
        var params = params
        params["patch"] = nil
        params["steps"] = .array(steps.map { step in
            var fields: [String: JSONValue] = ["op": .string(step.op)]
            for field in step.fields where !field.key.isEmpty {
                let text = field.text.trimmingCharacters(in: .whitespacesAndNewlines)
                fields[field.key] = formTextKeys.contains(field.key) || text.isEmpty ? .string(field.text) : formValue(text)
            }
            return .object(fields)
        })
        return params
    }

    /// A field's text: a string as it is, anything else as compact JSON.
    public static func formText(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): return text
        default:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? encoder.encode(value)).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        }
    }

    /// The value typed `text` stands for: JSON when it reads as a number, true/false, null, an object, an array or a
    /// quoted string, else the text as a string (a "$name" parameter reference, a word).
    public static func formValue(_ text: String) -> JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .string(text)
    }
}
