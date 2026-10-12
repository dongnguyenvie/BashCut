import BashCutPlugin
import Foundation
import Testing

/// Dragging files out of plugin views (#408).
@Suite("Plugin view drag")
struct PluginViewDragTests {
    @Test("Only absolute paths to existing video, audio and image files can be dragged")
    func files() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("folder.mov"), withIntermediateDirectories: true)
        for name in ["take.wav", "clip.mov", "still.png", "notes.txt", "key"] {
            try Data("x".utf8).write(to: root.appendingPathComponent(name))
        }
        #expect(PluginViewDrag.file(root.appendingPathComponent("take.wav").path) != nil)
        #expect(PluginViewDrag.file(root.appendingPathComponent("clip.mov").path) != nil)
        #expect(PluginViewDrag.file(root.appendingPathComponent("still.png").path) != nil)
        #expect(PluginViewDrag.file(root.appendingPathComponent("notes.txt").path) == nil)
        #expect(PluginViewDrag.file(root.appendingPathComponent("key").path) == nil)
        #expect(PluginViewDrag.file(root.appendingPathComponent("folder.mov").path) == nil)
        #expect(PluginViewDrag.file(root.appendingPathComponent("missing.wav").path) == nil)
        #expect(PluginViewDrag.file("take.wav") == nil && PluginViewDrag.file(nil) == nil)
        #expect(PluginFeature.all.contains("views.drag"))
    }
}
