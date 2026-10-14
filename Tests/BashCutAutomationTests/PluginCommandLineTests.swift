import BashCutAutomation
import BashCutProject
import Testing

/// The `cli` host call: a plugin's `bashcut …` words run as the same command with the same allow-list (#567).
struct PluginCommandLineTests {
    @Test("argv parses to the command and its validated params")
    func parses() throws {
        let command = try PluginCommandSession.commandLine([
            "argv": .array(["library", "list", "--kind", "clip", "--query", "coffee"].map(JSONValue.string)),
        ])
        #expect(command.method == "library.list")
        #expect(command.params["kind"] == .string("clip"))
        #expect(command.params["query"] == .string("coffee"))
        // --format is accepted and does not change the call.
        let formatted = try PluginCommandSession.commandLine([
            "argv": .array(["jobs", "wait", "job-1", "--done", "--format", "text"].map(JSONValue.string)),
        ])
        #expect(formatted.method == "jobs.wait")
        #expect(formatted.params["job"] == .string("job-1"))
        #expect(formatted.params["done"] == .bool(true))
    }

    @Test("Missing, empty, non-string or unknown argv fails with invalid params; cli cannot run cli", arguments: [
        [:],
        ["argv": JSONValue.array([])],
        ["argv": JSONValue.string("library list")],
        ["argv": JSONValue.array([.string("library"), .integer(2)])],
        ["argv": JSONValue.array([.string("nothing"), .string("here")])],
        ["argv": JSONValue.array([.string("library"), .string("list"), .string("--bogus")])],
    ] as [[String: JSONValue]])
    func failures(_ params: [String: JSONValue]) {
        #expect(throws: RPCFailure.self) { try PluginCommandSession.commandLine(params) }
        #expect((try? PluginCommandSession.commandLine(params)) == nil)
        do { _ = try PluginCommandSession.commandLine(params) } catch let failure as RPCFailure {
            #expect(failure.code == -32602 && !failure.message.isEmpty)
        } catch { Issue.record("Unexpected \(error)") }
        #expect(throws: RPCFailure.self) {
            try PluginCommandSession.commandLine(["argv": .array([.string("cli"), .string("library")])])
        }
    }

    @Test("Plugins may wait for jobs; the cli method itself is not a session command")
    @MainActor func allowList() async {
        #expect(PluginCommandSession.allowedMethods.contains("jobs.wait"))
        #expect(!PluginCommandSession.allowedMethods.contains("cli"))
        let session = PluginCommandSession()
        #expect(await session.perform("cli", params: [:], registry: CommandRegistry()).error?.code == -32601)
    }
}
