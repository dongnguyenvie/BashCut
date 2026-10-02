import BashCutProject
import CoreImage
import Foundation

public struct CubeLUT: @unchecked Sendable {
    public static let maximumBytes = 16 * 1_024 * 1_024
    public let dimension: Int
    public let cubeData: Data
    public let domainMin: [Float]
    public let domainMax: [Float]

    public static func load(_ url: URL) throws -> CubeLUT {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw ProjectError.invalid("LUT must be UTF-8 and at most 16 MiB")
        }
        return try parse(text)
    }

    // Header/data variants are intentionally handled in one bounded parser.
    // swiftlint:disable:next cyclomatic_complexity
    public static func parse(_ text: String) throws -> CubeLUT {
        var dimension: Int?
        var domainMin: [Float] = [0, 0, 0]
        var domainMax: [Float] = [1, 1, 1]
        var texels: [Float] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !line.isEmpty else { continue }
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            switch parts.first?.uppercased() {
            case "TITLE": continue
            case "LUT_1D_SIZE": throw ProjectError.invalid("Only 3D .cube LUTs are supported")
            case "LUT_3D_SIZE":
                guard parts.count == 2, let value = Int(parts[1]), (2...64).contains(value) else {
                    throw ProjectError.invalid("LUT_3D_SIZE must be between 2 and 64")
                }
                dimension = value
            case "DOMAIN_MIN": domainMin = try triple(parts, label: "DOMAIN_MIN")
            case "DOMAIN_MAX": domainMax = try triple(parts, label: "DOMAIN_MAX")
            default:
                guard dimension != nil else { throw ProjectError.invalid("LUT_3D_SIZE must precede cube data") }
                let rgb = try triple(parts, label: "LUT data")
                texels += rgb + [1]
            }
        }
        guard let dimension, texels.count == dimension * dimension * dimension * 4,
            zip(domainMin, domainMax).allSatisfy({ $0 < $1 })
        else { throw ProjectError.invalid("The .cube LUT has incomplete data or an invalid domain") }
        return texels.withUnsafeBufferPointer {
            CubeLUT(
                dimension: dimension, cubeData: Data(buffer: $0),
                domainMin: domainMin, domainMax: domainMax)
        }
    }

    func apply(to image: CIImage, strength: Double) -> CIImage {
        let range = zip(domainMin, domainMax).map { Double($1 - $0) }
        let offset = zip(domainMin, range).map { -Double($0) / $1 }
        let normalized = image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1 / range[0], y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1 / range[1], z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 / range[2], w: 0),
                "inputBiasVector": CIVector(x: offset[0], y: offset[1], z: offset[2], w: 0),
            ])
        let graded = normalized.applyingFilter(
            "CIColorCube",
            parameters: ["inputCubeDimension": dimension, "inputCubeData": cubeData])
        guard strength < 1 else { return graded }
        return image.applyingFilter(
            "CIDissolveTransition",
            parameters: ["inputTargetImage": graded, "inputTime": max(0, strength)])
    }

    private static func triple(_ parts: [String], label: String) throws -> [Float] {
        let start = parts.count == 4 ? 1 : 0
        guard parts.count - start == 3 else { throw ProjectError.invalid("\(label) requires three numbers") }
        let values = parts.dropFirst(start).compactMap(Float.init)
        guard values.count == 3, values.allSatisfy(\.isFinite) else {
            throw ProjectError.invalid("\(label) contains an invalid number")
        }
        return values
    }
}
