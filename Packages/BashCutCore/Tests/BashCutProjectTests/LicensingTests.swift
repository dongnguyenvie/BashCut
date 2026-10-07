import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

/// Structured licences and provenance (P2-H8).
@Suite("Licensing")
struct LicensingTests {
    @Test("Licences are free text or an open object; facts are the item's own")
    func storage() throws {
        let object: JSONValue = .object(["id": .string("gpl"), "version": .string("3"), "attribution": .string("Photo by A"),
                                         "redistribute": .bool(false), "custom": .integer(1)])
        let terms = try #require(LicenseTerms(json: object))
        #expect(terms.attribution == "Photo by A" && terms.facts.redistribute == false && terms.facts.commercial == nil)
        #expect(terms.json == object && terms.displayName == "gpl 3")
        #expect(LicenseTerms(json: .string("CC0"))?.text == "CC0" && LicenseTerms(json: .string("CC0"))?.id == nil)
        try LicenseTerms.validate(object, label: "x")
        try LicenseTerms.validate(.string("CC0"), label: "x")
        #expect(throws: ProjectError.self) { try LicenseTerms.validate(.object(["redistribute": .string("no")]), label: "x") }
        #expect(throws: ProjectError.self) { try LicenseTerms.validate(.integer(3), label: "x") }
        #expect(LicenseTerms.argument("{\"id\":\"cc-by\"}") == .object(["id": .string("cc-by")]))
        #expect(LicenseTerms.argument("CC-BY 4.0") == .string("CC-BY 4.0"))
    }

    @Test("Provenance checks origin, text fields, seed and charged; unknown fields pass")
    func provenance() throws {
        try Provenance.validate(.object([
            "origin": .string("ai"), "provider": .string("acme"), "seed": .integer(42), "charged": .number(0.12),
            "requestId": .string("r1"), "custom": .bool(true),
        ]), label: "x")
        for bad: [String: JSONValue] in [
            ["origin": .string("found")], ["charged": .number(-1)], ["seed": .bool(true)], ["prompt": .integer(1)],
        ] {
            #expect(throws: ProjectError.self) { try Provenance.validate(.object(bad), label: "x") }
        }
        #expect(Provenance.from(origin: nil, sourceUrl: nil, author: nil) == nil)
        #expect(Provenance.from(origin: "stock", sourceUrl: "https://a", author: "B")?.object["author"] == .string("B"))
    }

    @Test("setMediaRights sets, keeps and removes rights, round-trips as JSON and is validated with the project")
    func mediaRights() throws {
        let base = try Project(name: "Rights", fps: FrameRate(30, 1)).applying(.addMedia(
            ProjectFixtures.media("m", path: "m.mov", frames: 60, fps: FrameRate(30, 1), kind: "video", hasAudio: true))).project
        let license: JSONValue = .string("CC-BY 4.0")
        let set = EditOperation.setMediaRights(media: "m", license: license, provenance: .object(["origin": .string("stock")]))
        var project = try base.applying(set).project
        #expect(project.media[0]["license"] == license && project.media[0]["provenance"]?.object["origin"] == .string("stock"))
        project = try project.applying(.setMediaRights(media: "m", license: .null, provenance: nil)).project
        #expect(project.media[0]["license"] == nil && project.media[0]["provenance"] != nil)
        let decoded = try JSONDecoder().decode(EditOperation.self, from: JSONEncoder().encode(set))
        #expect(decoded == set)
        #expect(throws: ProjectError.self) {
            try base.applying(.setMediaRights(media: "m", license: nil, provenance: .object(["origin": .string("x")])))
        }
        // Rights do not stop the same file being reused.
        var candidate = base.media[0]
        candidate.fields["id"] = .string("other")
        candidate.fields["license"] = license
        #expect(base.existingMedia(like: candidate)?.id == "m")
    }

    @Test("A pack export refuses items whose licence forbids redistribution and lists unknown ones")
    func packExport() throws {
        var stock = LibraryItem(id: "stock", kind: .audio, name: "Stock", scope: .project)
        stock.fields["license"] = .object(["text": .string("Pixabay License"), "redistribute": .bool(false)])
        var free = LibraryItem(id: "free", kind: .audio, name: "Free", scope: .project)
        free.fields["license"] = .object(["id": .string("cc0"), "redistribute": .bool(true)])
        let bare = LibraryItem(id: "bare", kind: .audio, name: "Bare", scope: .project)
        let builtIn = LibraryItem(id: "kit", kind: .textPreset, name: "Kit")
        #expect(LibraryPack.redistributionRefusals([stock, free, bare]).map(\.item) == ["stock"])
        #expect(LibraryPack.unknownLicenses([stock, free, bare, builtIn]) == ["bare"])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pack-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: ProjectError.self) {
            try LibraryPack.export([stock, free], name: "P", catalog: LibraryCatalog(user: nil, project: nil), to: folder)
        }
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
