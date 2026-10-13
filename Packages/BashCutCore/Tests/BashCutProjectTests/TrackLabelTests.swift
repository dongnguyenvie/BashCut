import Foundation
import Testing

@testable import BashCutProject

@Suite("Short layer labels (V1, A1)")
struct TrackLabelTests {
    @Test("Visual layers count from the back, audio layers from the top, and labels follow layer moves")
    func derivation() throws {
        let project = Project(name: "Labels")
        let visual = project.tracks.filter(\.isVisual)
        let audio = project.tracks.filter { !$0.isVisual }
        #expect(!visual.isEmpty && !audio.isEmpty)
        let labels = project.trackLabels
        #expect(visual.enumerated().allSatisfy { labels[$1.id] == "V\($0 + 1)" })
        #expect(audio.enumerated().allSatisfy { labels[$1.id] == "A\($0 + 1)" })
        #expect(Set(labels.values).count == project.tracks.count)
        let main = try #require(project.tracks.first { $0.role == TrackRole.main })
        #expect(project.trackTitle(main) == "\(labels[main.id]!) · \(main.name)")

        // A new layer in front of the others takes the next label; nothing is stored.
        let added = try project.applying(
            .addTrack(track: Track(id: "top", kind: "text", role: TrackRole.captions), atIndex: visual.count)
        ).project
        #expect(added.trackLabel("top") == "V\(visual.count + 1)")
        #expect(added.track(id: "top")?.fields["label"] == nil)
    }

    @Test("A track argument accepts the label in any case, and an ID always wins")
    func resolution() throws {
        let project = Project(name: "Labels")
        let firstAudio = try #require(project.tracks.first { !$0.isVisual })
        let firstVisual = try #require(project.tracks.first)
        #expect(project.resolveTrackReference("A1") == firstAudio.id)
        #expect(project.resolveTrackReference("v1") == firstVisual.id)
        #expect(project.resolveTrackReference(firstAudio.id) == firstAudio.id)
        #expect(project.resolveTrackReference("V99") == "V99")
        #expect(project.resolveTrackReference("nope") == "nope")

        // A layer whose ID looks like a label keeps that ID.
        let named = try project.applying(
            .addTrack(track: Track(id: "A1", kind: "text", role: TrackRole.captions), atIndex: 1)
        ).project
        #expect(named.resolveTrackReference("A1") == "A1")
    }
}
