import CoreGraphics
import Foundation
import Vision

/// What Apple Vision finds in one picture. Boxes are `[x, y, width, height]` as shares of the upright picture with
/// the origin at the top left; confidence is Vision's own (0…1). No labels and no judgement: which face matters,
/// whether text is a caption or a sign, is the agent's.
public enum VisionDetect {
    public struct Box: Sendable, Equatable {
        public let box: [Double]
        public let confidence: Double
    }

    public struct Line: Sendable, Equatable {
        public let string: String
        public let box: [Double]
        public let confidence: Double
    }

    /// Faces and people (whole bodies) in `image`.
    public static func subjects(_ image: CGImage) throws -> (faces: [Box], people: [Box]) {
        let faces = VNDetectFaceRectanglesRequest()
        let people = VNDetectHumanRectanglesRequest()
        people.upperBodyOnly = false
        try VNImageRequestHandler(cgImage: image).perform([faces, people])
        let boxes = { (observations: [VNDetectedObjectObservation]?) in
            (observations ?? []).map { Box(box: topLeft($0.boundingBox), confidence: rounded(Double($0.confidence))) }
                .sorted { $0.box[0] < $1.box[0] }
        }
        return (boxes(faces.results), boxes(people.results))
    }

    /// Lines of text in `image`, top to bottom. `languages` (BCP 47) are tried in order; empty lets Vision pick.
    public static func text(_ image: CGImage, languages: [String]) throws -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        if languages.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = languages
        }
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            return Line(string: best.string, box: topLeft(observation.boundingBox), confidence: rounded(Double(best.confidence)))
        }.sorted { ($0.box[1], $0.box[0]) < ($1.box[1], $1.box[0]) }
    }

    /// Vision's normalized rectangle (origin bottom left) as `[x, y, width, height]` from the top left, clamped to 0…1.
    public static func topLeft(_ rect: CGRect) -> [Double] {
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull else { return [0, 0, 0, 0] }
        return [clipped.minX, 1 - clipped.maxY, clipped.width, clipped.height].map { rounded(Double($0)) }
    }

    static func rounded(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
}
