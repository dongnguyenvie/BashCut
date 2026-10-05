import BashCutAgent
import Foundation
import Testing

struct AgentContextFileTests {
    @Test("The context is written to an owner-only file, replacing the previous one")
    func write() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("agent-context")
        try AgentContextFile.write("first", in: folder)
        let url = try AgentContextFile.write("[BashCut context]\nrev: 44\n[/BashCut context]", in: folder)
        #expect(url.lastPathComponent == AgentContextFile.fileName)
        #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("[BashCut context]\nrev: 44"))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("The pasted prompt is the request plus short lines for the context file and the frame")
    func prompt() {
        let context = URL(fileURLWithPath: "/p/My Project/.bashcut/cache/agent-context/context.md")
        let frame = URL(fileURLWithPath: "/p/frame-r4-f12.png")
        let request = String(repeating: "Fix the caption timing. ", count: 4)

        let asked = AgentContextFile.prompt(request: "  \(request)\n", context: context, image: frame)
        #expect(asked.hasPrefix(request.trimmingCharacters(in: .whitespaces) + "\n"))
        #expect(asked.contains("`\(context.path)`"))
        #expect(asked.hasSuffix("Current viewer frame: `\(frame.path)`"))
        #expect(asked.count < 400)

        #expect(AgentContextFile.prompt(request: "", context: context)
            == "Read the BashCut context in `\(context.path)`.")
    }
}
