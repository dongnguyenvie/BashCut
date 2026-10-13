import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

/// The review's picture and loudness measurements were session-only: lost when the app restarted.
struct ReviewMeasurementStoreTests {
    @Test("Measurements come back for the same content at another revision, not after an edit")
    func roundTrip() throws {
        let root = try TestFixtures.temporaryDirectory("review-measurements")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Self.project(root: root)
        var picture = ReviewPicture(
            revision: project.revision, interval: 15,
            samples: [.init(frame: 0, luma: 0.4, spread: 0.1, change: 1, peak: 1),
                      .init(frame: 15, luma: 0.41, spread: 0.12, change: 0.01, peak: 0.05)],
            cuts: ["b": 0.3])
        picture.textContrast = ["t": .init(ratio: 4.5, frame: 12)]
        let loudness = ReviewLoudness(
            revision: project.revision, integratedLUFS: -14.2, truePeakDbTP: -1.6, loudnessRangeLU: 5,
            targetLUFS: -14, maxTruePeakDbTP: -1, preset: "tiktok")
        try ReviewMeasurementStore.store(picture, for: project, projectRoot: root)
        try ReviewMeasurementStore.store(loudness, for: project, projectRoot: root)

        // A restart: the same content, read again (the revision number may differ, e.g. after undo and redo).
        var reopened = project
        reopened.revision = project.revision + 7
        let stored = ReviewMeasurementStore.load(for: reopened, projectRoot: root)
        let restored = try #require(stored.picture)
        #expect(restored.revision == reopened.revision)
        #expect(restored.samples == picture.samples)
        #expect(restored.cuts == picture.cuts)
        #expect(restored.interval == 15)
        #expect(restored.textContrast == picture.textContrast)
        let sound = try #require(stored.loudness)
        #expect(sound.revision == reopened.revision)
        #expect(sound.integratedLUFS == -14.2 && sound.truePeakDbTP == -1.6 && sound.preset == "tiktok")

        // Any edit is other content: nothing is found.
        let edited = try project.applying(.move(item: "a", toTrack: "v1", atFrame: 3)).project
        let none = ReviewMeasurementStore.load(for: edited, projectRoot: root)
        #expect(none.picture == nil && none.loudness == nil)
    }

    @Test("Plugin review.check issues come back for the same content with their fix, facts and source")
    func pluginIssues() throws {
        let root = try TestFixtures.temporaryDirectory("review-measurements")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Self.project(root: root)
        let issue = ReviewIssue(
            id: "brand.check:logo-0", title: "Logo missing", detail: "No logo in the first 3 s", frame: 0, endFrame: 90,
            severity: .error, fix: ReviewFix(command: "library.place", arguments: ["id": .string("logo")], hint: "Add it"),
            source: "com.example.brand", facts: ["seconds": .number(3.5)])
        try ReviewMeasurementStore.store(pluginIssues: [issue], for: project, projectRoot: root)
        var reopened = project
        reopened.revision += 3
        let stored = try #require(ReviewMeasurementStore.load(for: reopened, projectRoot: root).pluginIssues)
        #expect(stored.revision == reopened.revision && stored.issues.count == 1)
        let back = try #require(stored.issues.first)
        #expect(back.json == issue.json)
        try ReviewMeasurementStore.store(pluginIssues: [], for: project, projectRoot: root)
        #expect(ReviewMeasurementStore.load(for: project, projectRoot: root).pluginIssues?.issues.isEmpty == true)
        let edited = try project.applying(.move(item: "a", toTrack: "v1", atFrame: 3)).project
        #expect(ReviewMeasurementStore.load(for: edited, projectRoot: root).pluginIssues == nil)
    }

    @Test("A media file changed on disk makes the stored measurements stale")
    func mediaChange() throws {
        let root = try TestFixtures.temporaryDirectory("review-measurements")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Self.project(root: root)
        try ReviewMeasurementStore.store(
            ReviewPicture(revision: 1, interval: 10, samples: [], cuts: [:]), for: project, projectRoot: root)
        #expect(ReviewMeasurementStore.load(for: project, projectRoot: root).picture != nil)
        try Data(repeating: 2, count: 65).write(to: root.appendingPathComponent("clip.mov"))
        #expect(ReviewMeasurementStore.load(for: project, projectRoot: root).picture == nil)
    }

    @Test("A record that does not decode is ignored, and old records are pruned")
    func corruptAndPrune() throws {
        let root = try TestFixtures.temporaryDirectory("review-measurements")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try Self.project(root: root)
        let key = ReviewMeasurementStore.key(for: project, projectRoot: root)
        let folder = ProjectCache.url(.reviewMeasurements, projectRoot: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{\"version\": 1}".utf8).write(to: folder.appendingPathComponent(key + "-picture.json"))
        #expect(ReviewMeasurementStore.load(for: project, projectRoot: root).picture == nil)

        var current = project
        for step in 0..<(ReviewMeasurementStore.limit + 5) {
            current = try current.applying(.move(item: "a", toTrack: "v1", atFrame: step + 1)).project
            try ReviewMeasurementStore.store(
                ReviewPicture(revision: current.revision, interval: 10, samples: [], cuts: [:]), for: current,
                projectRoot: root)
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.count <= ReviewMeasurementStore.limit)
        #expect(ReviewMeasurementStore.load(for: current, projectRoot: root).picture != nil)
    }

    private static func project(root: URL) throws -> Project {
        try Data(repeating: 1, count: 64).write(to: root.appendingPathComponent("clip.mov"))
        let media = Media(fields: [
            "id": .string("m"), "path": .string("clip.mov"), "kind": .string("video"), "fps": FrameRate().json,
            "frames": .integer(300), "hasAudio": .bool(true),
        ])
        return try Project(name: "Measured").applying(
            .group(label: "Fixture", author: .user, ops: [
                .addMedia(media), .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: 60)),
            ])).project
    }
}
