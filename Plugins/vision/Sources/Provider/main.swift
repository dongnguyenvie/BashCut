// BashCut Vision: the core plugin that provides `vision.faces` (face and person boxes) and `vision.text` (on-screen
// text) with Apple Vision, so an agent can measure what is in the picture without installing anything (P2-H6, P2-H7).
// Raw boxes, confidence and time only; reading them is the agent's.
//
// Plugin API one-shot transport: `provider rpc` reads one JSON request from stdin and writes one JSON response.
import BashCutVisionAnalysis
import Foundation

func requestedSampling(_ params: [String: Any]) throws -> VisionFrames.Sampling {
    guard let path = params["mediaPath"] as? String, FileManager.default.fileExists(atPath: path) else {
        throw VisionError("The media file is missing")
    }
    return VisionFrames.Sampling(
        path: path, from: (params["fromSeconds"] as? NSNumber)?.doubleValue,
        to: (params["toSeconds"] as? NSNumber)?.doubleValue, step: (params["step"] as? NSNumber)?.doubleValue ?? 1)
}

func box(_ value: VisionDetect.Box) -> [String: Any] { ["box": value.box, "confidence": value.confidence] }

func faces(_ params: [String: Any]) async throws -> [String: Any] {
    let sampling = try requestedSampling(params)
    var frames: [[String: Any]] = []
    try await VisionFrames.forEach(sampling, maximumPixels: 1_280) { seconds, image in
        let found = try VisionDetect.subjects(image)
        frames.append(["seconds": seconds, "faces": found.faces.map(box), "people": found.people.map(box)])
    }
    return ["step": sampling.step, "frames": frames]
}

func text(_ params: [String: Any]) async throws -> [String: Any] {
    let sampling = try requestedSampling(params)
    let languages = params["languages"] as? [String] ?? []
    var frames: [[String: Any]] = []
    try await VisionFrames.forEach(sampling, maximumPixels: 1_920) { seconds, image in
        let lines = try VisionDetect.text(image, languages: languages)
        frames.append(["seconds": seconds, "text": lines.map {
            ["string": $0.string, "box": $0.box, "confidence": $0.confidence] as [String: Any]
        }])
    }
    return ["step": sampling.step, "frames": frames]
}

func handle(_ request: [String: Any]) async -> [String: Any] {
    let id = request["id"] ?? ""
    let params = request["params"] as? [String: Any] ?? [:]
    do {
        switch request["method"] as? String {
        case "vision.faces": return ["id": id, "result": try await faces(params)]
        case "vision.text": return ["id": id, "result": try await text(params)]
        default: return ["id": id, "error": ["code": "unknown_method", "message": "\(request["method"] ?? "")"]]
        }
    } catch {
        return ["id": id, "error": ["code": "analysis_failed", "message": String(describing: error)]]
    }
}

guard CommandLine.arguments.dropFirst().first == "rpc" else {
    FileHandle.standardError.write(Data("usage: provider rpc\n".utf8))
    exit(2)
}
let line = readLine(strippingNewline: true) ?? ""
let request = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:]
let response = try JSONSerialization.data(withJSONObject: await handle(request))
FileHandle.standardOutput.write(response + Data([0x0A]))
