import CoreImage
import BashCutTestSupport
import Foundation
import Testing
@testable import BashCutEngine

struct CubeFilterTests {
    private func lut(dimension: Int = 2, domain: Bool = false) throws -> CubeLUT {
        var values: [Float] = []
        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    values += [1 - Float(red) / Float(dimension - 1), Float(green) / Float(dimension - 1),
                               Float(blue) / Float(dimension - 1), 1]
                }
            }
        }
        return try values.withUnsafeBufferPointer {
            try CubeLUT(dimension: dimension, cubeData: Data(buffer: $0),
                    domainMin: domain ? [-0.5, 0, 0.2] : [0, 0, 0], domainMax: domain ? [1.5, 2, 0.8] : [1, 1, 1])
        }
    }

    @Test("64-cube filter graph benchmark")
    func benchmark() throws {
        let lut = try lut(dimension: 64)
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6))
        var times: [Double] = []
        for _ in 0..<5 {
            let start = ContinuousClock.now
            for _ in 0..<1_000 { _ = lut.apply(to: image, strength: 1).extent }
            let elapsed = start.duration(to: .now).components
            times.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
        TestMeasurement.report("CUBE_FILTER 1000_frames_median_ms=\(times.sorted()[2])")
    }

    @Test("LUT domains, blend strengths and bypass preserve reference pixels")
    func parity() throws {
        let context = CIContext()
        let input = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6))
        for customDomain in [false, true] {
            let lut = try lut(domain: customDomain)
            for strength in [0.0, 0.3, 1.0] {
                let actual = lut.apply(to: input, strength: strength)
                if strength == 0 { #expect(actual === input) }
                let reference = legacy(lut, image: input, strength: strength)
                #expect(zip(pixel(actual, context), pixel(reference, context)).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
            }
        }
    }

    @Test("Shared LUT returns immutable independent images under concurrent use")
    func concurrent() async throws {
        let lut = try lut(), context = CIContext()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<64 {
                group.addTask {
                    let value = Double(index) / 100
                    let input = CIImage(color: CIColor(red: value, green: 0.3, blue: 0.7))
                    let actual = lut.apply(to: input, strength: 1)
                    await Task.yield()
                    let expected = legacy(lut, image: input, strength: 1)
                    #expect(zip(pixel(actual, context), pixel(expected, context)).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
                }
            }
        }
    }

    private func legacy(_ lut: CubeLUT, image: CIImage, strength: Double) -> CIImage {
        let range = zip(lut.domainMin, lut.domainMax).map { Double($1 - $0) }
        let offset = zip(lut.domainMin, range).map { -Double($0) / $1 }
        let normalized = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1 / range[0], y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1 / range[1], z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1 / range[2], w: 0),
            "inputBiasVector": CIVector(x: offset[0], y: offset[1], z: offset[2], w: 0)
        ])
        let graded = normalized.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": lut.dimension, "inputCubeData": lut.cubeData])
        return strength >= 1 ? graded : image.applyingFilter(
            "CIDissolveTransition", parameters: ["inputTargetImage": graded, "inputTime": strength])
    }

    private func pixel(_ image: CIImage, _ context: CIContext) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &result, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return result
    }
}
