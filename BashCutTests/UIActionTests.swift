import Testing

@testable import BashCutAutomation

struct UIActionTests {
    @Test("Shortcuts parse in any modifier order and print canonically")
    func shortcutParsing() throws {
        let redo = try #require(UIShortcut(parsing: "Shift+CMD+z"))
        #expect(redo == UIShortcut("z", [.command, .shift]))
        #expect(redo.description == "cmd+shift+z")
        #expect(UIShortcut(parsing: "command+option+k") == UIShortcut("k", [.command, .option]))
        #expect(UIShortcut(parsing: "cmd++") == UIShortcut("+", [.command]))
        #expect(UIShortcut(parsing: "space") == UIShortcut("space"))
        #expect(UIShortcut(parsing: "hyper+k") == nil)
        #expect(UIShortcut(parsing: "cmd+") == nil)
    }

    @Test("Actions are found by ID or by any of their shortcuts")
    func matching() {
        #expect(UIAction.matching("timeline.split") == [.split])
        #expect(UIAction.matching("cmd+b") == [.split])
        #expect(UIAction.matching("s") == [.split])
        #expect(UIAction.matching("cmd+shift+z") == [.redo])
        #expect(UIAction.matching("cmd+=") == [.zoomIn])
        #expect(UIAction.matching("shift+delete") == [.lift])
        // `space` plays whichever viewer is shown; the document picks the available one.
        #expect(Set(UIAction.matching("space")) == [.togglePlayback, .sourceTogglePlayback])
        #expect(UIAction.matching("nope").isEmpty)
    }

    @Test("Action IDs are unique and no shortcut is bound twice in the same viewer")
    func uniqueness() {
        #expect(Set(UIAction.allCases.map(\.id)).count == UIAction.allCases.count)
        var seen: [UIShortcut: UIAction] = [:]
        for action in UIAction.allCases {
            for shortcut in action.shortcuts {
                if let other = seen[shortcut] {
                    let pair: Set<UIAction> = [other, action]
                    #expect(pair == [.togglePlayback, .sourceTogglePlayback], "\(shortcut) on \(other.id) and \(action.id)")
                }
                seen[shortcut] = action
            }
        }
        #expect(UIAction.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
