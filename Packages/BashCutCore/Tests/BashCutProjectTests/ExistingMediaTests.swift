import BashCutProjectFixtures
import Testing
@testable import BashCutProject

struct ExistingMediaTests {
    @Test("Importing a file already in the project finds its media only while the file is unchanged")
    func existingMedia() throws {
        let project = try ProjectFixtures.twoClips()
        let stored = try #require(project.media.first)
        var again = stored
        again.fields["id"] = .string("new")
        #expect(project.existingMedia(like: again)?.id == stored.id)
        var longer = again
        longer.fields["frames"] = .integer((stored.fields["frames"]?.int ?? 0) + 30)
        #expect(project.existingMedia(like: longer) == nil)
        var elsewhere = again
        elsewhere.fields["path"] = .string("footage/other.mov")
        #expect(project.existingMedia(like: elsewhere) == nil)
    }
}
