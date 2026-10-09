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

    @Test("The curve follows the sound every 100 ms; silence is allowed when asked")
    func curve() throws {
        let sound = [Float](repeating: 0, count: 48_000) + sine(amplitude: 0.1, seconds: 4)
        let curve = LoudnessMeter.curve([sound])
        #expect(curve.momentary.count == 47 && curve.peakDb.count == 50)
        #expect(curve.momentary[0] == -100 && curve.peakDb[5] == -100)
        #expect(abs(curve.momentary[20] - -23) < 0.3)
        #expect(abs(curve.peakDb[30] - -20) < 0.2)
        #expect(abs((curve.shortTerm.last ?? 0) - -23) < 0.3)
        let silent = try LoudnessMeter.measure([[Float](repeating: 0, count: 48_000)], allowSilence: true)
        #expect(silent.integratedLUFS == -100)
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

    @Test("Grid v2: strengths, downbeats on the kick, a tight fit, and half and double alternates")
    func gridFacts() throws {
        let rate = 22_050.0, period = 0.5
        var samples = clicks(bpm: 120, seconds: 20)
        // A 60 Hz kick on every fourth beat, starting with the second one (index 1).
        var time = 0.3 + period
        while time < 20 {
            let start = Int(time * rate)
            for index in 0..<min(2_000, samples.count - start) {
                samples[start + index] += 0.8 * Float(sin(2 * .pi * 60 * Double(index) / rate)) * Float(exp(-Double(index) / 600))
            }
            time += period * 4
        }
        let (result, grid) = try BeatTracker.trackGrid(samples)
        #expect(grid.strengths.count == result.beatsSeconds.count && grid.strengths.allSatisfy { (0...1).contains($0) })
        #expect(grid.beatsPerBar == 4 && grid.phaseScores.max() == 1)
        let first = try #require(grid.downbeats.first)
        #expect(abs(first - 0.8) < 0.06, "\(grid.downbeats.prefix(3))")
        #expect(grid.rmsErrorMs < 15 && abs(grid.periodSeconds - period) < 0.01)
        #expect(grid.alternates.map(\.bpm) == [result.bpm / 2, result.bpm * 2])
        #expect(grid.tempoStrength > 0 && grid.tempoStrength <= 1)
    }

    @Test("Energy: level, onset and fullness per 100 ms; a lift where the music gets louder")
    func energy() throws {
        let rate = 22_050.0
        let quiet = clicks(bpm: 120, seconds: 8).map { $0 * 0.05 }
        let loud = clicks(bpm: 120, seconds: 8).enumerated().map { index, value in
            value + 0.3 * Float(sin(2 * .pi * 220 * Double(index) / rate))
        }
        let result = EnergyCurve.measure(quiet + loud, beats: [7.8, 8.3], count: 2)
        #expect(result.levelDb.count == 160 && result.onset.count == 160 && result.fullness.count == 160)
        let lift = try #require(result.candidates.first { $0.kind == "lift" })
        #expect(abs(lift.seconds - 8) < 0.3 && lift.magnitude > 10 && lift.beatSeconds == 7.8)
        #expect(result.candidates.filter { $0.kind == "lift" }.count <= 2)
    }

    @Test("Silence has no beats")
    func silentBeats() {
        #expect(throws: AnalysisError.self) { try BeatTracker.track([Float](repeating: 0, count: 22_050 * 5)) }
    }

    /// Speech-like sound at 8 kHz: noise bursts of random length and level, so every stretch has its own envelope.
    private func bursts(seconds: Double, seed: UInt64) -> [Float] {
        var state = seed
        func random() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        let rate = AudioSync.sampleRate
        var samples: [Float] = []
        samples.reserveCapacity(Int(seconds * rate))
        while Double(samples.count) < seconds * rate {
            let length = Int((0.08 + random() * 0.5) * rate)
            let level = random() < 0.3 ? 0.002 : 0.05 + random() * 0.4
            for _ in 0..<length { samples.append(Float((random() * 2 - 1) * level)) }
        }
        return Array(samples.prefix(Int(seconds * rate)))
    }

    @Test("Two recordings of one session are matched to their offset, with agreeing halves")
    func syncOffset() throws {
        let rate = AudioSync.sampleRate
        let session = bursts(seconds: 70, seed: 7)
        // The camera starts 3 s into the session, the screen recording 5.49 s in: screen = camera + (-2.49) ... and the
        // room mic adds its own noise.
        let camera = Array(session[Int(3 * rate)..<Int(63 * rate)])
        var noise: UInt64 = 99
        let screen = session[Int(5.49 * rate)...].map { sample -> Float in
            noise = noise &* 6_364_136_223_846_793_005 &+ 1
            return sample * 0.5 + Float(Double(noise >> 40) / Double(1 << 24) - 0.5) * 0.01
        }
        let result = try AudioSync.align(camera, screen)
        #expect(abs(result.match.offsetSeconds - -2.49) < 0.011)
        #expect(result.match.correlation > 0.8)
        #expect(result.isSteady)
        #expect(result.halves.count == 2)
    }

    @Test("A short render played inside a long screen recording is found where it starts")
    func syncInside() throws {
        let rate = AudioSync.sampleRate
        let screen = bursts(seconds: 90, seed: 3)
        let render = Array(screen[Int(41.2 * rate)..<Int(61.2 * rate)])
        let result = try AudioSync.align(screen, render)
        // Render time = screen time - 41.2.
        #expect(abs(result.match.offsetSeconds - -41.2) < 0.011)
        #expect(result.match.correlation > 0.95)
    }

    @Test("Unrelated recordings correlate weakly; too short ones are refused")
    func syncUnrelated() throws {
        let result = try AudioSync.align(bursts(seconds: 30, seed: 1), bursts(seconds: 30, seed: 2))
        #expect(result.match.correlation < 0.4)
        #expect(throws: AnalysisError.self) { try AudioSync.align(bursts(seconds: 2, seed: 1), bursts(seconds: 30, seed: 2)) }
    }

    @Test("Band shares put a 2 kHz tone in the presence band and a 100 Hz hum outside both")
    func bandShares() throws {
        let presence = try SpectralShare.measure([sine(amplitude: 0.1, seconds: 2, frequency: 2_000)])
        // 24 dB/octave edges: one octave inside an edge keeps (16/17)² of the power at each edge.
        #expect(presence.presence > 0.72 && presence.speech > 0.6)
        let hum = try SpectralShare.measure([sine(amplitude: 0.1, seconds: 2, frequency: 100)])
        #expect(hum.presence < 0.01 && hum.speech < 0.05)
        let low = try SpectralShare.measure([sine(amplitude: 0.1, seconds: 2, frequency: 500)])
        #expect(low.speech > 0.7 && low.presence < 0.01)
        #expect(throws: AnalysisError.self) { try SpectralShare.measure([[Float](repeating: 0, count: 4_800)]) }
    }
}
