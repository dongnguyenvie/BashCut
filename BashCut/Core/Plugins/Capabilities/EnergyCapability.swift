import BashCutPlugin
import BashCutProject
import Foundation

/// `audio.energy` (P0-B10): how a music file's energy moves: `levelDb`, `onset` and `fullness` every `step` seconds.
/// Picking lifts, drops and breaths from the curve is the agent's (the flexibility audit, B14); a provider's own
/// `candidates` are ignored.
public struct EnergyCapability: CapabilityAdapter {
    public static let capability = "audio.energy"
    public let mediaURL: URL

    public init(mediaURL: URL) { self.mediaURL = mediaURL }

    public func validate() throws {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Energy analysis source is unavailable")
        }
    }

    public func params(outputDirectory: URL?) -> JSONValue { .object(["mediaPath": .string(mediaURL.path)]) }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> GeneratedEnergy {
        var values = result.object
        guard let step = values["step"]?.double, step > 0, step <= 10,
            ["levelDb", "onset", "fullness"].allSatisfy({ key in
                guard case .array(let list)? = values[key] else { return false }
                return list.count <= 1_000_000 && list.allSatisfy { $0.double?.isFinite == true }
            })
        else { throw PluginError.invalid("Energy plugin returned an invalid curve") }
        values["candidates"] = nil
        return GeneratedEnergy(result: .object(values), provenance: context.provenance)
    }
}
