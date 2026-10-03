import BashCutAudioAnalysis
import Foundation
import Testing

@Suite("Core audio analysis")
struct AudioAnalysisTests {
    private func sine(amplitude: Float, seconds: Double, frequency: Double = 997, rate: Double = 48_000) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    @Test("A −20 dBFS 1 kHz sine measures about −23 LUFS and −20 dBTP")
    func sineLoudness() throws {
        let result = try LoudnessMeter.measure([sine(amplitude: 0.1, seconds: 5)])
        #expect(abs(result.integratedLUFS - -23.0) < 0.2)
        #expect(abs(result.truePeakDbTP - -20.0) < 0.2)
        #expect((result.loudnessRangeLU ?? 99) < 0.5)
        // Stereo doubles the power: +3 LU.
        let stereo = try LoudnessMeter.measure([sine(amplitude: 0.1, seconds: 5), sine(amplitude: 0.1, seconds: 5)])
        #expect(abs(stereo.integratedLUFS - result.integratedLUFS - 3.01) < 0.1)
    }

    @Test("Loudness range spans the loud and quiet halves; silence is refused")
    func rangeAndSilence() throws {
        let mixed = sine(amplitude: 0.1, seconds: 10) + sine(amplitude: 0.0316, seconds: 10)
        let result = try LoudnessMeter.measure([mixed])
        #expect(abs((result.loudnessRangeLU ?? 0) - 10) < 1)
        #expect(throws: AnalysisError.self) { try LoudnessMeter.measure([[Float](repeating: 0, count: 48_000)]) }
    }

    @Test("True peak sees an inter-sample peak the samples miss")
    func interSamplePeak() throws {
        // A quarter-rate sine sampled at ±45° never hits its crest: samples read −3 dB, the wave is at 0 dB.
        let samples = (0..<48_000).map { Float(sin(.pi / 2 * Double($0) + .pi / 4)) }
        let result = try LoudnessMeter.measure([samples])
        #expect(result.truePeakDbTP > -1)
    }

    private func clicks(bpm: Double, seconds: Double, offset: Double = 0.3, rate: Double = 22_050) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * rate))
        var time = offset
        while time < seconds {
            let start = Int(time * rate)
            for index in 0..<min(400, samples.count - start) {
                samples[start + index] = Float(sin(Double(index) * 0.6)) * Float(exp(-Double(index) / 80))
            }
            time += 60 / bpm
        }
        return samples
    }

    @Test("A click track's tempo and beats are found", arguments: [90.0, 120.0, 140.0])
    func clickTrack(bpm: Double) throws {
        let result = try BeatTracker.track(clicks(bpm: bpm, seconds: 20))
        #expect(abs(result.bpm - bpm) < 0.5)
        let first = try #require(result.beatsSeconds.first)
        #expect(abs(first - 0.3) < 0.05)
        let gaps = zip(result.beatsSeconds, result.beatsSeconds.dropFirst()).map { $1 - $0 }
        #expect(gaps.allSatisfy { abs($0 - 60 / bpm) < 0.05 })
        #expect(zip(result.beatsSeconds, result.beatsSeconds.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("Silence has no beats")
    func silentBeats() {
        #expect(throws: AnalysisError.self) { try BeatTracker.track([Float](repeating: 0, count: 22_050 * 5)) }
    }
}
