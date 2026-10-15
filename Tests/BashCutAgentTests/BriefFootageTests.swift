import BashCutAgent
import Foundation
import Testing

struct BriefFootageTests {
    @Test("Videos made from footage need it; explainers take it optionally; timeline edits do not ask")
    func need() {
        #expect(BriefFootage.need("travel") == .main)
        #expect(BriefFootage.need("clips") == .main)
        #expect(BriefFootage.need("explainer") == .optional)
        #expect(BriefFootage.need(nil) == .optional)
        #expect(BriefFootage.need("captions") == BriefFootage.Need.none)
    }

    @Test("A folder counts its media files, skipping hidden ones; a file is one item")
    func items() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("brief-footage-\(UUID().uuidString)")
        let day = folder.appendingPathComponent("day 1")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["a.mp4", "b.MOV", "day 1/c.jpg", "day 1/voice.m4a", "notes.txt", ".hidden.mp4"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let item = try #require(BriefFootage.item(folder))
        #expect(item.isFolder && item.mediaFiles == 4)
        #expect(item.name == folder.lastPathComponent + "/")

        let file = try #require(BriefFootage.item(folder.appendingPathComponent("a.mp4")))
        #expect(!file.isFolder && file.mediaFiles == 1)
        #expect(BriefFootage.item(folder.appendingPathComponent("missing.mp4")) == nil)
        #expect(BriefFootage.adding([file, item], to: [item]) == [item, file])
    }

    @Test("The request ends with one line naming each path, with ~ for the home folder")
    func line() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let items = [
            BriefFootage.Item(url: home.appendingPathComponent("trip"), isFolder: true, mediaFiles: 42),
            BriefFootage.Item(url: URL(fileURLWithPath: "/Volumes/SD/hook.mp4"), isFolder: false, mediaFiles: 1),
        ]
        #expect(BriefFootage.request("Make a travel vlog.", items: items)
            == "Make a travel vlog.\nFootage to import: `~/trip/` (folder, 42 media files), `/Volumes/SD/hook.mp4`")
        #expect(BriefFootage.request("Make a travel vlog.", items: []) == "Make a travel vlog.")
    }

    @Test("Recent briefs from older builds, without footage, still load")
    func olderRecords() throws {
        let json = #"{"id":"1EBA7FD0-637E-42E2-B819-78F3D4035A19","title":"T","prompt":"P","date":0}"#
        let record = try JSONDecoder().decode(BriefRecord.self, from: Data(json.utf8))
        #expect(record.footage == nil && record.prompt == "P")
    }
}
