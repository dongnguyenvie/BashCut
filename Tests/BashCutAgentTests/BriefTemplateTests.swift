import BashCutAgent
import Foundation
import Testing

struct BriefTemplateTests {
    @Test("25 templates in three groups with unique IDs, and the earlier template IDs kept")
    func catalog() {
        let all = BriefCatalog.all
        #expect(all.count == 25)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(all.filter { $0.group == .make }.count == 13)
        #expect(all.filter { $0.group == .fix }.count == 8)
        #expect(all.filter { $0.group == .finish }.count == 4)
        for id in ["vlog", "short", "review", "montage", "tutorial", "explainer", "captions", "fix"] {
            #expect(BriefCatalog.template(id) != nil, "missing \(id)")
        }
        for template in all {
            #expect(!template.fits.isEmpty && !template.recipe.isEmpty && !template.systemImage.isEmpty)
            #expect(Set(template.fields.map(\.id)).count == template.fields.count, "duplicate field in \(template.id)")
        }
        for state in BriefFit.allCases { #expect(!BriefCatalog.quickStarts(for: state).isEmpty) }
    }

    @Test("Every pattern blank has a field, every field is used, and chip defaults are in range")
    func placeholders() {
        for template in BriefCatalog.all {
            let blanks = BriefText.placeholders(in: template.patternKey)
            #expect(Set(blanks) == Set(template.fields.map(\.id)), "\(template.id): \(blanks)")
            for field in template.fields {
                if case .chips(let options, let index) = field.kind {
                    #expect(options.indices.contains(index) && options.count >= 2, "\(template.id).\(field.id)")
                }
            }
            #expect(!template.prompt().contains("{"), "\(template.id) left a blank")
        }
    }

    @Test("Every template string has English and Vietnamese in Localizable.xcstrings, with the same blanks")
    func localized() throws {
        let strings = try Self.xcstrings()
        let keys = BriefCatalog.all.flatMap(\.sourceKeys) + BriefGroup.allCases.map(\.titleKey)
        for key in Set(keys) where key.contains(where: \.isLetter) {
            let languages = strings[key]
            #expect(languages?["en"]?.isEmpty == false, "no English for \(key)")
            #expect(languages?["vi"]?.isEmpty == false, "no Vietnamese for \(key)")
        }
        for template in BriefCatalog.all {
            let vietnamese = strings[template.patternKey]?["vi"] ?? ""
            #expect(Set(BriefText.placeholders(in: vietnamese)) == Set(template.fields.map(\.id)), "\(template.id) vi")
        }
    }

    @Test("Project state: none, footage, one long talk, timeline, selection")
    func fit() {
        let clip = BriefFit.Media(seconds: 40, hasSpeech: true)
        let podcast = BriefFit.Media(seconds: 52 * 60, hasSpeech: true)
        let longSilent = BriefFit.Media(seconds: 20 * 60, hasSpeech: false)
        #expect(BriefFit.state(hasProject: false, media: [clip], timelineItems: 3, selected: 1) == .none)
        #expect(BriefFit.state(hasProject: true, media: [], timelineItems: 0, selected: 0) == .none)
        #expect(BriefFit.state(hasProject: true, media: [clip, clip], timelineItems: 0, selected: 0) == .footage)
        #expect(BriefFit.state(hasProject: true, media: [longSilent], timelineItems: 0, selected: 0) == .footage)
        #expect(BriefFit.state(hasProject: true, media: [podcast], timelineItems: 0, selected: 0) == .talk)
        #expect(BriefFit.state(hasProject: true, media: [podcast, clip], timelineItems: 1, selected: 0) == .talk)
        #expect(BriefFit.state(hasProject: true, media: [podcast], timelineItems: 6, selected: 0) == .timeline)
        #expect(BriefFit.state(hasProject: true, media: [clip], timelineItems: 4, selected: 0) == .timeline)
        #expect(BriefFit.state(hasProject: true, media: [clip], timelineItems: 4, selected: 2) == .selection)
        #expect(BriefFit.state(hasProject: true, media: [podcast], timelineItems: 1, selected: 1) == .selection)

        let color = BriefCatalog.template("color")
        #expect(color?.fits(.timeline) == true && color?.fits(.selection) == true && color?.fits(.footage) == false)
        #expect(BriefCatalog.template("fix")?.fits(.timeline) == false)
    }

    @Test("Filling a template: defaults, chosen values, and holes for empty text fields")
    func filling() throws {
        let vlog = try #require(BriefCatalog.template("vlog"))
        #expect(vlog.prompt() == "Make a vlog about a workday in Saigon, about 60 s long, with a chill feel, told with captions.")
        #expect(vlog.prompt(["topic": "Hue", "length": "8 min", "mood": "  "])
            == "Make a vlog about Hue, about 8 min long, with a ‹mood› feel, told with captions.")
        let short = try #require(BriefCatalog.template("short"))
        let text = short.prompt()
        #expect(text.hasPrefix("Make a 30 s vertical video about ‹topic› for TikTok"))
        let hole = try #require(BriefText.firstHole(in: text))
        #expect(text[hole] == "‹topic›")
        #expect(BriefText.firstHole(in: "No blanks") == nil)
    }

    @Test("Search ignores case and Vietnamese accents; matches come by group, fitting first")
    func search() throws {
        #expect(BriefText.normalize("Dịch phụ đề") == "dich phu de")
        #expect(BriefText.normalize("ĐÀ LẠT") == "da lat")
        let translate = BriefTemplate(
            id: "x", group: .finish, systemImage: "globe", titleKey: "Dịch phụ đề", detailKey: "Thêm một track ngôn ngữ",
            recipe: "captions-text", fits: [.timeline], fields: [], patternKey: "")
        #expect(BriefText.matches("dich", translate) && BriefText.matches("DICH phu", translate))
        #expect(BriefText.matches("ngon ngu", translate) && !BriefText.matches("vlog", translate))

        let sections = BriefCatalog.sections(for: .talk, query: "caption")
        #expect(sections.map(\.group) == [.make, .finish])
        let finish = try #require(sections.last?.templates.map(\.id))
        #expect(finish.first == "captions" && finish.contains("translate"))
        #expect(BriefCatalog.sections(for: .footage, query: "zzz").isEmpty)
        let make = try #require(BriefCatalog.sections(for: .talk).first?.templates)
        let firstMiss = make.firstIndex { !$0.fits(.talk) } ?? make.count
        #expect(make[..<firstMiss].allSatisfy { $0.fits(.talk) } && make[firstMiss...].allSatisfy { !$0.fits(.talk) })
    }

    @Test("Recent briefs: newest first, no repeats, five kept, stored with the project")
    func history() throws {
        var list: [BriefRecord] = []
        for index in 1...7 { list = BriefHistory.adding(BriefRecord(title: "b\(index)", prompt: "p\(index)"), to: list) }
        #expect(list.map(\.title) == ["b7", "b6", "b5", "b4", "b3"])
        list = BriefHistory.adding(BriefRecord(title: "again", prompt: " p5 "), to: list)
        #expect(list.map(\.title) == ["again", "b7", "b6", "b4", "b3"])

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("brief-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(BriefHistory.loadRecent(project: folder).isEmpty)
        try BriefHistory.saveRecent(list, project: folder)
        #expect(BriefHistory.loadRecent(project: folder).map(\.prompt) == list.map(\.prompt))

        let suite = "brief-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = [BriefRecord(title: "My TikTok", prompt: "Make a 30 s video", templateID: "short")]
        BriefHistory.storeSaved(saved, defaults)
        #expect(BriefHistory.loadSaved(defaults).first?.templateID == "short")
    }

    /// key → language → value, from the app's string catalog.
    static func xcstrings() throws -> [String: [String: String]] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("BashCut/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = json?["strings"] as? [String: [String: Any]] ?? [:]
        return strings.mapValues { entry in
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            return localizations.compactMapValues { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
        }
    }
}
