import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

/// Structured licences and provenance (P2-H8).
@Suite("Licensing")
struct LicensingTests {
    @Test("Free licence text maps to an id and version and keeps the text")
    func parse() {
        let cases: [(String, LicenseTerms.Identifier, String?)] = [
            ("CC0", .cc0, nil), ("CC0 1.0 Universal", .cc0, "1.0"), ("Public Domain", .publicDomain, nil),
            ("CC-BY 4.0", .ccBy, "4.0"), ("Creative Commons Attribution 3.0", .ccBy, "3.0"),
            ("CC BY-SA 4.0", .ccBySa, "4.0"), ("CC BY-NC 4.0", .ccByNc, "4.0"), ("cc-by-nc-sa", .ccByNcSa, nil),
            ("CC BY-ND 2.0", .ccByNd, "2.0"), ("Attribution-NonCommercial-NoDerivatives 4.0", .ccByNcNd, "4.0"),
            ("Pexels License", .royaltyFree, nil), ("Royalty-free", .royaltyFree, nil), ("own", .own, nil),
            ("All rights reserved", .allRightsReserved, nil), ("© 2026 Studio", .allRightsReserved, nil),
            ("", .unknown, nil), ("Ask the band first", .custom, nil),
        ]
        for (text, id, version) in cases {
            let terms = LicenseTerms.parse(text)
            #expect(terms.id == id, "\(text)")
            #expect(terms.version == version, "\(text)")
            if id != .unknown { #expect(terms.text == text.trimmingCharacters(in: .whitespaces)) }
        }
    }

    @Test("What a licence allows follows from its id; unreadable terms are unknown, not allowed")
    func facts() {
        #expect(LicenseTerms(id: .ccByNc).facts.commercial == false)
        #expect(LicenseTerms(id: .ccBySa).facts.shareAlike == true)
        #expect(LicenseTerms(id: .ccBy).facts.attributionRequired == true)
        #expect(LicenseTerms(id: .royaltyFree).facts.redistribute == false)
        #expect(LicenseTerms(id: .cc0).facts.redistribute == true)
        #expect(LicenseTerms(id: .custom, text: "x").facts.redistribute == nil)
        #expect(LicenseTerms(id: .ccBy, version: "4.0").displayName == "CC-BY 4.0")
        #expect(LicenseTerms.parse("CC-BY 4.0").reportJSON.object["facts"]?.object["commercial"] == .bool(true))
    }

    @Test("Stored licences read as text or object; anything else is refused")
    func storage() throws {
        let object = LicenseTerms(id: .ccBy, version: "4.0", attribution: "Photo by A").json
        #expect(LicenseTerms(json: object)?.attribution == "Photo by A")
        #expect(LicenseTerms(json: .string("CC0"))?.id == .cc0)
        try LicenseTerms.validate(object, label: "x")
        try LicenseTerms.validate(.string("CC0"), label: "x")
        #expect(throws: ProjectError.self) { try LicenseTerms.validate(.object(["id": .string("gpl")]), label: "x") }
        #expect(throws: ProjectError.self) { try LicenseTerms.validate(.integer(3), label: "x") }
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
        let license = LicenseTerms.parse("CC-BY 4.0").json
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
        stock.fields["license"] = .string("Pixabay License")
        var free = LibraryItem(id: "free", kind: .audio, name: "Free", scope: .project)
        free.fields["license"] = LicenseTerms.parse("CC0").json
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
