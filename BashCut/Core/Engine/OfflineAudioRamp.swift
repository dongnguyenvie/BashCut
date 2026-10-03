@preconcurrency import AVFoundation
import BashCutProject

/// Render one continuous stream. Pitch preservation uses WSOLA; varispeed keeps native resampling state across the curve.
enum OfflineAudioRamp {
    static func render(input url: URL, output: URL, curve: SpeedCurve, seconds: Double, preservesPitch: Bool) throws {
        if preservesPitch {
            try WaveformAudioRamp.render(input: url, output: output, curve: curve, seconds: seconds)
            return
        }
        let input = try AVAudioFile(forReading: url)
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        let first = AVAudioUnitVarispeed(), second = AVAudioUnitVarispeed()
        engine.attach(player)
        // Each varispeed unit supports 0.25...4; two square-root rates cover the project's 0.1...16 range.
        engine.attach(first)
        engine.attach(second)
        engine.connect(player, to: first, format: input.processingFormat)
        engine.connect(first, to: second, format: input.processingFormat)
        engine.connect(second, to: engine.mainMixerNode, format: input.processingFormat)
        try engine.enableManualRenderingMode(.offline, format: input.processingFormat, maximumFrameCount: 256)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 256) else {
            throw ProjectError.invalid("Could not allocate ramp audio buffer")
        }
        let file = try AVAudioFile(forWriting: output, settings: input.processingFormat.settings)
        player.scheduleFile(input, at: nil)
        try engine.start()
        player.play()
        defer { engine.stop() }
        let count = Int(ceil(seconds * input.processingFormat.sampleRate))
        var written = 0, retries = 0
        while written < count {
            try Task.checkCancellation()
            let frames = min(256, count - written)
            let fraction = (Double(written) + Double(frames) / 2) / (seconds * input.processingFormat.sampleRate)
            let rate = Float(curve.speed(at: fraction))
            first.rate = sqrt(rate)
            second.rate = sqrt(rate)
            let status = try engine.renderOffline(AVAudioFrameCount(frames), to: buffer)
            if status == .cannotDoInCurrentContext, retries < 16 { retries += 1; continue }
            guard status == .success, buffer.frameLength > 0 else {
                throw ProjectError.invalid("Could not render ramp audio (status \(status.rawValue))")
            }
            retries = 0
            try file.write(from: buffer)
            written += Int(buffer.frameLength)
        }
    }
}
