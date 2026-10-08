import BashCutAutomation
import BashCutProject
import Foundation
import Testing

struct ClaudeHookTests {
    private let question: JSONValue = .object([
        "question": .string("Which pacing?"), "header": .string("Pacing"), "multiSelect": .bool(false),
        "options": .array([.object(["label": .string("Fast"), "description": .string("Short cuts")])]),
    ])

    @Test("Only an AskUserQuestion hook input yields questions")
    func questions() throws {
        let input: JSONValue = .object([
            "hook_event_name": .string("PreToolUse"), "tool_name": .string("AskUserQuestion"),
            "tool_input": .object(["questions": .array([question])]),
        ])
        #expect(ClaudeHook.questions(hookInput: try JSONEncoder().encode(input)) == [question])
        let other: JSONValue = .object(["tool_name": .string("Bash"), "tool_input": .object([:])])
        #expect(ClaudeHook.questions(hookInput: try JSONEncoder().encode(other)) == nil)
        #expect(ClaudeHook.questions(hookInput: Data("not json".utf8)) == nil)
    }

    @Test("Answers become an allowed PreToolUse decision with the answers in the tool input")
    func output() throws {
        let result: JSONValue = .object([
            "answered": .bool(true), "answers": .object(["Which pacing?": .string("Slower, with room to breathe")]),
            "annotations": .object(["Which pacing?": .object(["notes": .string("Keep the intro")])]),
        ])
        let data = try #require(ClaudeHook.output(questions: [question], result: result))
        let output = try JSONDecoder().decode(JSONValue.self, from: data).object["hookSpecificOutput"]?.object ?? [:]
        #expect(output["hookEventName"] == .string("PreToolUse"))
        #expect(output["permissionDecision"] == .string("allow"))
        let updated = output["updatedInput"]?.object ?? [:]
        #expect(updated["questions"] == .array([question]))
        #expect(updated["answers"] == result.object["answers"])
        #expect(updated["annotations"] == result.object["annotations"])
    }

    @Test("A declined or empty answer prints nothing, so Claude asks in the terminal")
    func declined() {
        #expect(ClaudeHook.output(questions: [question], result: .object(["answered": .bool(false)])) == nil)
        #expect(ClaudeHook.output(questions: [question], result: .object([
            "answered": .bool(true), "answers": .object([:]),
        ])) == nil)
        #expect(ClaudeHook.output(questions: [question], result: .null) == nil)
    }
}
