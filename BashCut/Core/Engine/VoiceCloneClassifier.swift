@preconcurrency import AVFoundation
import Foundation
@preconcurrency import SoundAnalysis

/// Speech and music confidence (0–1) per `VoiceCloneTrimmer.frame` of a clone source (#532), from Apple's on-device
/// sound classifier.
public struct VoiceCloneClassification: Sendable, Equatable {
    public let speech: [Double]
    public let music: [Double]

    public init(speech: [Double], music: [Double]) {
        self.speech = speech
        self.music = music
    }
}

/// Runs `SNClassifySoundRequest` (version 1) over mono samples: 1 s windows overlapping by half, each window's
/// speech (speech, conversation, narration, monologue) and music confidence spread over the frames it covers (the
/// highest window wins). Nil when the classifier has no speech label.
public enum VoiceCloneClassifier {
    static let speechLabels: Set<String> = ["speech", "conversation", "narration", "monologue"]
    static let musicLabels: Set<String> = ["music"]

    public static func classify(_ samples: [Float], rate: Double) throws -> VoiceCloneClassification? {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        if case .durationRange(let range) = request.windowDurationConstraint,
            range.containsTime(CMTime(seconds: 1, preferredTimescale: 1_000))
        {
            request.windowDuration = CMTime(seconds: 1, preferredTimescale: 1_000)
        }
        request.overlapFactor = 0.5
        let known = Set(request.knownClassifications)
        let speech = speechLabels.intersection(known), music = musicLabels.intersection(known)
        guard !speech.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return nil }
        let frames = Int(Double(samples.count) / (rate * VoiceCloneTrimmer.frame))
        let observer = ClassificationObserver(frames: frames, speech: speech, music: music)
        let analyzer = SNAudioStreamAnalyzer(format: format)
        try analyzer.add(request, withObserver: observer)
        let chunk = 8_192
        for start in stride(from: 0, to: samples.count, by: chunk) {
            let count = min(chunk, samples.count - start)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                let channel = buffer.floatChannelData?[0]
            else { continue }
            samples.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                channel.update(from: base + start, count: count)
            }
            buffer.frameLength = AVAudioFrameCount(count)
            analyzer.analyze(buffer, atAudioFramePosition: AVAudioFramePosition(start))
        }
        analyzer.completeAnalysis()
        guard observer.done.wait(timeout: .now() + 60) == .success else { return nil }
        return try observer.result()
    }
}

/// Collects the classifier's results into per-frame confidences.
private final class ClassificationObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let speechLabels: Set<String>
    private let musicLabels: Set<String>
    private var speech: [Double]
    private var music: [Double]
    private var failure: (any Error)?

    init(frames: Int, speech: Set<String>, music: Set<String>) {
        (speechLabels, musicLabels) = (speech, music)
        self.speech = [Double](repeating: 0, count: max(0, frames))
        self.music = [Double](repeating: 0, count: max(0, frames))
    }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let confidence = { (labels: Set<String>) in
            labels.compactMap { result.classification(forIdentifier: $0)?.confidence }.max() ?? 0
        }
        let (speechValue, musicValue) = (confidence(speechLabels), confidence(musicLabels))
        let start = result.timeRange.start.seconds, end = start + result.timeRange.duration.seconds
        let frame = VoiceCloneTrimmer.frame
        lock.withLock {
            let first = max(0, Int(start / frame)), last = min(speech.count, Int((end / frame).rounded(.up)))
            guard first < last else { return }
            for index in first..<last {
                speech[index] = max(speech[index], speechValue)
                music[index] = max(music[index], musicValue)
            }
        }
    }

    func request(_ request: any SNRequest, didFailWithError error: any Error) {
        lock.withLock { failure = error }
        done.signal()
    }

    func requestDidComplete(_ request: any SNRequest) { done.signal() }

    func result() throws -> VoiceCloneClassification {
        try lock.withLock {
            if let failure { throw failure }
            return VoiceCloneClassification(speech: speech, music: music)
        }
    }
}
