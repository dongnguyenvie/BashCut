import BashCutAgent
import Foundation
import Testing

struct AgentRequestTests {
    @Test("Only the request and the attached frame are pasted, ending with a newline")
    func paste() {
        #expect(AgentRequest.paste("  Review the timeline.\n") == "Review the timeline.\n")
        #expect(AgentRequest.paste(" \n") == "")

        let frame = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("p/frame-r4-f12.png")
        #expect(AgentRequest.paste("Fix this caption", image: frame)
            == "Fix this caption\nCurrent viewer frame: `~/p/frame-r4-f12.png`\n")
        #expect(AgentRequest.paste("", image: URL(fileURLWithPath: "/tmp/f.png")) == "Current viewer frame: `/tmp/f.png`\n")
    }
}
