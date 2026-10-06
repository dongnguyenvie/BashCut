import Foundation
import Testing

@testable import BashCutAutomation

struct ChatScopeCommandTests {
    @Test("chat attach and detach take comma-separated items, are UI commands, and chat agents cannot call them")
    @MainActor func chatScope() throws {
        let attach = try CommandLineParser.parse(["chat", "attach", "--items", "v1,t2", "--plugin", "example.chat"])
        #expect(attach.spec.mode == .ui)
        #expect(attach.params == ["items": .string("v1,t2"), "plugin": .string("example.chat")])
        #expect(throws: RPCFailure.self) { try attach.spec.validate([:]) }
        let detach = try CommandLineParser.parse(["chat", "detach"])
        #expect(detach.spec.mode == .ui && detach.params.isEmpty)
        #expect(!ChatCommandSession.allowedMethods.contains("chat.attach"))
        #expect(!ChatCommandSession.allowedMethods.contains("chat.detach"))
        #expect(UIAction.matching("clip.send-to-agent") == [.sendToAgent])
    }
}
