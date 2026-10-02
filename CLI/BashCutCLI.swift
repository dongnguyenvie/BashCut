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
        if words.isEmpty || ["help", "-h", "--help"].contains(words[0]) { throw CleanExit.helpRequest(self) }
        let invocation: CommandLineParser.Invocation
        do { invocation = try CommandLineParser.parse(words) } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            throw ExitCode.validationFailure
        }
        let response = try UnixRPCClient.call(
            RPCRequest(
                method: invocation.spec.name, params: invocation.params,
                token: ProcessInfo.processInfo.environment["BASHCUT_SESSION_TOKEN"]))
        try write(response, format: invocation.format)
    }

    private func write(_ response: RPCResponse, format: String) throws {
        if format == "text", let text = response.result?.string {
            FileHandle.standardOutput.write(Data((text + "\n").utf8))
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(response.result ?? .null)
        data.append(10)
        FileHandle.standardOutput.write(data)
    }
}
