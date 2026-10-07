import Testing

@testable import BashCutProject

/// Severity and fixes (#435), sound (#431), text placement (#433) and the hook (#434).
struct ReviewQualityTests {
    /// A 1080×1920, 30 fps project of `seconds` with picture on Main, so no gap is reported.
    func project(seconds: Int = 10, width: Int = 1080, height: Int = 1920) throws -> Project {
        var project = Project(name: "Quality", fps: FrameRate(30, 1))
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

    func text(_ id: String, _ value: String, at: Int = 0, duration: Int = 60, style: [String: JSONValue] = [:]) -> Item {
        var item = Item(id: id, at: at, duration: duration)
        item["text"] = .string(value)
        if !style.isEmpty { item["textStyle"] = .object(style) }
        return item
    }

    func ids(_ issues: [ReviewIssue], _ prefix: String) -> [String] {
        issues.map(\.id).filter { $0.hasPrefix(prefix) }
    }

    /// The limits the checks used before #466, as a recipe would set them.
    static let shortFormProfile: JSONValue = .object([
        "minShotSeconds": .number(0.4), "maxShotSeconds": .number(8), "maxStillSeconds": .number(4),
        "maxSilenceSeconds": .number(1.5), "maxMusicGapSeconds": .number(1), "voiceoverMarginSeconds": .number(0.3),
        "captionLineChars": .number(32), "captionMaxLines": .number(2), "stillMotion": .number(0.02),
        "jumpCutChange": .number(0.06), "blackMinSeconds": .number(0.5), "loudnessToleranceLU": .number(2),
        "minTextSize": .number(0.03), "minSpeechCoverage": .number(0.9),
    ])

    /// The review with TikTok as the output and, with `profiled`, the short-form profile.
    func run(_ project: Project, profiled: Bool = true, platforms: [OutputPlatform] = [.tiktok]) -> [ReviewIssue] {
        var project = project
        if profiled, project["review"] == nil { project["review"] = Self.shortFormProfile }
        return TimelineReview.run(project, context: ReviewContext(targets: ReviewTargets(platforms: platforms)))
    }

    @Test("Errors come first; the summary counts severities and passes only without errors (#435)")
    func severityAndSummary() throws {
        var project = try project()
        set(&project, track: "v1", [Item(id: "clip", media: "m", at: 30, duration: 270)])
        set(&project, track: "t1", [text("hook", "Đà Lạt 48h?", at: 30)])
        let issues = TimelineReview.run(project)
        #expect(issues.first?.id == "gap-clip")
        #expect(issues.first?.severity == .error)
        #expect(issues.first?.fix?.command == "timeline.close-gap")
        #expect(issues.first?.fix?.arguments["atFrame"] == .integer(0))
        let ranks = issues.map(\.severity)
        #expect(ranks == ranks.sorted())
        let summary = ReviewSummary(issues)
        #expect(summary.errors == 1)
        #expect(!summary.passed)
        #expect(issues.first?.json.object["severity"] == .string("error"))
        #expect(issues.first?.json.object["fix"]?.object["command"] == .string("timeline.close-gap"))
        #expect(ReviewSummary([]).passed)
    }

    @Test("Loudness against the export's own target: unmeasured is info, off target and hot peaks are errors (#431, P0-K2)")
    func loudness() throws {
        var project = try project()
        project["review"] = Self.shortFormProfile
        set(&project, track: "a3", [Item(id: "bed", media: "music", at: 0, duration: 300)])
        let targets = ReviewTargets(measureArguments: ["preset": .string("tiktok")])
        let unmeasured = TimelineReview.run(project, context: ReviewContext(targets: targets))
        let note = unmeasured.first { $0.id == "loudness-unmeasured" }
        #expect(note?.severity == .info)
        #expect(note?.fix?.command == "export.start")
        #expect(note?.fix?.arguments["normalizeAudio"] == .bool(true))
        #expect(note?.fix?.arguments["preset"] == .string("tiktok"))

        let measured = { (project: Project, lufs: Double, peak: Double, revision: Int) in
            TimelineReview.run(project, context: ReviewContext(
                loudness: ReviewLoudness(
                    revision: revision, integratedLUFS: lufs, truePeakDbTP: peak, loudnessRangeLU: 3, targetLUFS: -14,
                    maxTruePeakDbTP: -1, preset: "tiktok"),
                targets: targets))
        }
        #expect(ids(measured(project, -14.3, -1.2, project.revision), "loudness").isEmpty)
        #expect(ids(measured(project, -14.3, -1.2, project.revision), "true-peak").isEmpty)
        // The older AgentVid kits shipped at -31 LUFS; one Reelcrew render clipped at +0.2 dBTP.
        #expect(measured(project, -31, -9, project.revision).first { $0.id == "loudness" }?.severity == .error)
        #expect(ids(measured(project, -12.7, 0.2, project.revision), "true-peak") == ["true-peak"])
        #expect(ids(measured(project, -31, -9, project.revision + 1), "loudness") == ["loudness-unmeasured"])
        // Without a tolerance the measurement is info; the peak ceiling is the platform's and stays an error.
        var bare = project
        bare["review"] = nil
        #expect(measured(bare, -31, 0.2, bare.revision).first { $0.id == "loudness" }?.severity == .info)
        #expect(measured(bare, -31, 0.2, bare.revision).first { $0.id == "true-peak" }?.severity == .error)
    }

    @Test("Music with ducking off under speech, dead air and a music bed that drops out (#431)")
    func soundLayout() throws {
        var project = try project(seconds: 20)
        set(&project, track: "a2", [Item(id: "vo", media: "voice", at: 0, duration: 150)])
        set(&project, track: "a3", [
            Item(id: "bed1", media: "music", at: 0, duration: 200),
            Item(id: "bed2", media: "music", at: 300, duration: 200),
        ])
        let index = project.tracks.firstIndex { $0.id == "a3" }!
        project.tracks[index]["duckingEnabled"] = .bool(false)
        let issues = run(project)
        let ducking = issues.first { $0.id == "ducking-a3" }
        #expect(ducking?.fix?.command == "timeline.apply" && ducking?.severity == .info)
        let op = ducking?.fix?.arguments["ops"]?.array.first?.object
        #expect(op?["op"] == .string("setTrackProperties"))
        #expect(op?["patch"]?.object["duckingEnabled"] == .bool(true))
        // 200–300 has no sound (3.3 s); 500–600 too, at the end.
        #expect(ids(issues, "silence-") == ["silence-clip+200", "silence-clip+500"])
        #expect(ids(issues, "music-gap-") == ["music-gap-clip+200"])

        project.tracks[index]["muted"] = .bool(true)
        project.tracks[index]["duckingEnabled"] = .bool(true)
        let muted = run(project)
        #expect(ids(muted, "ducking-").isEmpty)
        #expect(ids(muted, "music-gap-").isEmpty)
        #expect(ids(muted, "silence-") == ["silence-clip+150"])
        // Without limits: only the longest silence, as info.
        let bare = run(project, profiled: false).filter { $0.id.hasPrefix("silence-") }
        #expect(bare.map(\.id) == ["silence-clip+150"] && bare.first?.severity == .info)
    }

    @Test("Vertical safe area: bottom bar is an error with a fix, side buttons and top bar are warnings (#433)")
    func verticalSafeArea() throws {
        var project = try project()
        set(&project, track: "t1", [
            text("low", "Mua ngay", style: ["positionY": .number(0.05)]),
            text("wide", "Một dòng chữ rất dài chạy hết ngang khung", at: 60, style: ["positionY": .number(0.3)]),
            text("high", "Tiêu đề", at: 120, style: ["positionY": .number(0.95)]),
            text("fine", "Đà Lạt 48h", at: 180, style: ["positionY": .number(0.6)]),
        ])
        let issues = run(project)
        let low = issues.first { $0.id == "safe-bottom-low" }
        #expect(low?.severity == .error)
        let patch = low?.fix?.arguments["ops"]?.array.first?.object["patch"]?.object["textStyle"]?.object
        let raised = patch?["positionY"]?.double ?? 0
        #expect(raised > 0.16)
        var moved = project
        set(&moved, track: "t1", [text("low", "Mua ngay", style: ["positionY": .number(raised)])])
        #expect(ids(run(moved), "safe-").isEmpty)
        #expect(ids(issues, "safe-side-") == ["safe-side-wide"])
        #expect(ids(issues, "safe-top-") == ["safe-top-high"])
        #expect(!issues.contains { $0.id.hasSuffix("-fine") })
    }

    @Test("Small text, caption lines, overlapping text and landscape title safe (#433)")
    func textLayout() throws {
        var project = try project()
        set(&project, track: "t1", [
            text("tiny", "nhỏ", style: ["size": .number(0.02)]),
            text("lines", "một\nhai\nba", at: 90),
        ])
        set(&project, track: "v2", [])
        var titles = Track(id: "t2", kind: "text", role: "overlay")
        titles.items = [text("over", "chồng", at: 100)]
        project.tracks.append(titles)
        let issues = run(project)
        #expect(ids(issues, "small-text-") == ["small-text-tiny"])
        #expect(ids(issues, "caption-lines-") == ["caption-lines-lines"])
        #expect(ids(issues, "text-overlap-") == ["text-overlap-over"])
        // Text size and lines are the project's limits: none without them.
        let bare = run(project, profiled: false)
        #expect(ids(bare, "small-text-").isEmpty && ids(bare, "caption-lines-").isEmpty)

        var wide = try self.project(width: 1920, height: 1080)
        set(&wide, track: "t1", [text("edge", "Tiêu đề", style: ["positionY": .number(0.97)])])
        let landscape = run(wide, platforms: [.youtube])
        #expect(ids(landscape, "title-safe-") == ["title-safe-edge"])
        #expect(ids(landscape, "safe-").isEmpty)
    }

    @Test("Hook: no check without a project window; with one, nothing in it warns and any text or speech passes (#467)")
    func hook() throws {
        var project = try project()
        #expect(ids(TimelineReview.run(project), "hook").isEmpty)

        project["review"] = .object(["hookSeconds": .integer(3)])
        #expect(TimelineReview.run(project).first { $0.id == "hook" }?.severity == .warning)

        set(&project, track: "t1", [text("title", "Chuyến đi Đà Lạt", at: 15)])
        #expect(ids(TimelineReview.run(project), "hook").isEmpty)

        set(&project, track: "t1", [text("title", "Đi đâu cuối tuần?", at: 15)])
        #expect(ids(TimelineReview.run(project), "hook").isEmpty)

        set(&project, track: "t1", [])
        set(&project, track: "a2", [Item(id: "vo", media: "voice", at: 10, duration: 60)])
        #expect(ids(TimelineReview.run(project), "hook").isEmpty)

        // Too short to need a hook.
        #expect(ids(TimelineReview.run(try self.project(seconds: 5)), "hook").isEmpty)
    }

    @Test("With an empty review profile, editorial findings are info only; mechanical problems stay errors (#470)")
    func neutralDefaults() throws {
        var project = try project(seconds: 20)
        set(&project, track: "v1", [
            Item(id: "a", media: "m", at: 0, duration: 400), Item(id: "b", media: "m", at: 400, duration: 5),
            Item(id: "c", media: "m", at: 420, duration: 180),
        ])
        set(&project, track: "t1", [text("long", "Một dòng phụ đề rất dài hơn ba mươi hai ký tự nhiều lắm")])
        set(&project, track: "a3", [Item(id: "bed", media: "music", at: 0, duration: 200)])
        let issues = run(project, profiled: false)
        #expect(issues.contains { $0.id == "gap-c" && $0.severity == .error })
        let editorial = issues.filter { !$0.id.hasPrefix("gap-") && !$0.id.hasPrefix("safe-") }
        #expect(!editorial.isEmpty && editorial.allSatisfy { $0.severity == .info }, "\(editorial.map { ($0.id, $0.severity) })")
        #expect(ids(issues, "caption-").isEmpty)
    }
}
