import Foundation
import Testing

@testable import BashCutAutomation

struct DebugLogWriterTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Writers retain their handle and recover when another writer rotates the log")
    func rotation() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("debug.log")
        let first = DebugLogWriter(url: url, maximumBytes: 10)
        let second = DebugLogWriter(url: url, maximumBytes: 10)
        first.append("first\n")
        second.append("second\n")
        #expect(first.openCount == 1 && second.openCount == 1)
        second.append("third\n")
        first.append("fourth\n")
        #expect(first.openCount == 2 && second.openCount == 2)
        #expect(try String(contentsOf: url, encoding: .utf8) == "third\nfourth\n")
        #expect(try String(contentsOf: root.appendingPathComponent("debug.1.log"), encoding: .utf8) == "first\nsecond\n")
    }

    @Test("Concurrent writers produce intact unique lines without reopening per append")
    func concurrent() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("debug.log")
        let writers = (0..<4).map { _ in DebugLogWriter(url: url, maximumBytes: 1_000_000) }
        DispatchQueue.concurrentPerform(iterations: 400) { index in writers[index % writers.count].append("line-\(index)\n") }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(Set(lines) == Set((0..<400).map { "line-\($0)" }))
        #expect(lines.count == 400)
        #expect(writers.allSatisfy { $0.openCount == 1 })
    }

    @Test("Concurrent CLI processes rotate safely, flush before exit and never persist raw secret arguments")
    func cliProcesses() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("debug.log")
        try Data(repeating: 120, count: 5 * 1024 * 1024 + 1).write(to: url)
        let executable = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/debug/bashcut")
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        var processes: [Process] = []
        for index in 0..<10 {
            let process = Process()
            process.executableURL = executable
            // Invalid flag fails before any RPC or token lookup, so this test never contacts a running app.
            process.arguments = ["plugins", "option", "example", "--option", "apiKey", "--value", "secret-canary-\(index)", "--invalid"]
            process.environment = ["BASHCUT_DEBUG_LOG": "1", "BASHCUT_DEBUG_LOG_PATH": url.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            processes.append(process)
        }
        for process in processes { process.waitUntilExit(); #expect(process.terminationStatus == 64) }
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 10)
        #expect(!text.contains("secret-canary"))
        let archive = root.appendingPathComponent("debug.1.log")
        #expect(try FileManager.default.attributesOfItem(atPath: archive.path)[.posixPermissions] as? Int == 0o600)
    }
}
