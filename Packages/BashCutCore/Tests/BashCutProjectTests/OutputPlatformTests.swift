import Testing

@testable import BashCutProject

/// Platform targets (#441) and the project's review profile: hook window and severities.
struct OutputPlatformTests {
    func project(seconds: Int = 10, width: Int = 1080, height: Int = 1920) throws -> Project {
        var project = Project(name: "Platform", fps: FrameRate(30, 1))
        if width != 1080 || height != 1920 {
            project = try project.applying(.setFormat(width: width, height: height)).project
        }
        set(&project, track: "v1", [Item(id: "clip", media: "m", at: 0, duration: seconds * 30)])
        return project
    }

    func set(_ project: inout Project, track id: String, _ items: [Item]) {
        let index = project.tracks.firstIndex { $0.id == id }!
        project.tracks[index].items = items
    }

    func text(_ id: String, _ value: String, at: Int = 0, positionY: Double? = nil) -> Item {
        var item = Item(id: id, at: at, duration: 60)
        item["text"] = .string(value)
        if let positionY { item["textStyle"] = .object(["positionY": .number(positionY)]) }
        return item
    }

    func run(_ project: Project, _ platform: OutputPlatform?) -> [ReviewIssue] {
        TimelineReview.run(project, context: ReviewContext(targets: ReviewTargets(platform: platform)))
    }

    @Test("Safe zones follow the platform: Reels' taller caption bar flags text TikTok accepts")
    func safeZones() throws {
        var project = try project()
        // Default bold-outline caption: baseline at 18 %, its box starts about 17 % from the bottom.
        set(&project, track: "t1", [text("cap", "Đà Lạt 48h?")])
        #expect(run(project, .tiktok).first { $0.id == "safe-bottom-cap" } == nil)
        let reels = run(project, .reels).first { $0.id == "safe-bottom-cap" }
        #expect(reels?.severity == .error)
        #expect(reels?.detail.contains("20%") == true)
        #expect(reels?.detail.contains("Instagram Reels") == true)
        #expect(run(project, .shorts).contains { $0.id == "safe-bottom-cap" })
        // No platform: TikTok's zones, as before #441.
        #expect(run(project, nil).first { $0.id == "safe-bottom-cap" } == nil)
        // A vertical platform on a landscape frame falls back to title safe.
        var wide = try self.project(width: 1920, height: 1080)
        set(&wide, track: "t1", [text("low", "Low title", positionY: 0.02)])
        #expect(run(wide, .reels).contains { $0.id == "title-safe-low" })
    }

    @Test("Too long for the platform is an error; a frame of another shape suggests project format")
    func lengthAndShape() throws {
        let long = try project(seconds: 200)
        let issue = run(long, .shorts).first { $0.id == "output-length" }
        #expect(issue?.severity == .error)
        #expect(issue?.detail.contains("3:20") == true)
        #expect(issue?.detail.contains("3:00") == true)
        #expect(issue?.frame == 180 * 30)
        #expect(run(long, .tiktok).first { $0.id == "output-length" } == nil)
        #expect(run(long, .youtube).first { $0.id == "output-length" } == nil)

        let wide = try project(width: 1920, height: 1080)
        let shape = run(wide, .tiktok).first { $0.id == "output-shape" }
        #expect(shape?.fix?.command == "project.format")
        #expect(shape?.fix?.arguments["canvas"] == .string("portrait"))
        #expect(run(wide, .youtube).first { $0.id == "output-shape" } == nil)
        #expect(run(try project(width: 1080, height: 1080), .youtube).contains { $0.id == "output-shape" })
        // No platform, no platform checks.
        #expect(run(long, nil).allSatisfy { !$0.id.hasPrefix("output-") })
    }

    @Test("review.severities re-rates or drops checks by ID or prefix; the longest key wins")
    func severities() throws {
        var project = try project()
        set(&project, track: "t1", [text("cap", "Đà Lạt 48h?", positionY: 0.05)])
        #expect(run(project, nil).first { $0.id == "safe-bottom-cap" }?.severity == .error)
        project["review"] = .object([
            "severities": .object(["safe": .string("off"), "safe-bottom": .string("info"), "hook": .string("error")])
        ])
        let issues = run(project, nil)
        #expect(issues.first { $0.id == "safe-bottom-cap" }?.severity == .info)
        #expect(issues.map(\.severity) == issues.map(\.severity).sorted())
        project["review"] = .object(["severities": .object(["safe": .string("off")])])
        #expect(run(project, nil).allSatisfy { !$0.id.hasPrefix("safe-") })
    }

    @Test("review.hookSeconds widens or narrows the hook window")
    func hookWindow() throws {
        var project = try project(seconds: 20)
        set(&project, track: "t1", [text("title", "Hello", at: 4 * 30)])
        #expect(run(project, nil).first { $0.id == "hook" } == nil)
        project["review"] = .object(["hookSeconds": .integer(3)])
        #expect(run(project, nil).first { $0.id == "hook" }?.title == "Nothing said or written in the first 3 seconds")
        project["review"] = .object(["hookSeconds": .integer(5)])
        #expect(run(project, nil).first { $0.id == "hook" } == nil)
    }

    @Test("output.presets lists known export presets; anything else is refused")
    func outputValidation() throws {
        var project = Project(name: "Output", fps: FrameRate(30, 1))
        project["output"] = .object(["presets": .array([.string("reels"), .string("youtube-1080")])])
        try project.validate()
        #expect(project.outputPresets == ["reels", "youtube-1080"])
        project["output"] = .object(["presets": .array([.string("vine")])])
        #expect(throws: ProjectError.self) { try project.validate() }
        project["output"] = .string("reels")
        #expect(throws: ProjectError.self) { try project.validate() }
        #expect(OutputPlatform.named("shorts") == .shorts)
        #expect(OutputPlatform.fallback(for: try self.project()) == .tiktok)
    }
}
