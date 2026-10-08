import BashCutProject
import Foundation

/// `agent.ask` bounds: the socket client waits this long plus a margin for the user's answer.
public enum AgentAskDefaults {
    public static let seconds = 900
    public static let maximumSeconds = 3600
}

/// Claude Code's PreToolUse hook for AskUserQuestion in BashCut's Claude tabs (`bashcut agent hook`): the questions
/// show in a card over the terminal (`agent.ask`) and the answers go back as the tool's `answers`, so Claude skips its
/// own menu. Anything else (no questions, no app, the user chose the terminal) prints nothing, and Claude asks in the
/// terminal as usual.
public enum ClaudeHook {
    /// The CLI words that run the hook; not a catalog command, since its input is Claude's hook JSON on stdin.
    public static let words = ["agent", "hook"]

    /// The questions of an AskUserQuestion PreToolUse input, or nil for any other input.
    public static func questions(hookInput: Data) -> [JSONValue]? {
        guard let input = try? JSONDecoder().decode(JSONValue.self, from: hookInput),
            input.object["tool_name"]?.string == "AskUserQuestion",
            let questions = input.object["tool_input"]?.object["questions"]?.array, !questions.isEmpty
        else { return nil }
        return questions
    }

    /// The hook's stdout for `agent.ask`'s `result`: the questions with their answers, allowed without asking again;
    /// nil when the user did not answer here.
    public static func output(questions: [JSONValue], result: JSONValue) -> Data? {
        guard result.object["answered"]?.bool == true, case .object(let answers)? = result.object["answers"], !answers.isEmpty
        else { return nil }
        var updated: [String: JSONValue] = ["questions": .array(questions), "answers": .object(answers)]
        if case .object(let annotations)? = result.object["annotations"], !annotations.isEmpty {
            updated["annotations"] = .object(annotations)
        }
        let output: JSONValue = .object([
            "hookSpecificOutput": .object([
                "hookEventName": .string("PreToolUse"), "permissionDecision": .string("allow"),
                "permissionDecisionReason": .string("Answered in BashCut"), "updatedInput": .object(updated),
            ]),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(output)
    }
}
