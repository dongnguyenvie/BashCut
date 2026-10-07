import SwiftUI

/// The agent's questions over its terminal tab (`agent.ask`, Claude Code's AskUserQuestion): options as rows, Other
/// with its own text, the focused option's preview, and Submit or Answer in Terminal.
struct AgentQuestionCard: View {
    @Bindable var prompt: AgentQuestionPrompt
    let agent: String
    @State private var previewed: [Int: Int] = [:]
    @FocusState private var typing: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble").foregroundStyle(.cyan)
                Text(String(format: String(localized: "%@ asks"), agent)).font(.caption.bold())
                Spacer()
            }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(prompt.questions) { question in questionView(question) }
                }.padding(.horizontal, 12).padding(.bottom, 8)
            }.frame(maxHeight: 420).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Button("Answer in Terminal") { prompt.answerInTerminal() }
                    .buttonStyle(.link).font(.caption)
                    .help("Close this card and choose in the terminal instead")
                Spacer()
                Button("Submit") { prompt.submit() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!prompt.canSubmit)
            }.padding(10)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.09, green: 0.1, blue: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cyan.opacity(0.35)))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .padding(10)
        .onAppear { typing = nil }
    }

    @ViewBuilder private func questionView(_ question: AgentQuestionPrompt.Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !question.header.isEmpty {
                Text(question.header.uppercased()).font(.caption2.bold()).foregroundStyle(.cyan)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.cyan.opacity(0.15)))
            }
            Text(question.question).font(.headline).fixedSize(horizontal: false, vertical: true)
            if question.multiSelect {
                Text("Choose any that apply").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(question.options) { option in
                optionRow(
                    selected: prompt.isSelected(option, in: question), multiSelect: question.multiSelect,
                    label: option.label, description: option.description
                ) {
                    prompt.toggle(option, in: question)
                    previewed[question.id] = option.id
                }
                .onHover { if $0, option.preview != nil { previewed[question.id] = option.id } }
            }
            otherRow(question)
            if let preview = preview(for: question) {
                ScrollView {
                    Text(preview).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                .frame(maxHeight: 180)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
            }
            TextField("Notes for the agent (optional)", text: binding(\.notes, question.id))
                .textFieldStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func optionRow(
        selected: Bool, multiSelect: Bool, label: String, description: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon(selected: selected, multiSelect: multiSelect))
                    .foregroundStyle(selected ? Color.cyan : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).fontWeight(selected ? .semibold : .regular)
                    if !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8).contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04)))
        }.buttonStyle(.plain)
    }

    private func otherRow(_ question: AgentQuestionPrompt.Question) -> some View {
        let chosen = prompt.otherChosen.contains(question.id)
        return HStack(alignment: .center, spacing: 8) {
            Button { prompt.toggleOther(question) } label: {
                Image(systemName: icon(selected: chosen, multiSelect: question.multiSelect))
                    .foregroundStyle(chosen ? Color.cyan : Color.secondary)
            }.buttonStyle(.plain)
            TextField("Type your own answer…", text: binding(\.otherText, question.id), axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...4).focused($typing, equals: question.id)
                .onChange(of: prompt.otherText[question.id] ?? "") { _, text in
                    if !text.isEmpty, !prompt.otherChosen.contains(question.id) { prompt.chooseOther(question) }
                }
                .onSubmit { prompt.submit() }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(chosen ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04)))
    }

    private func preview(for question: AgentQuestionPrompt.Question) -> String? {
        let shown = previewed[question.id].flatMap { id in question.options.first { $0.id == id } }
            ?? question.options.first { prompt.isSelected($0, in: question) }
        return shown?.preview
    }

    private func icon(selected: Bool, multiSelect: Bool) -> String {
        multiSelect ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle")
    }

    private func binding(_ path: ReferenceWritableKeyPath<AgentQuestionPrompt, [Int: String]>, _ id: Int) -> Binding<String> {
        Binding(get: { prompt[keyPath: path][id] ?? "" }, set: { prompt[keyPath: path][id] = $0 })
    }
}
