import ArgumentParser
import BashCutAutomation
import BashCutProject
import Foundation

@main struct BashCutCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bashcut", abstract: "Control the running BashCut editor.",
        discussion: CommandLineParser.help + "\n\nAdd --format text to print text results without JSON quoting.")

    @Argument(parsing: .captureForPassthrough, help: "<group> <command> [arguments], for example: timeline get")
    var words: [String] = []

    func run() throws {
        // `bashcut --version` (what agents try first) is `bashcut app version`.
        if words == ["--version"] || words == ["-V"] {
            var alias = self
            alias.words = ["app", "version"]
            return try alias.run()
        }
        // `bashcut timeline --help` or `bashcut help timeline`: that group's commands only.
        let asked = words.first == "help" ? Array(words.dropFirst()) : words.filter { $0 != "--help" && $0 != "-h" }
        if asked.count == 1, words.count == 2, let help = CommandLineParser.groupHelp(asked[0]) {
            FileHandle.standardOutput.write(Data((help + "\n").utf8))
            return
        }
        if words.first == "help", words.count > 1 {
            guard let spec = CommandCatalog.specs.first(where: { $0.cliWords == Array(words.dropFirst()) }) else {
                throw report(RPCFailure(-32602, "Unknown command: \(words.dropFirst().joined(separator: " "))"))
            }
            FileHandle.standardOutput.write(Data((CommandReference.entry(spec).joined(separator: "\n") + "\n").utf8))
            return
        }
        if words.isEmpty || ["help", "-h", "--help"].contains(words[0]) { throw CleanExit.helpRequest(self) }
        // `bashcut <group> <command> --help` prints that command's reference, like `bashcut help <group> <command>`.
        if words.prefix(while: { $0 != "--" }).contains(where: { $0 == "--help" || $0 == "-h" }),
            let spec = CommandCatalog.specs.first(where: { words.starts(with: $0.cliWords) }) {
            FileHandle.standardOutput.write(Data((CommandReference.entry(spec).joined(separator: "\n") + "\n").utf8))
            return
        }
        if words == ClaudeHook.words { return hook() }
        defer { DebugLog.flush() }
        let invocation: CommandLineParser.Invocation
        do { invocation = try CommandLineParser.parse(words) } catch {
            DebugLog.write("cli", "command parsing failed")
            throw report(RPCFailure.from(error, fallbackCode: -32602))
        }
        DebugLog.write("cli", "call \(invocation.spec.name)")
        let response: RPCResponse
        do {
            response = try UnixRPCClient.call(
                RPCRequest(
                    method: invocation.spec.name, params: invocation.params,
                    token: AutomationPaths.sessionToken()))
        } catch {
            DebugLog.write("cli", "\(invocation.spec.name) failed")
            throw report(RPCFailure.from(error))
        }
        try write(response, format: invocation.format)
        let status = CommandCatalog.exitStatus(method: invocation.spec.name, result: response.result)
        if status != 0 { throw ExitCode(status) }
    }

    /// Claude Code's AskUserQuestion hook (`ClaudeHook`): asks in the app and prints the answers, or prints nothing
    /// (exit 0) so Claude asks in the terminal, whatever goes wrong.
    private func hook() {
        defer { DebugLog.flush() }
        guard let questions = ClaudeHook.questions(hookInput: FileHandle.standardInput.readDataToEndOfFile())
        else { return }
        do {
            let response = try UnixRPCClient.call(
                RPCRequest(
                    method: "agent.ask", params: ["questions": .array(questions)], token: AutomationPaths.sessionToken()))
            guard let output = ClaudeHook.output(questions: questions, result: response.result ?? .null) else { return }
            FileHandle.standardOutput.write(output + Data([10]))
        } catch {
            DebugLog.write("cli", "agent.ask hook fell back to the terminal")
        }
    }

    private func report(_ failure: RPCFailure) -> ExitCode {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if var data = try? encoder.encode(failure.typed.payload) {
            data.append(10)
            FileHandle.standardError.write(data)
        }
        return ExitCode(failure.exitStatus)
    }

    private func write(_ response: RPCResponse, format: String) throws {
        if format == "text", let text = response.result?.string {
            FileHandle.standardOutput.write(Data((text + "\n").utf8))
            return
        }
        let encoder = JSONEncoder()
        // Pretty in a terminal; compact when read by a program or an agent, where indentation only costs tokens.
        encoder.outputFormatting = isatty(STDOUT_FILENO) == 1
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(response.result ?? .null)
        data.append(10)
        FileHandle.standardOutput.write(data)
    }
}
