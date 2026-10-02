import AVFoundation
import BashCutProject

extension FrameRate {
    public func time(_ frame: Int) -> CMTime {
        CMTime(value: Int64(frame) * Int64(denominator), timescale: Int32(numerator))
    }
    public func frame(_ time: CMTime) -> Int {
        Int(
            CMTimeConvertScale(time, timescale: Int32(numerator), method: .roundHalfAwayFromZero).value
                / Int64(denominator))
    }
}
