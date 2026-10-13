import BashCutDocument
import BashCutProject
import Foundation
import Testing

struct RecentProjectTests {
    private func project(_ path: String, name: String? = nil) -> RecentProject {
        RecentProject(url: URL(fileURLWithPath: path + "/project.bashcut.json"), name: name)
    }

    @Test("Same-named projects get their parent folders in the menu, only as many as tell them apart (#529)")
    func menuTitles() {
        let projects = [
            project("/bench/graphics-bench/b2/project"), project("/bench/lessons/lesson1/project"),
            project("/a/run/project"), project("/b/run/project"), project("/films/Trip"),
            project("/films/other", name: "Trip"), project("/project"), project("/films/Holiday", name: "Đà Lạt"),
        ]
        #expect(RecentProject.menuTitles(projects) == [
            "project — b2", "project — lesson1", "project — a/run", "project — b/run", "Trip — films", "Trip — films",
            "project", "Đà Lạt",
        ])
        #expect(RecentProject.menuTitles([project("/a/project"), project("/b/cut")]) == ["project", "cut"])
    }

    @Test("Search finds words in the name or path, letters in order, ignoring case and marks; title matches first")
    func filter() {
        let projects = [
            project("/bench/graphics-bench/b2/project"), project("/bench/lessons/lesson1/project"),
            project("/films/Holiday", name: "Đà Lạt trip"), project("/films/project-notes"),
        ]
        func folders(_ query: String) -> [String] {
            RecentProject.filter(projects, query: query).map(\.folder.path)
        }
        #expect(RecentProject.filter(projects, query: "  ") == projects)
        #expect(folders("lesson") == ["/bench/lessons/lesson1/project"])
        #expect(folders("GRAPHICS b2") == ["/bench/graphics-bench/b2/project"])
        #expect(folders("gbb2") == ["/bench/graphics-bench/b2/project"])
        #expect(folders("da lat") == ["/films/Holiday"])
        #expect(folders("notes") == ["/films/project-notes"])
        // A title starting with the query, then a match as written, then letters in between.
        #expect(folders("project")
            == ["/bench/graphics-bench/b2/project", "/bench/lessons/lesson1/project", "/films/project-notes"])
        #expect(folders("trip") == ["/films/Holiday", "/bench/graphics-bench/b2/project"])
        #expect(folders("zzz").isEmpty)
    }

    @Test("Rows carry name, path, lastOpened and whether the file exists; paths shorten under home")
    func rows() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("recents-\(UUID().uuidString)/cut")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let file = folder.appendingPathComponent("project.bashcut.json")
        try Data("{}".utf8).write(to: file)

        let present = RecentProject(url: file, lastOpened: Date(timeIntervalSince1970: 0))
        #expect(present.exists)
        #expect(present.json.object["name"]?.string == "cut")
        #expect(present.json.object["lastOpened"]?.string == "1970-01-01T00:00:00Z")
        let missing = project(folder.path + "/gone", name: "Gone")
        #expect(!missing.exists)
        #expect(missing.json.object["exists"] == .bool(false))
        #expect(missing.json.object["lastOpened"] == .null)
        #expect(missing.json.object["name"]?.string == "Gone")

        #expect(project("/Users/me/Movies/BashCut/graphics-bench/b2").shortPath(home: "/Users/me")
            == "~/…/graphics-bench/b2")
        #expect(project("/Users/me/Movies/b2").shortPath(home: "/Users/me") == "~/Movies/b2")
        let loose = RecentProject(url: URL(fileURLWithPath: "/films/trip.json"))
        #expect(loose.title == "trip")
    }
}
