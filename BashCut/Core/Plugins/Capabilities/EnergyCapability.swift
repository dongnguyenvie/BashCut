import BashCutPlugin
import BashCutProject
import Foundation

/// `audio.energy` (P0-B10): how a music file's energy moves: `levelDb`, `onset` and `fullness` every `step` seconds,
/// and `candidates` [{kind lift|drop|breath, seconds, magnitude, beatSeconds?}].
public struct EnergyCapability: CapabilityAdapter {
    public static let capability = "audio.energy"
    public let mediaURL: URL
    public let count: Int?
    public let windowSeconds: Double?

    public init(mediaURL: URL, count: Int? = nil, windowSeconds: Double? = nil) {
        self.mediaURL = mediaURL
        self.count = count
        self.windowSeconds = windowSeconds
    }

    public func validate() throws {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Energy analysis source is unavailable")
        }
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        var params: [String: JSONValue] = ["mediaPath": .string(mediaURL.path)]
        if let count { params["count"] = .integer(count) }
        if let windowSeconds { params["windowSeconds"] = .number(windowSeconds) }
        return .object(params)
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> GeneratedEnergy {
        let values = result.object
        guard let step = values["step"]?.double, step > 0, step <= 10,
            ["levelDb", "onset", "fullness"].allSatisfy({ key in
                guard case .array(let list)? = values[key] else { return false }
                return list.count <= 1_000_000 && list.allSatisfy { $0.double?.isFinite == true }
            }),
            (values["candidates"]?.array ?? []).allSatisfy({
                ["lift", "drop", "breath"].contains($0.object["kind"]?.string ?? "") && $0.object["seconds"]?.double != nil
            })
        else { throw PluginError.invalid("Energy plugin returned an invalid curve or candidates") }
        return GeneratedEnergy(result: result, provenance: context.provenance)
    }
}
