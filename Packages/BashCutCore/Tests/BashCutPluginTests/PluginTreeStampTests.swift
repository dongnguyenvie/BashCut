import Foundation
import Testing

@testable import BashCutPlugin

@Suite("Plugin tree stamp")
struct PluginTreeStampTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("node_modules/dependency/lib", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        for index in 0..<50 { try Data("\(index)".utf8).write(to: nested.appendingPathComponent("file\(index).js")) }
        try Data("#!/bin/sh\n".utf8).write(to: root.appendingPathComponent("provider"))
        return root
    }

    @Test("The stamp is stable for an unchanged tree; Finder metadata only re-runs the digest, which ignores it")
    func stable() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try PluginTree.stamp(root), digest = try PluginTree.digest(root)
        #expect(try PluginTree.stamp(root) == first)
        // Writing .DS_Store touches its directory's mtime, so the stamp may change; the pinned digest must not.
        try Data("finder".utf8).write(to: root.appendingPathComponent("node_modules/.DS_Store"))
        #expect(try PluginTree.digest(root) == digest)
    }

    @Test("Content, mode, additions, removals and link targets all change the stamp", arguments: [
        "content", "mode", "added", "removed", "link"
    ])
    func changes(_ kind: String) throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("node_modules/dependency/lib")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("alias").path, withDestinationPath: "provider")
        let before = try PluginTree.stamp(root)
        switch kind {
        case "content": try Data("other".utf8).write(to: nested.appendingPathComponent("file7.js"))
        case "mode": try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nested.appendingPathComponent("file7.js").path)
        case "added": try Data("new".utf8).write(to: nested.appendingPathComponent(".hidden.js"))
        case "removed": try FileManager.default.removeItem(at: nested.appendingPathComponent("file7.js"))
        default:
            try FileManager.default.removeItem(at: root.appendingPathComponent("alias"))
            try FileManager.default.createSymbolicLink(
                atPath: root.appendingPathComponent("alias").path, withDestinationPath: "node_modules/dependency/lib/file1.js")
        }
        #expect(try PluginTree.stamp(root) != before)
    }

    @Test("The stamp follows the folder through a linked plugin root")
    func linkedRoot() throws {
        let root = try folder()
        let link = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: link) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        #expect(try PluginTree.stamp(link) == PluginTree.stamp(root))
    }
}
