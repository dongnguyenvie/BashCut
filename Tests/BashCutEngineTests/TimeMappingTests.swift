import AVFoundation
import BashCutProject
import Testing

@testable import BashCutEngine

struct TimeMappingTests {
    @Test("29.97 frame conversion does not accumulate drift")
    func mapping() {
        let fps = FrameRate()
        for frame in [0, 1, 61, 3291, 107892, 1_000_000] {
            #expect(fps.frame(fps.time(frame)) == frame)
            #expect(fps.time(frame).value == Int64(frame) * 1001)
            #expect(fps.time(frame).timescale == 30000)
        }
    }
}
