import AVFoundation
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutEngine

/// Saving a trimmed audio clip to the library writes only the part it plays.
struct AudioRangeWriterTests {
    @Test("A PCM file's range is written as WAV at its length; a compressed one as M4A")
    func writesRange() throws {
        let folder = try TestFixtures.temporaryDirectory("audio-range")
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("tone.wav")
        try TestFixtures.writeTone(to: source, seconds: 4, channels: 2)
        #expect(try AudioRangeWriter.outputExtension(for: source) == "wav")
        let part = folder.appendingPathComponent("part.wav")
        let seconds = try AudioRangeWriter.write(source: source, range: 1...2.5, to: part)
        #expect(abs(seconds - 1.5) < 0.001)
        let written = try AVAudioFile(forReading: part)
        #expect(written.processingFormat.channelCount == 2)
        #expect(abs(Double(written.length) / written.processingFormat.sampleRate - 1.5) < 0.001)
        // Past the end, only what the file holds.
        #expect(abs(try AudioRangeWriter.write(source: source, range: 3...9, to: part) - 1) < 0.001)
        #expect(throws: (any Error).self) { try AudioRangeWriter.write(source: source, range: 5...6, to: part) }

        let compressed = folder.appendingPathComponent("tone.m4a")
        try AudioRangeWriter.write(source: source, range: 0...4, to: compressed)
        #expect(try AudioRangeWriter.outputExtension(for: compressed) == "m4a")
        let aac = folder.appendingPathComponent("part.m4a")
        try AudioRangeWriter.write(source: compressed, range: 0.5...1.5, to: aac)
        let read = try AVAudioFile(forReading: aac)
        #expect(abs(Double(read.length) / read.processingFormat.sampleRate - 1) < 0.1)
    }
}
