import BashCutAutomation
import BashCutProject
import Foundation
import Observation

/// Questions an agent asks in a card over its terminal tab (`agent.ask`): Claude Code's AskUserQuestion, routed here
/// by a hook. The handler awaits `answer()`; the card, the tab closing or the timeout finishes it once.
@MainActor @Observable final class AgentQuestionPrompt {
    struct Option: Identifiable {
        let id: Int
        let label: String
        let description: String
        let preview: String?
    }

    struct Question: Identifiable {
        let id: Int
        let question: String
        let header: String
        let multiSelect: Bool
        let options: [Option]
    }

    let questions: [Question]
    /// Chosen option IDs per question.
    var selected: [Int: Set<Int>] = [:]
    /// Questions answered with Other, and the text typed there.
    var otherChosen: Set<Int> = []
    var otherText: [Int: String] = [:]
    var notes: [Int: String] = [:]
    @ObservationIgnored private var result: JSONValue?
    @ObservationIgnored private var waiting: CheckedContinuation<JSONValue, Never>?

    static let declined: JSONValue = .object(["answered": .bool(false)])

    /// Reads AskUserQuestion's `questions`; throws when one has no question text or options.
    init(questions: [JSONValue]) throws {
        self.questions = try questions.enumerated().map { index, value in
            let options = value.object["options"]?.array ?? []
            guard let text = value.object["question"]?.string, !text.isEmpty, !options.isEmpty else {
                throw RPCFailure(-32602, "Each question needs question text and options")
            }
            return Question(
                id: index, question: text, header: value.object["header"]?.string ?? "",
                multiSelect: value.object["multiSelect"]?.bool ?? false,
                options: options.enumerated().map { optionIndex, option in
                    Option(
                        id: optionIndex, label: option.object["label"]?.string ?? "",
                        description: option.object["description"]?.string ?? "",
                        preview: option.object["preview"]?.string.flatMap { $0.isEmpty ? nil : $0 })
                })
        }
        guard !self.questions.isEmpty else { throw RPCFailure(-32602, "questions must not be empty") }
    }

    func isSelected(_ option: Option, in question: Question) -> Bool { selected[question.id]?.contains(option.id) == true }

    /// Picks an option: toggles it for multiple choice, else replaces the choice and leaves Other.
    func toggle(_ option: Option, in question: Question) {
        if question.multiSelect {
            selected[question.id, default: []].formSymmetricDifference([option.id])
        } else {
            selected[question.id] = [option.id]
            otherChosen.remove(question.id)
        }
    }

    func chooseOther(_ question: Question) {
        if !question.multiSelect { selected[question.id] = [] }
        otherChosen.insert(question.id)
    }

    func toggleOther(_ question: Question) {
        if otherChosen.contains(question.id) { otherChosen.remove(question.id) } else { chooseOther(question) }
    }

    /// The answer for one question: chosen labels (comma-separated), with the typed text last; empty when unanswered.
    func answer(for question: Question) -> String {
        var parts = question.options.filter { isSelected($0, in: question) }.map(\.label)
        let typed = (otherText[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if otherChosen.contains(question.id), !typed.isEmpty { parts.append(typed) }
        return parts.joined(separator: ", ")
    }

    var canSubmit: Bool { questions.allSatisfy { !answer(for: $0).isEmpty } }

    /// `agent.ask`'s result: answers and annotations (notes, the chosen option's preview) keyed by question text.
    var answeredJSON: JSONValue {
        var answers: [String: JSONValue] = [:]
        var annotations: [String: JSONValue] = [:]
        for question in questions {
            answers[question.question] = .string(answer(for: question))
            var annotation: [String: JSONValue] = [:]
            let note = (notes[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { annotation["notes"] = .string(note) }
            if !question.multiSelect, let preview = question.options.first(where: { isSelected($0, in: question) })?.preview {
                annotation["preview"] = .string(preview)
            }
            if !annotation.isEmpty { annotations[question.question] = .object(annotation) }
        }
        return .object(["answered": .bool(true), "answers": .object(answers), "annotations": .object(annotations)])
    }

    func submit() {
        guard canSubmit else { return }
        finish(answeredJSON)
    }

    /// Lets the agent ask in the terminal instead.
    func answerInTerminal() { finish(Self.declined) }

    var isFinished: Bool { result != nil }

    /// Waits until the prompt is finished and returns its result.
    func answer() async -> JSONValue {
        if let result { return result }
        return await withCheckedContinuation { waiting = $0 }
    }

    /// Finishes once; later calls are ignored.
    func finish(_ value: JSONValue) {
        guard result == nil else { return }
        result = value
        waiting?.resume(returning: value)
        waiting = nil
    }
}

extension AgentDockModel {
    /// Shows `prompt` over `session`'s terminal and waits for the answer, or `seconds`; a newer question replaces it,
    /// and closing the tab or the agent exiting lets it go unanswered.
    func ask(_ prompt: AgentQuestionPrompt, in session: TerminalSession, seconds: Int) async -> JSONValue {
        session.question?.answerInTerminal()
        session.question = prompt
        selectedSession = session.id
        chatPluginID = nil
        pluginViewKey = nil
        if !isDetached { document.ui.showAgentDock = true }
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        let timeout = Task { [weak self, weak prompt, weak session] in
            while !Task.isCancelled, Date() < deadline, let self, let session,
                self.sessions.contains(where: { $0 === session }), session.view.process.running {
                try? await Task.sleep(for: .seconds(1))
            }
            prompt?.answerInTerminal()
        }
        let result = await prompt.answer()
        timeout.cancel()
        if session.question === prompt { session.question = nil }
        return result
    }
}
