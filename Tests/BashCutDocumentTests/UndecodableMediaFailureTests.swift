import BashCutAutomation
import BashCutDocument
import BashCutEngine
import Testing

struct UndecodableMediaFailureTests {
    @Test("Undecodable media is invalid arguments with category unsupported_media, the media and a conversion hint")
    func typed() {
        let media = UndecodableMedia(mediaID: "m1", path: "footage/trail.mp4", codec: "vp09", start: 30, end: 90)
        let failure = RPCFailure.from(UndecodableMediaError([media])).typed
        #expect(failure.code == -32602 && failure.category == .unsupportedMedia)
        #expect(failure.message.contains("trail.mp4 (vp09)"))
        let data = failure.data?.object ?? [:]
        #expect(data["retryable"] == .bool(false))
        #expect(data["remediation"]?.object["command"] == .string("media.inventory"))
        let first = data["media"]?.array.first?.object ?? [:]
        #expect(first["media"] == .string("m1") && first["codec"] == .string("vp09"))
        #expect(first["start"] == .integer(30) && first["end"] == .integer(90))
    }
}
