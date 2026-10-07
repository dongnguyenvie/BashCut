import Testing

@testable import BashCutProject

/// Platform targets (#441, #469, P0-K2) and the project's review profile: hook window, severities and validation.
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

    func run(_ project: Project, _ platforms: OutputPlatform...) -> [ReviewIssue] {
        TimelineReview.run(project, context: ReviewContext(targets: ReviewTargets(platforms: platforms)))
    }

    @Test("Safe zones follow every output: Reels' taller caption bar flags text TikTok alone accepts (#469)")
    func safeZones() throws {
        var project = try project()
        // Default bold-outline caption: baseline at 18 %, its box starts about 17 % from the bottom.
        set(&project, track: "t1", [text("cap", "Đà Lạt 48h?")])
        #expect(run(project, .tiktok).first { $0.id == "safe-bottom-cap" } == nil)
        let reels = run(project, .reels).first { $0.id == "safe-bottom-cap" }
        #expect(reels?.severity == .error)
        #expect(reels?.detail.contains("20%") == true)
        // Two outputs: the strictest zone of each side wins.
        let both = run(project, .tiktok, .reels).first { $0.id == "safe-bottom-cap" }
        #expect(both?.detail.contains("TikTok and Instagram Reels") == true)
        #expect(run(project, .shorts).contains { $0.id == "safe-bottom-cap" })
        // No platform: nothing assumed, one note.
        let none = run(project)
        #expect(!none.contains { $0.id.hasPrefix("safe-") })
        #expect(none.first { $0.id == "platform-none" }?.severity == .info)
        // Overrides change the check when an app changes its interface.
        project["review"] = .object(["platform": .object(["safeArea": .object(["bottom": .number(0.1)])])])
        #expect(run(project, .reels).first { $0.id == "safe-bottom-cap" } == nil)
        // A landscape frame checks title safe of a landscape output only.
        var wide = try self.project(width: 1920, height: 1080)
        set(&wide, track: "t1", [text("low", "Low title", positionY: 0.02)])
        #expect(run(wide, .youtube).contains { $0.id == "title-safe-low" })
        #expect(!run(wide, .reels).contains { $0.id == "title-safe-low" })
    }

    @Test("Too long for the platform is an error; a frame of another shape suggests project format")
    func lengthAndShape() throws {
        let long = try project(seconds: 200)
        let issue = run(long, .shorts).first { $0.id == "output-length-shorts" }
        #expect(issue?.severity == .error)
        #expect(issue?.detail.contains("3:20") == true)
        #expect(issue?.detail.contains("3:00") == true)
        #expect(issue?.frame == 180 * 30)
        #expect(run(long, .tiktok).first { $0.id.hasPrefix("output-length") } == nil)
        #expect(run(long, .youtube).first { $0.id.hasPrefix("output-length") } == nil)
        #expect(run(long, .tiktok, .shorts).filter { $0.id.hasPrefix("output-length") }.map(\.id) == ["output-length-shorts"])

        let wide = try project(width: 1920, height: 1080)
        let shape = run(wide, .tiktok).first { $0.id == "output-shape-tiktok" }
        #expect(shape?.fix?.command == "project.format")
        #expect(shape?.fix?.arguments["canvas"] == .string("portrait"))
        #expect(run(wide, .youtube).first { $0.id.hasPrefix("output-shape") } == nil)
        #expect(run(try project(width: 1080, height: 1080), .youtube).contains { $0.id == "output-shape-youtube" })
        // No platform, no platform checks.
        #expect(run(long).allSatisfy { !$0.id.hasPrefix("output-") })
    }

    @Test("review.severities re-rates or drops checks by ID, prefix or plugin provider; the longest key wins")
    func severities() throws {
        var project = try project()
        set(&project, track: "t1", [text("cap", "Đà Lạt 48h?", positionY: 0.05)])
        #expect(run(project, .tiktok).first { $0.id == "safe-bottom-cap" }?.severity == .error)
        project["review"] = .object([
            "severities": .object(["safe": .string("off"), "safe-bottom": .string("info"), "hook": .string("error")])
        ])
        let issues = run(project, .tiktok)
        #expect(issues.first { $0.id == "safe-bottom-cap" }?.severity == .info)
        #expect(issues.map(\.severity) == issues.map(\.severity).sorted())
        project["review"] = .object(["severities": .object(["safe": .string("off")])])
        #expect(run(project, .tiktok).allSatisfy { !$0.id.hasPrefix("safe-") })
        let plugin = ReviewIssue(id: "weak-hook", title: "Weak hook", detail: "", frame: 0, source: "acme.checks")
        project["review"] = .object(["severities": .object(["acme.checks:": .string("info")])])
        #expect(TimelineReview.applyingSeverities([plugin], project: project).first?.severity == .info)
    }

    @Test("review.hookSeconds widens or narrows the hook window")
    func hookWindow() throws {
        var project = try project(seconds: 20)
        set(&project, track: "t1", [text("title", "Hello", at: 4 * 30)])
        #expect(run(project).first { $0.id == "hook" } == nil)
        project["review"] = .object(["hookSeconds": .integer(3)])
        #expect(run(project).first { $0.id == "hook" }?.title == "Nothing said or written in the first 3 seconds")
        project["review"] = .object(["hookSeconds": .integer(5)])
        #expect(run(project).first { $0.id == "hook" } == nil)
    }

    @Test("output.presets and output.targets are checked; each export has its own loudness target (P0-K2)")
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
        project["output"] = .object([
            "presets": .array([.string("youtube-1080"), .string("tiktok")]),
            "targets": .object(["youtube-1080": .object(["integratedLUFS": .number(-16), "truePeakDbTP": .number(-2)])]),
        ])
        try project.validate()
        #expect(project.loudnessTarget(preset: "youtube-1080", platform: .youtube) == (-16, -2))
        #expect(project.loudnessTarget(preset: "tiktok", platform: .tiktok) == (-14, -1))
        project["output"] = .object(["targets": .object(["tiktok": .object(["integratedLUFS": .number(-3)])])])
        #expect(throws: ProjectError.self) { try project.validate() }
    }

    @Test("The review profile is validated: numbers in range, severities from the list, platform fractions (#466)")
    func profileValidation() throws {
        var project = Project(name: "Profile", fps: FrameRate(30, 1))
        project["review"] = .object(["hookSeconds": .number(2), "severities": .object(["safe": .string("off")])])
        try project.validate()
        for review: JSONValue in [
            .object(["hookSeconds": .integer(0)]), .object(["severities": .object(["safe": .string("loud")])]),
            .object(["platform": .object(["safeArea": .object(["bottom": .number(2)])])]), .string("strict"),
        ] {
            project["review"] = review
            #expect(throws: ProjectError.self) { try project.validate() }
        }
    }
}
