import BashCutProject
import Foundation

public struct VoiceSynthesisTakeSpec: Sendable, Equatable {
    public let audioPath: String
    public let score: Double?

    public init(audioPath: String, score: Double? = nil) {
        self.audioPath = audioPath
        self.score = score
    }
}

public enum VoiceSynthesisResultParser {
    public static func parse(_ result: JSONValue, maximumTakes: Int = 8) throws
        -> [VoiceSynthesisTakeSpec]
    {
        guard (1...32).contains(maximumTakes) else {
            throw PluginError.invalid("Invalid voice take limit")
        }
        let values: [JSONValue]
        if let takes = result.object["takes"] {
            guard case .array(let array) = takes, !array.isEmpty, array.count <= maximumTakes else {
                throw PluginError.invalid("Voice plugin returned an invalid takes array")
            }
            values = array
        } else {
            values = [result]
        }
        var paths = Set<String>()
        return try values.map { value in
            let object = value.object
            guard let path = object["audioPath"]?.string, !path.isEmpty,
                paths.insert(path).inserted
            else { throw PluginError.invalid("Voice plugin returned an invalid or duplicate audioPath") }
            let score = object["score"]?.double
            if let score, !score.isFinite || !(0...1).contains(score) {
                throw PluginError.invalid("Voice take score must be between 0 and 1")
            }
            return VoiceSynthesisTakeSpec(audioPath: path, score: score)
        }
    }
}
