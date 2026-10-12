import BashCutAgent
import BashCutProject
import Foundation
import Testing

/// Quick edits on the selection (#449) and the result card's follow-ups (#448), as the agent reads them.
struct AgentFollowUpTests {
    /// Main: `w` 0–360 and `v` 360–540; music `bed` 300–900 and `late` 900–1200 on the music layer.
    private func project() throws -> Project {
        let media = Media(fields: [
            "id": .string("m"), "path": .string("footage/beach.mov"), "frames": .integer(3600),
            "fps": FrameRate(30, 1).json, "kind": .string("video"), "hasAudio": .bool(true),
        ])
        let music = try Project(name: "Quick", fps: FrameRate(30, 1)).requireTrack(role: TrackRole.music).id
        return try Project(name: "Quick", fps: FrameRate(30, 1)).applying(.group(label: "Setup", author: .user, ops: [
            .addMedia(media), .insert(track: "v1", item: Item(id: "w", media: "m", at: 0, duration: 360)),
            .insert(track: "v1", item: Item(id: "v", media: "m", at: 360, duration: 180)),
            .insert(track: music, item: Item(id: "bed", media: "m", at: 300, duration: 600)),
            .insert(track: music, item: Item(id: "late", media: "m", at: 900, duration: 300)),
        ])).project
    }

    @Test("A quick edit asks for the change, then a review of just the clips' range")
    func quickEdit() throws {
        let project = try project()
        let items = AgentScope.items(["v"], in: project)
        #expect(AgentFollowUp.range(items) == 360...540)
        let faster = try AgentFollowUp.quickEdit(.faster, text: nil, items: items)
        #expect(faster.hasPrefix("Make this part faster"))
        #expect(faster.contains("review run --summary --from 360 --to 540"))
        #expect(faster.contains("review verify"))
        let noted = try AgentFollowUp.quickEdit(.caption, text: "  in Vietnamese ", items: items)
        #expect(noted.contains("Also: in Vietnamese"))
        let custom = try AgentFollowUp.quickEdit(.custom, text: "Make it black and white", items: items)
        #expect(custom.hasPrefix("Make it black and white\n\n"))
        #expect(throws: ProjectError.self) { try AgentFollowUp.quickEdit(.custom, text: " ", items: items) }
        #expect(throws: ProjectError.self) { try AgentFollowUp.quickEdit(.faster, text: nil, items: []) }
        #expect(QuickEdit(rawValue: "music-lower") == .musicLower && QuickEdit(rawValue: "punch-in") == .punchIn)
        for kind in QuickEdit.allCases where kind != .custom {
            let ask = try AgentFollowUp.quickEdit(kind, text: nil, items: items).components(separatedBy: "\n\n")[0]
            #expect(!ask.isEmpty && ask.rangeOfCharacter(from: .decimalDigits) == nil, "\(kind.rawValue): no numbers in the ask")
        }
    }

    @Test("Lower the music takes in the music under the range")
    func music() throws {
        let project = try project()
        #expect(AgentFollowUp.musicItems(under: 360...540, in: project) == ["bed"])
        #expect(AgentFollowUp.musicItems(under: 0...300, in: project).isEmpty)
        #expect(AgentFollowUp.musicItems(under: 800...1000, in: project) == ["bed", "late"])
    }

    @Test("The result card's follow-ups name what is left and keep this version")
    func followUps() {
        let fix = AgentFollowUp.fixIssues(errors: 2, warnings: 5, output: "/tmp/out.mp4")
        #expect(fix.contains("(/tmp/out.mp4)") && fix.contains("2 errors and 5 warnings") && fix.contains("export again"))
        let other = AgentFollowUp.anotherRecipe(current: "bashcut.vlog:travel", recipe: nil)
        #expect(other.contains("different recipe than bashcut.vlog:travel") && other.contains("project derive"))
        let named = AgentFollowUp.anotherRecipe(current: nil, recipe: "bashcut.vlog:food")
        #expect(named.contains("skills get bashcut.vlog:food"))
    }
}
