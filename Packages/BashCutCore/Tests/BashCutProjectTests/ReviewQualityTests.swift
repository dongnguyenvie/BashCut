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

    @Test("Loudness: unmeasured is info, off target and hot peaks are errors, other revisions do not count (#431)")
    func loudness() throws {
        var project = try project()
        set(&project, track: "a3", [Item(id: "bed", media: "music", at: 0, duration: 300)])
        let targets = ReviewTargets(integratedLUFS: -14, measureArguments: ["preset": .string("tiktok")])
        let unmeasured = TimelineReview.run(project, context: ReviewContext(targets: targets))
        let note = unmeasured.first { $0.id == "loudness-unmeasured" }
        #expect(note?.severity == .info)
        #expect(note?.fix?.command == "export.start")
        #expect(note?.fix?.arguments["normalizeAudio"] == .bool(true))
        #expect(note?.fix?.arguments["preset"] == .string("tiktok"))

        let measured = { (lufs: Double, peak: Double, revision: Int) in
            TimelineReview.run(project, context: ReviewContext(
                loudness: ReviewLoudness(revision: revision, integratedLUFS: lufs, truePeakDbTP: peak, loudnessRangeLU: 3),
                targets: targets))
        }
        #expect(ids(measured(-14.3, -1.2, project.revision), "loudness").isEmpty)
        #expect(ids(measured(-14.3, -1.2, project.revision), "true-peak").isEmpty)
        // The older AgentVid kits shipped at -31 LUFS; one Reelcrew render clipped at +0.2 dBTP.
        let quiet = measured(-31, -9, project.revision)
        #expect(quiet.first { $0.id == "loudness" }?.severity == .error)
        #expect(ids(measured(-12.7, 0.2, project.revision), "true-peak") == ["true-peak"])
        #expect(ids(measured(-31, -9, project.revision + 1), "loudness") == ["loudness-unmeasured"])
        // No target, no loudness checks (the default context).
        #expect(ids(TimelineReview.run(project), "loudness").isEmpty)
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
        let issues = TimelineReview.run(project)
        let ducking = issues.first { $0.id == "ducking-a3" }
        #expect(ducking?.fix?.command == "timeline.apply")
        let op = ducking?.fix?.arguments["ops"]?.array.first?.object
        #expect(op?["op"] == .string("setTrackProperties"))
        #expect(op?["patch"]?.object["duckingEnabled"] == .bool(true))
        // 200–300 has no sound (3.3 s); 500–600 too, at the end.
        #expect(ids(issues, "silence-") == ["silence-200", "silence-500"])
        #expect(ids(issues, "music-gap-") == ["music-gap-200"])

        project.tracks[index]["muted"] = .bool(true)
        project.tracks[index]["duckingEnabled"] = .bool(true)
        let muted = TimelineReview.run(project)
        #expect(ids(muted, "ducking-").isEmpty)
        #expect(ids(muted, "music-gap-").isEmpty)
        #expect(ids(muted, "silence-") == ["silence-150"])
    }

    @Test("Vertical safe area: bottom bar is an error with a fix, side buttons and top bar are warnings (#433)")
    func verticalSafeArea() throws {
        var project = try project()
        set(&project, track: "t1", [
            text("low", "Mua ngay", style: ["positionY": .number(0.05)]),
            text("wide", "Một dòng chữ rất dài chạy hết ngang khung", at: 60),
            text("high", "Tiêu đề", at: 120, style: ["positionY": .number(0.95)]),
            text("fine", "Đà Lạt 48h", at: 180),
        ])
        let issues = TimelineReview.run(project)
        let low = issues.first { $0.id == "safe-bottom-low" }
        #expect(low?.severity == .error)
        let patch = low?.fix?.arguments["ops"]?.array.first?.object["patch"]?.object["textStyle"]?.object
        let raised = patch?["positionY"]?.double ?? 0
        #expect(raised > 0.16)
        var moved = project
        set(&moved, track: "t1", [text("low", "Mua ngay", style: ["positionY": .number(raised)])])
        #expect(ids(TimelineReview.run(moved), "safe-").isEmpty)
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
        let issues = TimelineReview.run(project)
        #expect(ids(issues, "small-text-") == ["small-text-tiny"])
        #expect(ids(issues, "caption-lines-") == ["caption-lines-lines"])
        #expect(ids(issues, "text-overlap-") == ["text-overlap-over"])

        var wide = try self.project(width: 1920, height: 1080)
        set(&wide, track: "t1", [text("edge", "Tiêu đề", style: ["positionY": .number(0.97)])])
        let landscape = TimelineReview.run(wide)
        #expect(ids(landscape, "title-safe-") == ["title-safe-edge"])
        #expect(ids(landscape, "safe-").isEmpty)
    }

    @Test("Hook: nothing in the first 3 s warns, text without a number is info, a number or speech passes (#434)")
    func hook() throws {
        var project = try project()
        #expect(TimelineReview.run(project).first { $0.id == "hook" }?.severity == .warning)

        set(&project, track: "t1", [text("title", "Chuyến đi Đà Lạt", at: 15)])
        #expect(TimelineReview.run(project).first { $0.id == "hook" }?.severity == .info)

        set(&project, track: "t1", [text("title", "Đà Lạt 48h · 3 triệu", at: 15)])
        #expect(ids(TimelineReview.run(project), "hook").isEmpty)

        set(&project, track: "t1", [text("title", "Đi đâu cuối tuần?", at: 15)])
        #expect(ids(TimelineReview.run(project), "hook").isEmpty)

        set(&project, track: "t1", [])
        set(&project, track: "a2", [Item(id: "vo", media: "voice", at: 10, duration: 60)])
        #expect(ids(TimelineReview.run(project), "hook").isEmpty)

        // Too short to need a hook.
        #expect(ids(TimelineReview.run(try self.project(seconds: 5)), "hook").isEmpty)
    }
}
