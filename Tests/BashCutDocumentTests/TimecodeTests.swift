import BashCutDocument
import BashCutProject
import Testing

struct TimecodeTests {
    @Test("The transport label shows playhead and length as mm:ss:ff, like the timeline (P0 PR4)")
    func transportLabel() {
        let fps = FrameRate(30, 1)
        #expect(Timecode.transportLabel(position: 0, length: 50 * 30 + 15, fps: fps) == "00:00:00 / 00:50:15")
        #expect(Timecode.transportLabel(position: 45, length: 3600 * 30, fps: fps) == "00:01:15 / 1:00:00:00")
        #expect(Timecode.transportLabel(position: 12, length: 12, fps: fps) == Timecode.string(12, fps: fps) + " / 00:00:12")
    }
}
